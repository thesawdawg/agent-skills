#!/usr/bin/env bash
# dave.sh - state layer for D.A.V.E. (Digital Assistant for Various Endeavors)
#
# Every piece of durable state lives under $DAVE_HOME (default ~/.dave) as plain
# markdown and JSON, so the user can read and hand-edit any of it without D.A.V.E.
# in the loop. This script is the only thing that writes there.
#
# Usage: dave.sh <command> [args]   -- run `dave.sh help` for the full list.

set -euo pipefail

DAVE_HOME="${DAVE_HOME:-$HOME/.dave}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/../templates"

CONFIG="$DAVE_HOME/config.json"
STATE="$DAVE_HOME/state.json"
PRIORITIES="$DAVE_HOME/priorities.md"
PARKING="$DAVE_HOME/parking-lot.md"
LOGDIR="$DAVE_HOME/log"
MISSIONS="$DAVE_HOME/missions"
INTAKE="$DAVE_HOME/intake"

die() { echo "dave: $*" >&2; exit 1; }

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
}

today() { date +%F; }
now_iso() { date -Iseconds; }

# Exit 3 is the agreed "not set up yet" signal, distinct from a real error.
require_init() {
  [ -f "$CONFIG" ] || exit 3
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-60
}

# Atomically replace a JSON file with the result of a jq program.
json_edit() {
  local file="$1"; shift
  local tmp
  tmp="$(mktemp "${file}.XXXXXX")"
  if jq "$@" "$file" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    die "failed to update $file"
  fi
}

cmd_init() {
  need_jq
  mkdir -p "$DAVE_HOME" "$LOGDIR" "$MISSIONS" "$INTAKE"
  [ -f "$CONFIG" ]     || cp "$TEMPLATES/config-template.json" "$CONFIG"
  [ -f "$PRIORITIES" ] || cp "$TEMPLATES/priorities-template.md" "$PRIORITIES"
  [ -f "$PARKING" ]    || printf '# Parking Lot\n\nCaptured detours, deferred ideas, and anything that pulled focus off the list.\nOpen items are `- [ ]`; retired ones `- [x]`.\n\n' > "$PARKING"
  if [ ! -f "$STATE" ]; then
    jq -n --arg ts "$(now_iso)" \
      '{focus:null, last_intake:null, last_brief:null, created:$ts, drift_events:[]}' > "$STATE"
  fi
  echo "$DAVE_HOME"
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
  echo "=== FOCUS ==="
  if [ "$(jq -r '.focus // "null"' "$STATE")" = "null" ]; then
    echo "(none set)"
  else
    jq -r '"ref: \(.focus.ref)\nlabel: \(.focus.label)\nstarted: \(.focus.started)"' "$STATE"
    echo "elapsed: $(cmd_drift | head -1)"
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

cmd_focus() {
  require_init
  need_jq
  local sub="${1:-show}"
  case "$sub" in
    set)
      [ $# -ge 2 ] || die "usage: focus set <ref> [label]"
      local ref="$2"; local label="${3:-$2}"
      json_edit "$STATE" --arg ref "$ref" --arg label "$label" --arg ts "$(now_iso)" \
        '.focus = {ref:$ref, label:$label, started:$ts}'
      echo "focus: $ref — $label"
      ;;
    clear)
      json_edit "$STATE" '.focus = null'
      echo "focus cleared"
      ;;
    show)
      jq -r 'if .focus == null then "(none set)" else "\(.focus.ref) — \(.focus.label) (since \(.focus.started))" end' "$STATE"
      ;;
    *) die "unknown focus subcommand: $sub" ;;
  esac
}

# Reports how long the current focus has been held and whether it is still
# something the priority list actually mentions. Both are inputs to a drift call,
# never a verdict on their own.
cmd_drift() {
  require_init
  need_jq
  local started ref
  started="$(jq -r '.focus.started // empty' "$STATE")"
  ref="$(jq -r '.focus.ref // empty' "$STATE")"
  if [ -z "$started" ]; then
    echo "no focus set"
    return 0
  fi
  local start_epoch now_epoch mins
  start_epoch="$(date -d "$started" +%s 2>/dev/null || echo 0)"
  now_epoch="$(date +%s)"
  mins=$(( (now_epoch - start_epoch) / 60 ))
  echo "${mins}m on focus"
  if grep -qF -- "$ref" "$PRIORITIES" 2>/dev/null; then
    echo "on-list: yes ($ref appears in priorities.md)"
  else
    echo "on-list: NO ($ref is not in priorities.md)"
  fi
}

