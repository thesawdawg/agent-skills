# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# views.sh — derived state.
#
# The journal is the only truth; everything under .local/views/ is a cache of
# what folding every journal event produces. Readers keep the exact file
# layout they always had (state.json, notes.json, commitments.json,
# missions.json, sessions.jsonl, assignments.jsonl) — only the directory moved.
#
# Sourced by dave.sh.

# Every journal file's name + size + mtime, in one string. Cheaper than reading
# a single event; a changed journal is the only thing that can change a view.
# mtime is taken at nanosecond resolution (%y): two writes inside one second —
# a burst of events, a fast edit — must not fold into the same fingerprint.
_journal_fingerprint() {
  local f fp=""
  [ -d "$JOURNAL_DIR" ] || { printf '%s' "$fp"; return 0; }
  for f in "$JOURNAL_DIR"/*.jsonl; do
    [ -e "$f" ] || continue
    if stat -c '%s:%y' "$f" >/dev/null 2>&1; then
      fp+="$(basename "$f")=$(stat -c '%s:%y' "$f");"
    else
      fp+="$(basename "$f")=$(wc -c < "$f" | tr -d ' '):$(date -r "$f" +%s 2>/dev/null || echo 0);"
    fi
  done
  printf '%s' "$fp"
}

# All valid events across all device journals. jsonl_stream per file so a
# truncated tail line (an interrupted append, a half-synced file) is skipped
# rather than taking the whole journal down with it.
_journal_events() {
  local f
  [ -d "$JOURNAL_DIR" ] || return 0
  for f in "$JOURNAL_DIR"/*.jsonl; do
    [ -e "$f" ] || continue
    jsonl_stream "$f"
  done
}

# Runs at the top of every command (inside require_init). The fast path is one
# stat pass and a string compare; a rebuild happens only when the journals
# changed or a view file is missing. A tree with no journal/ yet is pre-journal
# — nothing to derive, and the schema check reports it as too old instead.
_views_ensure() {
  [ -d "$JOURNAL_DIR" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local stored="" missing=0 f
  [ -f "$VIEWS/.fingerprint" ] && stored="$(cat "$VIEWS/.fingerprint")"
  for f in state.json missions.json notes.json commitments.json \
           sessions.jsonl assignments.jsonl \
           log.json parked.json projects.json; do
    [ -f "$VIEWS/$f" ] || { missing=1; break; }
  done
  if [ "$missing" -eq 1 ] || [ "$(_journal_fingerprint)" != "$stored" ]; then
    views_rebuild
  fi
}

# Fold the whole journal into the six view files, each written atomically.
views_rebuild() {
  need_jq
  mkdir -p "$VIEWS" "$LOCAL"
  local created tmp
  # `created` can't come from events when the journal is empty; the device's
  # birth stamp is the closest thing the tree has to a creation time.
  created="$(json_get "$DEVICE_FILE" '.created' "$(now_iso)")"
  tmp="$(mktemp -d "$LOCAL/.views.XXXXXX")"
  _journal_events | jq -s -f "$DAVE_LIB_DIR/views.jq" \
    --arg created "$created" --argjson schema_version "$SCHEMA_VERSION" \
    > "$tmp/out.json" || { rm -rf "$tmp"; die "view rebuild failed"; }
  jq '.state'       "$tmp/out.json" > "$tmp/state.json"
  jq '.missions'    "$tmp/out.json" > "$tmp/missions.json"
  jq '.notes'       "$tmp/out.json" > "$tmp/notes.json"
  jq '.commitments' "$tmp/out.json" > "$tmp/commitments.json"
  jq '.log'         "$tmp/out.json" > "$tmp/log.json"
  jq '.parked'      "$tmp/out.json" > "$tmp/parked.json"
  jq '.projects'    "$tmp/out.json" > "$tmp/projects.json"
  jq -c '.sessions[]'    "$tmp/out.json" > "$tmp/sessions.jsonl"
  jq -c '.assignments[]' "$tmp/out.json" > "$tmp/assignments.jsonl"
  local f
  for f in state.json missions.json notes.json commitments.json \
           log.json parked.json projects.json \
           sessions.jsonl assignments.jsonl; do
    mv "$tmp/$f" "$VIEWS/$f"
  done
  _journal_fingerprint > "$VIEWS/.fingerprint"
  rm -rf "$tmp"
  # The markdown a human would have written is rendered last, from the views
  # just written — log/<date>.md and parking-lot.md under .local/render/.
  render_views
}
