# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# migrate.sh — the one-way move from the schema-2 layout to the journal tree.
#
# A schema-2 tree kept its structured state as plain files at the vault root
# and its sync transport as a git remote. This folds all of it into a separate
# import journal (journal/<device>-import.jsonl — identifiable as import data,
# never appended to afterwards), splits config into shared + device-local,
# then parks the originals under .migrated-<date>/ so nothing is deleted.
#
# Sourced by dave.sh.

# The eight root files/dirs a schema-2 tree kept. Everything else under the
# root stays where it is (priorities.md, missions/, intake/, projects/, config).
_MIGRATE_LEGACY_ITEMS=(state.json notes.json commitments.json missions.json
                       sessions.jsonl assignments.jsonl parking-lot.md log)

# The schema-2 structured JSON, packed into one import.snapshot event. The
# reducer folds it ahead of any real events, so a partially-imported journal
# (M1's importer) and a full migration produce the same starting view.
_legacy_snapshot() {
  local snap='{}' f
  for pair in "state.json:state" "notes.json:notes" "missions.json:missions"; do
    f="$DAVE_HOME/${pair%%:*}"
    [ -f "$f" ] || continue
    snap="$(jq --arg k "${pair##*:}" --slurpfile v "$f" \
      '.[$k] = $v[0]' <<< "$snap")" || continue
  done
  [ -f "$DAVE_HOME/commitments.json" ] && \
    snap="$(jq --slurpfile v "$DAVE_HOME/commitments.json" \
      '.commitments = ($v[0] | if type == "array" then . else [] end)' <<< "$snap")"
  for pair in "sessions.jsonl:sessions" "assignments.jsonl:assignments"; do
    f="$DAVE_HOME/${pair%%:*}"
    [ -f "$f" ] || continue
    snap="$(jq --arg k "${pair##*:}" --argjson v "$(jsonl_stream "$f" | jq -s .)" \
      '.[$k] = $v' <<< "$snap")"
  done
  printf '%s' "$snap"
}

# One event line for the import journal: envelope ts/seq/dev/sid controlled by
# the caller so imported history keeps its own clock.
_migrate_emit() {
  local file="$1" ts="$2" seq="$3" type="$4" data="$5" dev="$6"
  jq -nc --arg ts "$ts" --argjson seq "$seq" --arg dev "$dev" --arg sid "migrate" \
    --arg type "$type" --argjson data "$data" \
    '{ts:$ts, seq:$seq, dev:$dev, sid:$sid, type:$type, data:$data}' >> "$file"
}

# log/<date>.md -> log.add events. Entry lines are `- `HH:MM` [**REF** — ]text`;
# anything else that isn't a header/comment/blank is imported verbatim at
# 00:00 rather than dropped. data.ts is local wall-clock like cmd_log's.
_migrate_import_log() {
  local file="$1" seq="$2" dev="$3"
  local n=0 f d off
  for f in "$DAVE_HOME"/log/*.md; do
    [ -f "$f" ] || continue
    d="$(basename "$f" .md)"
    case "$d" in ????-??-??) ;; *) continue ;; esac
    off="$(date -d "$d 12:00" +%:z 2>/dev/null || date +%:z)"
    # A tab IFS would collapse the empty ref field (IFS whitespace merges), so
    # the fields come back separated by \x1f instead — never whitespace, never
    # plausibly inside a log line.
    while IFS=$'\x1f' read -r hm ref text; do
      [ -n "$text" ] || continue
      local ts_local ts_utc
      ts_local="${d}T${hm}:00${off}"
      ts_utc="$(date -ud "$ts_local" -Iseconds 2>/dev/null || now_iso_utc)"
      seq=$((seq + 1)); n=$((n + 1))
      _migrate_emit "$file" "$ts_utc" "$seq" "log.add" \
        "$(jq -nc --arg ts "$ts_local" --arg ref "$ref" --arg text "$text" \
          '{ts:$ts, ref:$ref, text:$text, imported:true}')" "$dev"
    done < <(awk '
      BEGIN { FS = "\n"; US = "\x1f" }
      /^- `[0-9][0-9]:[0-9][0-9]`/ {
        t = substr($0, 4, 5); rest = substr($0, 11); ref = ""
        if (rest ~ /^\*\*[^*]+\*\* — /) {
          sub(/^\*\*/, "", rest)
          i = index(rest, "** — ")
          ref = substr(rest, 1, i - 1)
          # The em dash is three UTF-8 bytes; byte-offset substr would land
          # inside it. Let the regex eat the separator instead.
          text = substr(rest, i); sub(/^\*\* — /, "", text)
        } else text = rest
        printf "%s%s%s%s%s\n", t, US, ref, US, text
        next
      }
      /^#/ || /^<!--/ || /^[[:space:]]*$/ { next }
      { printf "00:00%s%s%s\n", US, US, $0 }
    ' "$f")
  done
  printf '%s %s\n' "$n" "$seq"
}

