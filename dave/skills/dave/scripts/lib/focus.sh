# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# focus.sh — what the session is pointed at, and how far it has wandered.
# Sourced by dave.sh.

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
