# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# state.sh — the state tree itself: creation, migration, and the composite read.
# Sourced by dave.sh.

# The jq program that brings a state.json up to the current schema. Used by both
# init and migrate so a fresh tree and an upgraded one are byte-identical.
_state_upgrade_prog='
    .schema_version = $v
  | .focus         = (.focus // null)
  | .focus_stack   = (.focus_stack // [])
  | .active_mission = (.active_mission // null)
  | .drift_events  = (.drift_events // [])
  | .last_intake   = (.last_intake // null)
  | .last_brief    = (.last_brief // null)
'

cmd_init() {
  need_jq
  mkdir -p "$DAVE_HOME" "$LOGDIR" "$MISSIONS" "$INTAKE" "$PROJECTS"
  [ -f "$CONFIG" ]     || cp "$TEMPLATES/config-template.json" "$CONFIG"
  [ -f "$PRIORITIES" ] || cp "$TEMPLATES/priorities-template.md" "$PRIORITIES"
  [ -f "$PARKING" ]    || printf '# Parking Lot\n\nCaptured detours, deferred ideas, and anything that pulled focus off the list.\nOpen items are `- [ ]`; retired ones `- [x]`.\n\n' > "$PARKING"
  if [ ! -f "$STATE" ]; then
    jq -n --arg ts "$(now_iso)" \
      '{focus:null, last_intake:null, last_brief:null, created:$ts, drift_events:[]}' > "$STATE"
  fi
  json_edit "$STATE" --argjson v "$SCHEMA_VERSION" "$_state_upgrade_prog"
  echo "$DAVE_HOME"
}

# Brings an existing tree forward. Idempotent, and safe to run on a tree this
# version created.
cmd_migrate() {
  need_jq
  [ -f "$CONFIG" ] || exit 3
  mkdir -p "$DAVE_HOME" "$LOGDIR" "$MISSIONS" "$INTAKE" "$PROJECTS"
  if [ ! -f "$STATE" ]; then
    jq -n --arg ts "$(now_iso)" \
      '{focus:null, last_intake:null, last_brief:null, created:$ts, drift_events:[]}' > "$STATE"
  fi
  local from
  from="$(jq -r '.schema_version // 1' "$STATE" 2>/dev/null || echo 1)"
  json_edit "$STATE" --argjson v "$SCHEMA_VERSION" "$_state_upgrade_prog"
  echo "migrated: schema $from -> $SCHEMA_VERSION ($DAVE_HOME)"
}

cmd_home() { echo "$DAVE_HOME"; }

cmd_config() {
  require_init
  need_jq
  case "${1:-}" in
    --global)  cat "$CONFIG" ;;
    --project) [ -n "$PROJECT_HOME" ] \
                 || die "no project instance here (try: project spawn)"
               cat "$PROJECT_CONFIG" ;;
    "")        cat "$(config_effective_file)" ;;
    *)         die "unknown flag: $1 (try: config [--global|--project])" ;;
  esac
}

cmd_state() {
  require_init
  cat "$STATE"
}

cmd_priorities() {
  require_init
  cat "$PRIORITIES"
}

# One composite read so a session start costs a single tool call, not five.
cmd_brief() {
  require_init
  need_jq
  # A synced tree only stays true if the session starts by pulling it. Bounded
  # by gnet's timeouts: an offline machine degrades to local state, never a
  # hung brief.
  if sync_ready; then
    echo "=== SYNC ==="
    cmd_sync pull || echo "sync: using local state"
    echo
  fi
  echo "=== IDENTITY ==="
  jq -r '"user: \(.user.name // "unknown")\naddress_as: \(.user.address_as // "-")\nwork_hours: \(.user.work_hours // "-")"' \
    "$(config_effective_file)"
  echo
  # Project before list: orientation starts with where you are, and only then
  # with what is ranked. In an unregistered directory this stays one line.
  echo "=== PROJECT (from $PWD) ==="
  local slug; slug="$(_project_resolve)"
  if [ -z "$slug" ]; then
    echo "(this directory is not in a registered project)"
  else
    jq -r '"\(.slug)\(if .name == .slug then "" else " — \(.name)" end)  ·  \(.status) · \(.cadence)",
           "goal: \(if (.goal // "") == "" then "(none set)" else .goal end)",
           "refs: \(if (.refs | length) == 0 then "(none linked)" else (.refs | join(", ")) end)"' \
      "$(_project_file "$slug")"
    # Refreshes the scan cache as a side effect, which is what leaves the hook
    # something to show without ever probing at session start itself.
    cmd_scan >/dev/null 2>&1 || true
    _scan_cached_line "$slug"
  fi
  echo

  # A project-tuned instance overlays the global config; brief says so plainly
  # rather than letting a tuned threshold read as a changed global.
  if [ -n "$PROJECT_HOME" ]; then
    echo "=== PROJECT INSTANCE ==="
    echo "$PROJECT_HOME"
    jq -r '([keys[] | select(. != "project" and (startswith("_comment") | not))]) as $k
           | "overrides: \(if ($k|length) == 0 then "(none)" else ($k | join(", ")) end)",
             "project roles: \([.roster // {} | to_entries[] | select(.value == true) | .key] as $r
                              | if ($r|length) == 0 then "(none enabled)" else ($r | join(", ")) end)"' \
      "$PROJECT_CONFIG"
    local rules
    rules="$(_md_section "$PROJECT_BRIEF" "Rules for D.A.V.E. in this project" \
             | grep -E '^[[:space:]]*[-*][[:space:]]*[^[:space:]]' || true)"
    [ -n "$rules" ] && printf '%s\n' "$rules"
    echo
  fi
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
  # The instance's own lot stays a count-and-sample like the global one; parking
  # project-locally is for detours that mean nothing outside this directory.
  if [ -n "$PROJECT_PARKING" ] && [ -f "$PROJECT_PARKING" ]; then
    local local_parked
    local_parked="$(grep -c '^- \[ \]' "$PROJECT_PARKING" 2>/dev/null || true)"
    if [ "${local_parked:-0}" -gt 0 ]; then
      echo "project-local open items: $local_parked"
      grep '^- \[ \]' "$PROJECT_PARKING" 2>/dev/null | tail -5 || true
    fi
  fi
  echo
  echo "=== LAST INTAKE ==="
  jq -r '.last_intake // "(never — priorities may be stale)"' "$STATE"
  json_edit "$STATE" --arg ts "$(now_iso)" '.last_brief = $ts'
}