# parking-lot.md -> park.add (+ park.done for `- [x]` lines). The parked stamp
# carries date+time; the retired suffix carries a date only (00:00 local).
_migrate_import_parking() {
  local file="$1" seq="$2" dev="$3"
  local n=0 done_n=0 line rest parked ref retired text ts_local ts_utc id
  [ -f "$DAVE_HOME/parking-lot.md" ] || { printf '0 0 %s\n' "$seq"; return 0; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '- [ ] '*|'- [x] '*|'- [X] '*) ;;
      *) continue ;;
    esac
    local done_flag=0
    case "$line" in '- [ ] '*) ;; *) done_flag=1 ;; esac
    rest="${line:6}"
    parked="$(printf '%s' "$rest" \
      | sed -n 's/.*_(parked \([0-9-]\{10\}\)[ ,]\([0-9:]\{5\}\)\?.*/\1 \2/p')"
    ref="$(printf '%s' "$rest" \
      | sed -n 's/.*, while on \([^)_]*\))_.*/\1/p')"
    retired="$(printf '%s' "$rest" \
      | sed -n 's/.*_(retired \([0-9-]\{10\}\))_.*/\1/p')"
    text="$(printf '%s' "$rest" \
      | sed -e 's/ *_(parked [^)]*)_//' -e 's/ *_(retired [^)]*)_//')"
    local pd="1970-01-01" ph="00:00"
    [ -n "$parked" ] && { pd="${parked%% *}"; ph="${parked##* }"; }
    local off
    off="$(date -d "$pd 12:00" +%:z 2>/dev/null || date +%:z)"
    ts_local="${pd}T${ph}:00${off}"
    ts_utc="$(date -ud "$ts_local" -Iseconds 2>/dev/null || now_iso_utc)"
    n=$((n + 1)); seq=$((seq + 1))
    id="${pd}T${ph}-import-${n}"
    _migrate_emit "$file" "$ts_utc" "$seq" "park.add" \
      "$(jq -nc --arg id "$id" --arg text "$text" --arg ref "$ref" --arg ts "$ts_local" \
        '{id:$id, text:$text, ref:$ref, ts:$ts, imported:true}')" "$dev"
    if [ "$done_flag" -eq 1 ]; then
      local rd="${retired:-$pd}" roff rts_local rts_utc
      roff="$(date -d "$rd 12:00" +%:z 2>/dev/null || date +%:z)"
      rts_local="${rd}T00:00:00${roff}"
      rts_utc="$(date -ud "$rts_local" -Iseconds 2>/dev/null || now_iso_utc)"
      done_n=$((done_n + 1)); seq=$((seq + 1))
      _migrate_emit "$file" "$rts_utc" "$seq" "park.done" \
        "$(jq -nc --arg id "$id" --arg ts "$rts_local" '{id:$id, ts:$ts}')" "$dev"
    fi
  done < "$DAVE_HOME/parking-lot.md"
  printf '%s %s %s\n' "$n" "$done_n" "$seq"
}

