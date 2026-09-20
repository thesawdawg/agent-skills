# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# state.sh — the state tree itself: creation, migration, and the composite read.
# Sourced by dave.sh.

# state.json's defaults and schema version now live in lib/views.jq — the file
# is a derived view, so a fresh tree and an imported one come out identical by
# construction rather than by sharing an upgrade program.

cmd_init() {
  need_jq
  # A tree that still carries schema-2 files must be migrated, not initialised
  # over — importing silently here would double-write once migrate runs.
  if _has_legacy_files; then
    echo "init: legacy state files found — run: dave.sh migrate" >&2
    exit 4
  fi
  mkdir -p "$DAVE_HOME" "$MISSIONS" "$INTAKE" "$PROJECTS" \
          "$LOCAL" "$VIEWS" "$JOURNAL_DIR" "$RENDER/log"
  # Receiving devices get local protection during initialization, before a
  # later setup command can register the vault with Syncthing.
  _sync_prepare_ignores || die "init: could not prepare .stignore"
  [ -f "$CONFIG" ]       || cp "$TEMPLATES/config-template.json" "$CONFIG"
  [ -f "$PRIORITIES" ]   || cp "$TEMPLATES/priorities-template.md" "$PRIORITIES"
  [ -f "$LOCAL_CONFIG" ] || printf '{}\n' > "$LOCAL_CONFIG"
  # device.json supplies the `created` fallback an empty journal can't.
  device_id >/dev/null
  views_rebuild
  echo "$DAVE_HOME"
}

cmd_home() { echo "$DAVE_HOME"; }

# The merged view the commands themselves read: shared config.json with this
# device's .local/config.json applied over it.
cmd_config() {
  require_init
  _config_merged >/dev/null
  jq . <<< "$_CONFIG_MERGED_CACHE"
}

cmd_state() {
  require_init
  cat "$STATE"
}

cmd_priorities() {
  require_init
  case "${1:-}" in
    "") cat "$PRIORITIES" ;;
    set) _priorities_set ;;
    *) die "usage: priorities [set]" ;;
  esac
}

# Replaces priorities.md wholesale from stdin — the dashboard's save path.
# Atomic via a tempfile next to the target, and a blank stream can never
# clobber the list: empty input is the signature of a broken pipe, not an edit.
_priorities_set() {
  local tmp
  tmp="$(mktemp "$PRIORITIES.XXXXXX")"
  cat > "$tmp"
  if [ -z "$(tr -d '[:space:]' < "$tmp")" ]; then
    rm -f "$tmp"
    die "priorities set: refusing to replace the list with empty input"
  fi
  mv "$tmp" "$PRIORITIES"
  echo "priorities: updated"
}

# One composite read so a session start costs a single tool call, not five.
cmd_brief() {
  require_init
  need_jq
  # Syncthing owns transport now: a brief never performs network work itself.
  # Whatever the sync layer delivered since last read is already folded into
  # the views by require_init's _views_ensure.
  echo "=== IDENTITY ==="
  _config_merged >/dev/null
  jq -r '"user: \(.user.name // "unknown")\naddress_as: \(.user.address_as // "-")\nwork_hours: \(.user.work_hours // "-")"' \
    <<< "$_CONFIG_MERGED_CACHE"
  echo
  # Project before list: orientation starts with where you are, and only then
  # with what is ranked. In an unregistered directory this stays one line.
  echo "=== PROJECT (from $PWD) ==="
  local slug; slug="$(_project_resolve)"
  if [ -z "$slug" ]; then
    echo "(this directory is not in a registered project)"
  else
    _projects_all | jq -r --arg s "$slug" '.[] | select(.slug == $s) |
      "\(.slug)\(if .name == .slug then "" else " — \(.name)" end)  ·  \(.status) · \(.cadence)",
      "goal: \(if (.goal // "") == "" then "(none set)" else .goal end)",
      "refs: \(if (.refs | length) == 0 then "(none linked)" else (.refs | join(", ")) end)"'
    # Refreshes the scan cache as a side effect, which is what leaves the hook
    # something to show without ever probing at session start itself.
    cmd_scan >/dev/null 2>&1 || true
    _scan_cached_line "$slug"
  fi
  echo
  echo "=== FOCUS ==="
  if [ "$(jq -r '.focus // "null"' "$STATE")" = "null" ]; then
    echo "(none set)"
  else
    jq -r '"ref: \(.focus.ref)\nlabel: \(.focus.label)\nstarted: \(.focus.started)"' "$STATE"
    # Captured whole rather than piped into `head -1`: closing the pipe early can
    # hand cmd_drift a SIGPIPE, which pipefail then turns into an aborted brief.
    local drift_out
    drift_out="$(cmd_drift)"
    echo "elapsed: $(printf '%s\n' "$drift_out" | head -1)"
    local focus_ref next_text
    focus_ref="$(jq -r '.focus.ref // empty' "$STATE")"
    next_text="$(_next_for "$focus_ref")"
    [ -n "$next_text" ] && echo "next: $next_text"
    jq -r 'if ((.focus_stack // []) | length) > 0
           then "stacked under it: \((.focus_stack | map(.ref) | reverse | join(", ")))"
           else empty end' "$STATE"
  fi
  echo

  # Both of the sections below are omitted entirely when empty. A brief that
  # prints "(none)" five times is a brief nobody reads to the bottom.
  local due
  due="$(_promise_list --open --due-within "$(config_get '.review.promise_horizon_days' 3)" 2>/dev/null || true)"
  if [ -n "$due" ] && [ "$due" != "(nothing matching)" ] && [ "$due" != "(no commitments recorded)" ]; then
    echo "=== PROMISED, DUE SOON ==="
    printf '%s\n' "$due"
    echo
  fi

  # Everything except the focused ref, whose note is already on the focus line.
  local notes focus_now
  focus_now="$(jq -r '.focus.ref // empty' "$STATE")"
  if [ -n "$slug" ]; then
    notes="$(_next_show --project "$slug" 2>/dev/null || true)"
  else
    notes="$(_next_show 2>/dev/null || true)"
  fi
  # Exact prefix match rather than a regex: a ref is not guaranteed to be free
  # of characters grep would read as syntax.
  [ -n "$focus_now" ] && notes="$(printf '%s\n' "$notes" | awk -v r="${focus_now}: " 'index($0, r) != 1')"
  if [ -n "$notes" ] && [ "$notes" != "(no next actions recorded)" ]; then
    echo "=== WHERE YOU LEFT OFF ==="
    printf '%s\n' "$notes" | head -5
    echo
  fi
  echo "=== PRIORITIES ==="
  cat "$PRIORITIES"
  echo
  echo "=== TODAY ($(today)) ==="
  if [ -f "$LOGDIR/$(today).md" ]; then cat "$LOGDIR/$(today).md"; else echo "(nothing logged yet)"; fi
  echo
  echo "=== PARKED (open) ==="
  local open_parked
  open_parked="$(grep -c '^- \[ \]' "$PARKING" 2>/dev/null || true)"
  echo "open items: ${open_parked:-0}"
  grep '^- \[ \]' "$PARKING" 2>/dev/null | tail -5 || true
  echo
  echo "=== LAST INTAKE ==="
  jq -r '.last_intake // "(never — priorities may be stale)"' "$STATE"
  event_append "brief.seen" "$(jq -nc --arg ts "$(now_iso)" '{ts:$ts}')"
}
