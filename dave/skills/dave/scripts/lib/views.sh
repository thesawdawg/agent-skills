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
    case "$(basename "$f")" in *.sync-conflict-*) continue ;; esac
    jsonl_stream "$f"
  done
}

# Pin one complete generation. Publication and pin acquisition share a short
# lock; a per-generation lease keeps garbage collection away from active readers.
_views_pin() {
  [ -L "$LOCAL/current" ] || return 0
  local publication_fd lease_fd generation
  exec {publication_fd}>"$LOCAL/publication.lock"
  flock -s "$publication_fd" || return 1
  generation="$(readlink -f "$LOCAL/current")"
  case "$generation" in "$LOCAL"/generations/gen.*) ;; *)
    exec {publication_fd}>&-; return 1 ;;
  esac
  exec {lease_fd}>"$generation/.lease" || { exec {publication_fd}>&-; return 1; }
  flock -s "$lease_fd"
  exec {publication_fd}>&-
  if [ -n "${_VIEW_LEASE_FD:-}" ]; then exec {_VIEW_LEASE_FD}>&-; fi
  _VIEW_LEASE_FD="$lease_fd"
  _views_paths "$generation"
}

# All derived paths move together, both when staging and when pinning readers.
_views_paths() {
  VIEWS="$1/views"; RENDER="$1/render"
  STATE="$VIEWS/state.json"; NOTES="$VIEWS/notes.json"
  COMMITMENTS="$VIEWS/commitments.json"; SESSIONS="$VIEWS/sessions.jsonl"
  ASSIGNMENTS="$VIEWS/assignments.jsonl"; MISSIONS_JSON="$VIEWS/missions.json"
  PROJECTS_JSON="$VIEWS/projects.json"
  PARKING="$RENDER/parking-lot.md"; LOGDIR="$RENDER/log"
}

# Runs before state reads. Compare the signature of the input actually reduced,
# not the files that happened to exist at the end of a previous rebuild.
_views_ensure() {
  [ -d "$JOURNAL_DIR" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  command -v flock >/dev/null 2>&1 || { echo "dave: flock is required for safe state access" >&2; return 1; }
  _views_pin || return 1
  local stored="" missing=0 f
  [ -f "$VIEWS/.fingerprint" ] && stored="$(cat "$VIEWS/.fingerprint")"
  for f in state.json missions.json notes.json commitments.json sessions.jsonl \
           assignments.jsonl log.json parked.json projects.json; do
    [ -f "$VIEWS/$f" ] || { missing=1; break; }
  done
  if [ "$missing" -eq 1 ] || [ ! -L "$LOCAL/current" ] || \
     [ "$(_journal_fingerprint)" != "$stored" ]; then
    views_rebuild || return 1
  fi
}

# Publish a generation under the short publication lock, then collect only
# generations with no reader lease. Old legacy cache directories are preserved
# once for recovery; source journals and hand-edited documents never move.
_views_publish() {
  local generation="$1" publication_fd f link old lease_fd
  exec {publication_fd}>"$LOCAL/publication.lock"
  flock -x "$publication_fd" || return 1
  for f in views render; do
    if [ -d "$LOCAL/$f" ] && [ ! -L "$LOCAL/$f" ]; then
      old="$(mktemp -d "$LOCAL/legacy-$f.XXXXXX")"
      mv "$LOCAL/$f" "$old/$f" || return 1
    fi
    link="$LOCAL/.link-$f-$$"
    ln -s "current/$f" "$link" && mv -Tf "$link" "$LOCAL/$f" || return 1
  done
  link="$LOCAL/.current-$$"
  ln -s "generations/$(basename "$generation")" "$link" && \
    mv -Tf "$link" "$LOCAL/current" || return 1
  for old in "$LOCAL"/generations/gen.*; do
    [ -d "$old" ] && [ "$old" != "$generation" ] || continue
    exec {lease_fd}>"$old/.lease"
    if flock -xn "$lease_fd"; then rm -rf -- "$old"; fi
    exec {lease_fd}>&-
  done
  exec {publication_fd}>&-
}

# Called in a locked subshell: staging never repoints the caller's live paths.
_views_build_locked() (
  local created tmp before after attempt stable=0
  tmp="$(mktemp -d "$LOCAL/generations/.staging.XXXXXX")" || return 1
  trap 'rm -rf -- "$tmp"' EXIT
  for attempt in 1 2 3; do
    before="$(_journal_fingerprint)" || return 1
    if declare -F _journal_snapshot >/dev/null; then
      _journal_snapshot "$tmp/events.jsonl" "$tmp/integrity.json" || return 1
    else
      _journal_events > "$tmp/events.jsonl" || return 1
      printf '[]\n' > "$tmp/integrity.json"
    fi
    after="$(_journal_fingerprint)" || return 1
    if [ "$before" = "$after" ]; then stable=1; break; fi
  done
  if [ "$stable" -ne 1 ]; then
    echo "dave: journals changed during all three snapshot attempts; views remain stale" >&2
    return 1
  fi
  if declare -F _integrity_store >/dev/null; then
    _integrity_store "$tmp/integrity.json" || return 1
  fi
  if ! jq -e 'all(.[]; .severity != "error")' "$tmp/integrity.json" >/dev/null; then
    echo "dave: journal integrity errors; inspect sync status --json" >&2
    return 1
  fi
  created="$(json_get "$DEVICE_FILE" '.created' "$(now_iso)")"
  jq -s -f "$DAVE_LIB_DIR/views.jq" --arg created "$created" \
    --argjson schema_version "$SCHEMA_VERSION" "$tmp/events.jsonl" \
    > "$tmp/out.json" || return 1
  _views_paths "$tmp"
  mkdir -p "$VIEWS" "$RENDER/log"
  local f
  for f in state missions notes commitments log parked projects; do
    jq ".$f" "$tmp/out.json" > "$VIEWS/$f.json" || return 1
  done
  for f in sessions assignments; do
    jq -c ".${f}[]" "$tmp/out.json" > "$VIEWS/$f.jsonl" || return 1
  done
  # Forward-compatible replay diagnostics are owned by the reducer.
  jq '.identity_diagnostics // {}' "$tmp/out.json" > "$VIEWS/identity-diagnostics.json" || return 1
  cp "$tmp/integrity.json" "$VIEWS/integrity.json" || return 1
  jq '.diagnostics // []' "$tmp/out.json" > "$VIEWS/diagnostics.json" || return 1
  printf '%s' "$before" > "$VIEWS/.fingerprint"
  render_views || return 1
  rm -f "$tmp/events.jsonl" "$tmp/out.json" "$tmp/integrity.json"
  : > "$tmp/.lease"
  local generation="$LOCAL/generations/gen.${tmp##*.}"
  mv "$tmp" "$generation" || return 1
  _views_publish "$generation" || return 1
)

# Serialize local builders. Remote arrivals can still occur, so the builder
# verifies its input independently and never stamps a newer source signature.
views_rebuild() {
  need_jq
  command -v flock >/dev/null 2>&1 || { echo "dave: flock is required for rebuilding views" >&2; return 1; }
  mkdir -p "$LOCAL/generations"
  local rebuild_fd result=0
  exec {rebuild_fd}>"$LOCAL/rebuild.lock"
  flock -x "$rebuild_fd" || return 1
  _views_build_locked || result=$?
  exec {rebuild_fd}>&-
  if [ "$result" -ne 0 ]; then
    echo "dave: view rebuild failed; last complete generation retained" >&2
    return "$result"
  fi
  _views_pin
}