# project.link / project.touch events for what legacy project.json held inline:
# `refs` and `last_touched` are view data now, not document data.
_migrate_import_projects() {
  local file="$1" seq="$2" dev="$3"
  local n=0 f slug p
  for f in "$PROJECTS"/*/project.json; do
    [ -f "$f" ] || continue
    slug="$(basename "$(dirname "$f")")"
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      seq=$((seq + 1)); n=$((n + 1))
      _migrate_emit "$file" "$(now_iso_utc)" "$seq" "project.link" \
        "$(jq -nc --arg slug "$slug" --arg ref "$ref" '{slug:$slug, ref:$ref}')" "$dev"
    done < <(jq -r '.refs[]?' "$f" 2>/dev/null)
    p="$(json_get "$f" '.last_touched')"
    if [ -n "$p" ]; then
      seq=$((seq + 1)); n=$((n + 1))
      _migrate_emit "$file" "$(date -ud "$p" -Iseconds 2>/dev/null || now_iso_utc)" \
        "$seq" "project.touch" \
        "$(jq -nc --arg slug "$slug" --arg ts "$p" '{slug:$slug, ts:$ts}')" "$dev"
    fi
  done
  printf '%s %s\n' "$n" "$seq"
}

# Has any journal already imported log/park? Detects the M1-partial case:
# JSON was imported by _import_legacy but markdown was left for M5.
_migrate_logpark_imported() {
  _journal_events | jq -e \
    'any(.[]; (.type == "log.add" or .type == "park.add") and .data.imported == true)' \
    >/dev/null 2>&1
}

# Move the device-local keys out of the shared file: projects.root and
# projects.paths belong to this machine, as do hooks and sync settings.
# On any overlap the existing local value wins.
_migrate_split_config() {
  [ -f "$LOCAL_CONFIG" ] || printf '{}\n' > "$LOCAL_CONFIG"
  local moved
  moved="$(jq -c '{
      hooks: (.hooks // null),
      sync: (.sync // null),
      projects: ((.projects // {}) | {
          root: (.root // null), paths: (.paths // null)
        } | with_entries(select(.value != null)))
    } | with_entries(select(.value != null))
      | if (.projects | length) == 0 then del(.projects) else . end' "$CONFIG")"

  local tmp_s
  tmp_s="$(mktemp "$CONFIG.XXXXXX")"
  jq 'del(.hooks, .sync)
      | if .projects then .projects |= del(.root, .paths) else . end' \
      "$CONFIG" > "$tmp_s" && mv "$tmp_s" "$CONFIG" \
    || { rm -f "$tmp_s"; die "config split failed (shared)"; }

  local tmp_l
  tmp_l="$(mktemp "$LOCAL_CONFIG.XXXXXX")"
  jq -n --slurpfile l "$LOCAL_CONFIG" --argjson m "$moved" '
    ($l[0]) as $lc
    | $lc
      + (if $m.hooks != null
         then {hooks: (($m.hooks // {}) + ($lc.hooks // {}))} else {} end)
      + (if $m.sync != null
         then {sync: (($m.sync // {}) + ($lc.sync // {}))} else {} end)
      + (if $m.projects != null
         then {projects: (($lc.projects // {})
               + (if $m.projects.root != null and ($lc.projects.root // "") == ""
                  then {root: $m.projects.root} else {} end)
               + (if $m.projects.paths != null
                  then {paths: (($m.projects.paths // {}) + ($lc.projects.paths // {}))}
                  else {} end))}
         else {} end)' > "$tmp_l" && mv "$tmp_l" "$LOCAL_CONFIG" \
    || { rm -f "$tmp_l"; die "config split failed (local)"; }
}

# ------------------------------------------------------------------ cmd

# The one-way move. Idempotent: a second run on a finished tree reports
# "already migrated"; a tree where M1's importer ran but markdown was never
# folded finishes only the remaining steps.
cmd_migrate() {
  need_jq
  [ -f "$CONFIG" ] || exit 3
  mkdir -p "$LOCAL"
  # Protect local state and future migration archives before importing or
  # registering anything. The shared helper also preserves custom rules.
  _sync_prepare_ignores || die "migrate: could not prepare .stignore"
  mkdir -p "$VIEWS" "$JOURNAL_DIR" "$RENDER/log"
  device_id >/dev/null

  local has_journal=0 has_legacy=0 migrated_dir_exists=0
  compgen -G "$JOURNAL_DIR/*.jsonl" >/dev/null && has_journal=1
  _has_legacy_files && has_legacy=1
  compgen -G "$DAVE_HOME/.migrated-*" >/dev/null && migrated_dir_exists=1

  if [ "$migrated_dir_exists" -eq 1 ] && [ "$has_journal" -eq 1 ]; then
    echo "already migrated"
    return 0
  fi

  [ -f "$LOCAL_CONFIG" ] || printf '{}\n' > "$LOCAL_CONFIG"
  local dev seq=0 import_file
  dev="$(device_id)-import"
  import_file="$JOURNAL_DIR/$dev.jsonl"

  # Step 2: the JSON snapshot. Skipped when the journal already carries
  # events — that means _import_legacy (or a previous migrate) ran.
  local snap_count=0
  if [ "$has_journal" -eq 0 ] && [ "$has_legacy" -eq 1 ]; then
    local snap created_ts
    snap="$(_legacy_snapshot)"
    if [ "$snap" != '{}' ]; then
      # The snapshot's envelope ts is the legacy state's `created`, so the
      # derived view's created stamp folds to the tree's real birthday.
      created_ts="$(json_get "$DAVE_HOME/state.json" '.created')"
      created_ts="$(date -ud "${created_ts:-$(now_iso)}" -Iseconds 2>/dev/null || now_iso_utc)"
      _migrate_emit "$import_file" "$created_ts" "$seq" "import.snapshot" "$snap" "$dev"
      snap_count=1
    fi
  fi

  # Step 3: markdown import — skipped only when imported events already exist.
  local log_n=0 park_n=0 park_done_n=0 proj_n=0
  if ! _migrate_logpark_imported; then
    local r
    r="$(_migrate_import_log "$import_file" "$seq" "$dev")"
    log_n="${r%% *}"; seq="${r##* }"
    r="$(_migrate_import_parking "$import_file" "$seq" "$dev")"
    park_n="$(printf '%s' "$r" | awk '{print $1}')"
    park_done_n="$(printf '%s' "$r" | awk '{print $2}')"
    seq="$(printf '%s' "$r" | awk '{print $3}')"
  fi
  # The M1 importer never read project.json, so its refs/last_touched fields
  # become events whenever the files still carry them — stripped in step 4.
  local r
  r="$(_migrate_import_projects "$import_file" "$seq" "$dev")"
  proj_n="${r%% *}"; seq="${r##* }"

  # Step 4: config split + per-project file cleanup. The project fields are
  # stripped on every migrate path — a partial tree carries them too.
  if [ "$has_legacy" -eq 1 ]; then
    _migrate_split_config
  fi
  local f slug p
  for f in "$PROJECTS"/*/project.json; do
    [ -f "$f" ] || continue
    slug="$(basename "$(dirname "$f")")"
    p="$(json_get "$f" '.path')"
    [ -n "$p" ] && _project_path_set "$slug" "$p"
    json_edit "$f" 'del(.path, .refs, .last_touched)'
  done

  # Step 5: park the originals. Everything the import read moves to
  # .migrated-<date>/ so the migration is reversible by hand; .git/.gitignore
  # go too — the old transport's remains.
  local dest moved=()
  dest="$DAVE_HOME/.migrated-$(today)"
  if [ "$has_legacy" -eq 1 ]; then
    local item
    mkdir -p "$dest"
    for item in "${_MIGRATE_LEGACY_ITEMS[@]}"; do
      [ -e "$DAVE_HOME/$item" ] || continue
      mv "$DAVE_HOME/$item" "$dest/"
      moved+=("$item")
    done
    # Stray backups of the same files ride along rather than linger.
    for item in "$DAVE_HOME"/*.jsonl.bak-* "$DAVE_HOME"/sessions.jsonl.bak-* \
                "$DAVE_HOME"/assignments.jsonl.bak-*; do
      [ -e "$item" ] || continue
      mv "$item" "$dest/"
      moved+=("$(basename "$item")")
    done
    for item in .git .gitignore; do
      [ -e "$DAVE_HOME/$item" ] || continue
      mv "$DAVE_HOME/$item" "$dest/"
      moved+=("$item")
    done
    # A scan cache is derived but expensive; keep it in its new home.
    if [ -f "$DAVE_HOME/scan-cache.json" ] && [ ! -f "$SCAN_CACHE" ]; then
      mv "$DAVE_HOME/scan-cache.json" "$SCAN_CACHE"
    elif [ -f "$DAVE_HOME/scan-cache.json" ]; then
      mv "$DAVE_HOME/scan-cache.json" "$dest/"
      moved+=("scan-cache.json")
    fi
  fi
  # The marker dir doubles as the "already migrated" flag — it must exist even
  # when this run had nothing to move (the partial path moves no root files).
  mkdir -p "$dest"

  views_rebuild

  # Summary — including missions whose brief file never made it, a warning
  # rather than a failure.
  echo "migrated: schema 2 -> $SCHEMA_VERSION ($DAVE_HOME)"
  [ "$snap_count" -gt 0 ] && echo "  import.snapshot: state, notes, missions, commitments, sessions, assignments"
  [ "$log_n" -gt 0 ] && echo "  log.add: $log_n event(s)"
  [ "$park_n" -gt 0 ] && echo "  park.add: $park_n event(s), $park_done_n retired"
  [ "$proj_n" -gt 0 ] && echo "  project events: $proj_n"
  [ "${#moved[@]}" -gt 0 ] && echo "  moved to .migrated-$(today)/: ${moved[*]}"
  if printf '%s\n' "${moved[@]}" | grep -qx '.git'; then
    echo "  note: the old git-sync remote repo (if any) can be deleted — dave.sh no longer uses it"
  fi
  local slug
  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    [ -f "$MISSIONS/$slug.md" ] || \
      echo "  warning: mission '$slug' has no brief file (missions/$slug.md missing)"
  done < <(jq -r 'keys[]' "$MISSIONS_JSON" 2>/dev/null)
}