cmd_park() {
  require_init
  [ $# -ge 1 ] || die "usage: park <text>"
  printf -- '- [ ] %s _(parked %s' "$*" "$(date '+%F %H:%M')" >> "$PARKING"
  local ref
  ref="$(jq -r '.focus.ref // empty' "$STATE" 2>/dev/null || true)"
  if [ -n "$ref" ]; then printf ', while on %s' "$ref" >> "$PARKING"; fi
  printf ')_\n' >> "$PARKING"
  echo "parked: $*"
}

cmd_parked() {
  require_init
  grep '^- \[ \]' "$PARKING" 2>/dev/null || echo "(nothing parked)"
}

cmd_log() {
  require_init
  [ $# -ge 1 ] || die "usage: log <text>"
  local f="$LOGDIR/$(today).md"
  [ -f "$f" ] || printf '# %s\n\n' "$(date '+%A, %B %-d, %Y')" > "$f"
  local ref
  ref="$(jq -r '.focus.ref // empty' "$STATE" 2>/dev/null || true)"
  if [ -n "$ref" ]; then
    printf -- '- `%s` **%s** — %s\n' "$(date '+%H:%M')" "$ref" "$*" >> "$f"
  else
    printf -- '- `%s` %s\n' "$(date '+%H:%M')" "$*" >> "$f"
  fi
  echo "logged"
}

cmd_today() {
  require_init
  local f="$LOGDIR/$(today).md"
  [ -f "$f" ] && cat "$f" || echo "(nothing logged today)"
}

# Concatenate the last N days that actually have a log file.
cmd_standup() {
  require_init
  local days="${1:-1}"
  local i=0 found=0
  while [ "$i" -lt "$days" ]; do
    local d f
    d="$(date -d "-${i} day" +%F 2>/dev/null || echo "")"
    [ -n "$d" ] || break
    f="$LOGDIR/$d.md"
    if [ -f "$f" ]; then echo "--- $d ---"; cat "$f"; echo; found=1; fi
    i=$((i + 1))
  done
  [ "$found" -eq 1 ] || echo "(no log entries in the last $days day(s))"
}

cmd_mission() {
  require_init
  local sub="${1:-list}"
  case "$sub" in
    new)
      [ $# -ge 2 ] || die "usage: mission new <name>"
      local slug path
      slug="$(slugify "$2")"
      path="$MISSIONS/$slug.md"
      [ -f "$path" ] && die "mission already exists: $path"
      sed -e "s|{{SLUG}}|$slug|g" -e "s|{{DATE}}|$(today)|g" \
        "$TEMPLATES/mission-brief-template.md" > "$path"
      echo "$path"
      ;;
    show)
      [ $# -ge 2 ] || die "usage: mission show <slug>"
      cat "$MISSIONS/$(slugify "$2").md"
      ;;
    list)
      ls -1 "$MISSIONS" 2>/dev/null | sed 's/\.md$//' || echo "(no missions)"
      ;;
    *) die "unknown mission subcommand: $sub" ;;
  esac
}

# Archives a raw pasted board (read from stdin) so intake is auditable and the
# same board is never re-parsed from scratch.
cmd_intake() {
  require_init
  need_jq
  local source_name="${1:-board}"
  local path="$INTAKE/$(today)-$(slugify "$source_name").md"
  cat > "$path"
  json_edit "$STATE" --arg ts "$(now_iso)" --arg src "$source_name" \
    '.last_intake = ($ts + " (" + $src + ")")'
  echo "$path"
}

cmd_help() {
  cat <<'HELP'
dave.sh — state layer for D.A.V.E.  (state lives in $DAVE_HOME, default ~/.dave)

  init                      create the state tree from templates (idempotent)
  home                      print the state directory path
  config                    print config.json          (exit 3 if not set up)
  state                     print state.json
  brief                     composite read: identity, focus, priorities, today, parked
  priorities                print priorities.md

  focus set <ref> [label]   set the current focus
  focus clear               clear it
  focus show                print it
  drift                     minutes on focus + whether the ref is still on the list

  park <text>               capture a detour without acting on it
  parked                    list open parked items

  log <text>                append a timestamped line to today's log
  today                     print today's log
  standup [days]            print the last N days of log (default 1)

  mission new <name>        create a mission brief from the template, print path
  mission show <slug>       print a mission brief
  mission list              list mission slugs

  intake <source>           archive a board pasted on stdin, print path
HELP
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    init) cmd_init "$@" ;;
    home) cmd_home "$@" ;;
    config) cmd_config "$@" ;;
    state) cmd_state "$@" ;;
    brief) cmd_brief "$@" ;;
    priorities) cmd_priorities "$@" ;;
    focus) cmd_focus "$@" ;;
    drift) cmd_drift "$@" ;;
    park) cmd_park "$@" ;;
    parked) cmd_parked "$@" ;;
    log) cmd_log "$@" ;;
    today) cmd_today "$@" ;;
    standup) cmd_standup "$@" ;;
    mission) cmd_mission "$@" ;;
    intake) cmd_intake "$@" ;;
    help|-h|--help) cmd_help ;;
    *) die "unknown command: $cmd (try: dave.sh help)" ;;
  esac
}

main "$@"
