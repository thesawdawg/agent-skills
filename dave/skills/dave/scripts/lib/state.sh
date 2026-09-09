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
  cat "$CONFIG"
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
  echo "=== IDENTITY ==="
  jq -r '"user: \(.user.name // "unknown")\naddress_as: \(.user.address_as // "-")\nwork_hours: \(.user.work_hours // "-")"' "$CONFIG"
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
  fi
  echo
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
  json_edit "$STATE" --arg ts "$(now_iso)" '.last_brief = $ts'
}
