# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# journal-core.sh — the append-only event journal.
#
# Every structured mutation is one JSON line in journal/<device-id>.jsonl, and
# that file is the only one in journal/ this device ever writes. Two devices
# (or two sessions on one device) can therefore never collide on a write, and a
# moved-in foreign journal is read-only history for the views to fold in.
#
# Event shape: {"ts":<iso-utc>,"seq":N,"dev":<id>,"sid":<session>,"type":t,"data":{...}}
# Total order is (ts, dev, seq) — the reducer's sort key.
#
# Sourced by dave.sh.

# The stable name this device writes under: <hostname-slug>-<6 hex>. Created
# once and kept in .local/device.json — .local never syncs, so the id is truly
# per-device even if the rest of the vault is copied around.
device_id() {
  local id
  id="$(json_get "$DEVICE_FILE" '.id')"
  [ -n "$id" ] && { printf '%s\n' "$id"; return 0; }
  need_jq
  mkdir -p "$LOCAL"
  local host base suffix
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo device)"
  base="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')"
  [ -n "$base" ] || base="device"
  suffix="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
  # Two sessions racing to create the file: whoever wins the mv wins the id,
  # and the loser reads the winner's rather than forking the device's identity.
  local tmp
  tmp="$(mktemp "$DEVICE_FILE.XXXXXX")"
  jq -n --arg id "$base-$suffix" --arg h "$host" --arg ts "$(now_iso)" \
    '{id:$id, hostname:$h, created:$ts}' > "$tmp"
  mv -n "$tmp" "$DEVICE_FILE" 2>/dev/null || true
  rm -f "$tmp"   # mv -n leaves the source behind when it declines to clobber
  json_get "$DEVICE_FILE" '.id' "$base-$suffix"
}

# One session = one dave.sh invocation unless the caller names a wider scope.
session_id() { printf '%s\n' "${DAVE_SESSION_ID:-$PPID}"; }

# entity_id_new — mint the opaque identity assigned to a newly created
# promise or mission charge.  It is deliberately independent of a derived
# view's numeric alias: two offline writers may choose the same c1/m#1 label,
# but they must never choose the same entity identity.
entity_id_new() {
  local random
  random="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')" \
    || die "cannot obtain collision-resistant randomness for entity identity"
  [ "${#random}" -eq 32 ] || die "cannot obtain collision-resistant randomness for entity identity"
  printf 'ent_%s\n' "$random"
}

# entity_id_is_valid — validate an identity before placing it in an event.
entity_id_is_valid() {
  case "${1:-}" in
    ent_[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
    *) return 1 ;;
  esac
}

# event_append <type> <data-json> — the single write path for structured state.
#
# seq is read-incremented inside the same flock region as the append, so two
# same-device sessions can't both claim the next number. After the append the
# process rebuilds its own views, so a command that writes twice sees its first
# event reflected when it reads for the second.
event_append() {
  local type="$1" data="$2"
  need_jq
  local dev file
  dev="$(device_id)"
  file="$JOURNAL_DIR/$dev.jsonl"
  mkdir -p "$JOURNAL_DIR" "$LOCAL"
  if command -v flock >/dev/null 2>&1; then
    (
      flock 9
      _event_write "$file" "$type" "$data" "$dev" >&9
    ) 9>>"$file"
  else
    _event_write "$file" "$type" "$data" "$dev" >> "$file"
  fi
  views_rebuild
}

# The actual append, factored out so the locked and unlocked paths share it:
# bump seq, build the envelope, terminate any truncated tail line, write.
# Whatever stream it writes to must already be redirected at the journal file.
_event_write() {
  local file="$1" type="$2" data="$3" dev="$4"
  local seq ts
  seq=$(( $(cat "$LOCAL/seq" 2>/dev/null || echo 0) + 1 ))
  printf '%s\n' "$seq" > "$LOCAL/seq"
  ts="$(now_iso_utc)"
  if [ -s "$file" ] && [ -n "$(tail -c1 "$file")" ]; then printf '\n'; fi
  jq -nc --arg ts "$ts" --argjson seq "$seq" --arg dev "$dev" \
    --arg sid "$(session_id)" --arg type "$type" --argjson data "$data" '
    # A parked item is addressed by id everywhere after this point (park.done,
    # the dashboard); `<ts>-<dev>-<seq>` is collision-free by construction and
    # only the envelope knows all three parts, so it is minted here.
    ($data + (if $type == "park.add" and ($data.id // null) == null
              then {id: ($ts + "-" + $dev + "-" + ($seq | tostring))}
              else {} end)) as $d
    | {ts:$ts, seq:$seq, dev:$dev, sid:$sid, type:$type, data:$d}'
}

# ------------------------------------------------------------------ import

# (The schema-2 → schema-3 import that used to live here as _import_legacy
# moved into lib/migrate.sh with the rest of the one-way migration.)
