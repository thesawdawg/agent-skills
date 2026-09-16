# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# focus.sh — what the session is pointed at, how long it has been there, and how
# far it has wandered.
#
# Focus is a stack, not a slot. A deliberate detour is a legitimate answer to a
# drift call, and answering it used to destroy the parent focus and its timer —
# so "continue" cost you the thing you were continuing from.
#
# Closing a focus writes a segment to sessions.jsonl. That ledger is what lets
# Scribe put real hours on a time entry instead of the `<needs user input>` its
# own evidence rule otherwise guarantees.
#
# Sourced by dave.sh.

DRIFT_KINDS="unlisted third-repo parked-resurfaced no-focus"
DRIFT_OUTCOMES="parked promoted continued"

# jq helper: minutes -> "6h20m". Prepended to programs that print durations.
JQ_HM='def hm: (. // 0) as $t | ($t / 60 | floor) as $h | ($t % 60 | floor) as $m
       | (if $h > 0 then "\($h)h\($m)m" else "\($m)m" end);'

# How many log lines fall inside a segment. Zero means real elapsed time with no
# evidence behind it — reported separately rather than folded into the total,
# because an over-counting ledger is worse than no ledger at all.
_count_log_lines() {
  local start="$1" end="$2" day end_day start_day count=0 f lo hi guard=0
  start_day="$(date -d "$start" +%F 2>/dev/null)" || { echo 0; return 0; }
  end_day="$(date -d "$end" +%F 2>/dev/null)"     || { echo 0; return 0; }
  day="$start_day"
  while [ "$guard" -lt 400 ]; do
    f="$LOGDIR/$day.md"
    if [ -f "$f" ]; then
      if [ "$day" = "$start_day" ]; then lo="$(date -d "$start" +%H:%M)"; else lo="00:00"; fi
      if [ "$day" = "$end_day" ];   then hi="$(date -d "$end" +%H:%M)";   else hi="23:59"; fi
      # Log lines are "- `HH:MM` ...", so HH:MM sits at offset 4 and compares
      # correctly as a string.
      count=$(( count + $(awk -v lo="$lo" -v hi="$hi" '
        /^- `[0-9][0-9]:[0-9][0-9]`/ { t = substr($0, 4, 5); if (t >= lo && t <= hi) n++ }
        END { print n+0 }' "$f") ))
    fi
    [ "$day" = "$end_day" ] && break
    day="$(date -d "$day +1 day" +%F 2>/dev/null)" || break
    guard=$((guard + 1))
  done
  printf '%s\n' "$count"
}

# Which project a ref belongs to: its explicit link first, then the directory the
# session is sitting in.
_focus_project_for() {
  local ref="$1" p=""
  p="$(_project_of_slug "$ref" 2>/dev/null || true)"
  [ -n "$p" ] || p="$(_project_resolve 2>/dev/null || true)"
  printf '%s' "$p"
}

# Append the current focus to the time ledger and stamp its project as touched.
# A no-op when nothing is focused, so every caller can call it unconditionally.
_focus_close_segment() {
  local cur; cur="$(jq -c '.focus // empty' "$STATE")"
  [ -n "$cur" ] || return 0
  local ref label project start end s e mins lines
  ref="$(printf '%s' "$cur"     | jq -r '.ref')"
  label="$(printf '%s' "$cur"   | jq -r '.label // .ref')"
  project="$(printf '%s' "$cur" | jq -r '.project // ""')"
  start="$(printf '%s' "$cur"   | jq -r '.started')"
  end="$(now_iso)"
  s="$(date -d "$start" +%s 2>/dev/null || echo 0)"
  e="$(date -d "$end" +%s)"
  [ "$s" -gt 0 ] || return 0
  mins=$(( (e - s) / 60 ))
  lines="$(_count_log_lines "$start" "$end")"
  jsonl_append "$SESSIONS" "$(jq -nc \
    --arg ref "$ref" --arg label "$label" --arg project "$project" \
    --arg start "$start" --arg end "$end" \
    --argjson minutes "$mins" --argjson log_lines "$lines" \
    '{ref:$ref, label:$label, project:$project, start:$start, end:$end,
      minutes:$minutes, log_lines:$log_lines}')"
  [ -n "$project" ] && [ -f "$(_project_file "$project")" ] && \
    json_edit "$(_project_file "$project")" --arg ts "$(now_iso)" '.last_touched = $ts'
  return 0
}

_focus_open() {
  local ref="$1" label="${2:-$1}" project
  project="$(_focus_project_for "$ref")"
  json_edit "$STATE" --arg ref "$ref" --arg label "$label" --arg project "$project" \
    --arg ts "$(now_iso)" \
    '.focus = {ref:$ref, label:$label, project:$project, started:$ts}'
}

_focus_line() {
  jq -r 'if .focus == null then "(none set)"
         else "\(.focus.ref) — \(.focus.label) (since \(.focus.started))"
              + (if (.focus.project // "") == "" then "" else "  [\(.focus.project)]" end)
         end' "$STATE"
}

cmd_focus() {
  require_init
  need_jq
  local sub="${1:-show}"
  case "$sub" in
    set)
      [ $# -ge 2 ] || die "usage: focus set <ref> [label]"
      _focus_close_segment
      _focus_open "$2" "${3:-$2}"
      echo "focus: $2 — ${3:-$2}"
      ;;
    push)
      [ $# -ge 2 ] || die "usage: focus push <ref> [label]"
      local had; had="$(jq -r '.focus.ref // empty' "$STATE")"
      _focus_close_segment
      if [ -n "$had" ]; then
        json_edit "$STATE" '.focus_stack = ((.focus_stack // []) + [.focus])'
      fi
      _focus_open "$2" "${3:-$2}"
      if [ -n "$had" ]; then
        echo "focus: $2 — ${3:-$2}  (stacked over $had)"
      else
        echo "focus: $2 — ${3:-$2}  (nothing was focused to stack)"
      fi
      ;;
    pop)
      _focus_close_segment
      local depth; depth="$(jq -r '(.focus_stack // []) | length' "$STATE")"
      if [ "$depth" -eq 0 ]; then
        json_edit "$STATE" '.focus = null | .focus_stack = []'
        echo "focus cleared (nothing stacked to return to)"
        return 0
      fi
      # Restarting the parent's clock is the point: its earlier time is already
      # banked as its own segment, and the detour must not be billed to it.
      json_edit "$STATE" --arg ts "$(now_iso)" \
        '.focus = ((.focus_stack | last) | .started = $ts)
         | .focus_stack = (.focus_stack[:-1])'
      echo "focus: $(jq -r '"\(.focus.ref) — \(.focus.label)"' "$STATE")  (returned)"
      ;;
    clear)
      _focus_close_segment
      json_edit "$STATE" '.focus = null | .focus_stack = []'
      echo "focus cleared"
      ;;
    show)
      _focus_line
      local depth; depth="$(jq -r '(.focus_stack // []) | length' "$STATE")"
      if [ "$depth" -gt 0 ]; then
        echo "stacked under it:"
        jq -r '(.focus_stack // []) | reverse | .[] | "  \(.ref) — \(.label)"' "$STATE"
      fi
      ;;
    *) die "unknown focus subcommand: $sub (set|push|pop|clear|show)" ;;
  esac
}

# ------------------------------------------------------------------ the ledger

# time [ref] [--since DATE] [--project P] [--json]
#
# Reports recorded time and, separately, how much of it has no log activity
# behind it. Scribe is forbidden from estimating hours; this is what it estimates
# *from*, caveat included.
cmd_time() {
  require_init
  need_jq
  local ref="" since="" project="" as_json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --since)   since="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      --json)    as_json=1; shift ;;
      -*) die "unknown flag: $1" ;;
      *) ref="$1"; shift ;;
    esac
  done

  local since_iso=""
  if [ -n "$since" ]; then
    since_iso="$(date -d "$since" -Iseconds 2>/dev/null)" || die "unreadable date: $since"
  fi

  local rows
  rows="$(jsonl_fold "$SESSIONS" '
      map(select(type == "object"))
    | map(select($ref == "" or .ref == $ref))
    | map(select($project == "" or .project == $project))
    | map(select($since == "" or (.end >= $since)))' \
    --arg ref "$ref" --arg project "$project" --arg since "$since_iso")"

  # The segment currently open has no end. Cap it on read rather than counting
  # wall-clock to now: a focus left set overnight is four hours flagged, not
  # sixteen asserted.
  local cap open_json="null"
  cap="$(config_get '.time.max_segment_minutes' 240)"
  local cur; cur="$(jq -c '.focus // empty' "$STATE")"
  if [ -n "$cur" ]; then
    local o_ref o_start o_mins o_project
    o_ref="$(printf '%s' "$cur" | jq -r '.ref')"
    o_project="$(printf '%s' "$cur" | jq -r '.project // ""')"
    o_start="$(printf '%s' "$cur" | jq -r '.started')"
    o_mins=$(( ( $(date +%s) - $(date -d "$o_start" +%s 2>/dev/null || date +%s) ) / 60 ))
    [ "$o_mins" -gt "$cap" ] && o_mins="$cap"
    if { [ -z "$ref" ] || [ "$ref" = "$o_ref" ]; } && { [ -z "$project" ] || [ "$project" = "$o_project" ]; }; then
      open_json="$(jq -nc --arg ref "$o_ref" --arg start "$o_start" --argjson minutes "$o_mins" \
        --argjson capped "$( [ "$o_mins" -ge "$cap" ] && echo true || echo false )" \
        '{ref:$ref, start:$start, minutes:$minutes, capped:$capped}')"
    fi
  fi

  if [ "$as_json" -eq 1 ]; then
    jq -n --argjson rows "$rows" --argjson open "$open_json" '{segments:$rows, open:$open}'
    return 0
  fi

  local summary
  summary="$(printf '%s' "$rows" | jq -r "$JQ_HM"'
      group_by(.ref) | map({
          ref: .[0].ref,
          label: .[0].label,
          total: (map(.minutes) | add // 0),
          segments: length,
          verified: (map(select(.log_lines > 0) | .minutes) | add // 0),
          unverified: (map(select(.log_lines == 0) | .minutes) | add // 0),
          unverified_segments: (map(select(.log_lines == 0)) | length)
        })
    | sort_by(-.total)
    | if length == 0 then "(nothing recorded)" else
        map(
          "\(.ref)  \(.total | hm) across \(.segments) segment\(if .segments == 1 then "" else "s" end)"
          + (if .unverified > 0 then
               "\n        \(.verified | hm) with log activity · \(.unverified | hm) unverified (\(.unverified_segments) segment\(if .unverified_segments == 1 then "" else "s" end))"
             else "" end)
        ) | join("\n")
      end')"
  printf '%s\n' "$summary"

  if [ "$open_json" != "null" ]; then
    printf '%s' "$open_json" | jq -r "$JQ_HM"'
      "        open now: \(.minutes | hm) on \(.ref)"
      + (if .capped then " (capped — a focus held this long is probably stale)" else "" end)'
  fi
}

# -------------------------------------------------------------------- drifting

cmd_drift() {
  local sub="${1:-report}"
  case "$sub" in
    record) shift; _drift_record "$@" ;;
    events) shift; _drift_events "$@" ;;
    report) _drift_report ;;
    -*|*) _drift_report ;;
  esac
}

# Reports how long the current focus has been held and whether it is still
# something the priority list actually mentions. Both are inputs to a drift call,
# never a verdict on their own.
_drift_report() {
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
  local depth; depth="$(jq -r '(.focus_stack // []) | length' "$STATE")"
  [ "$depth" -gt 0 ] && echo "stacked: $depth item(s) below this one"
  return 0
}

# One call when a drift episode resolves. A single in-session nudge is invisible
# a week later; six of them landing in the same project is a pattern worth seeing.
_drift_record() {
  require_init
  need_jq
  [ $# -ge 2 ] || die "usage: drift record <$(echo "$DRIFT_KINDS" | tr ' ' '|')> <$(echo "$DRIFT_OUTCOMES" | tr ' ' '|')> [--ref R] [--project P]"
  local kind="$1" outcome="$2"; shift 2
  case " $DRIFT_KINDS "    in *" $kind "*) ;;    *) die "kind must be one of: $DRIFT_KINDS" ;; esac
  case " $DRIFT_OUTCOMES " in *" $outcome "*) ;; *) die "outcome must be one of: $DRIFT_OUTCOMES" ;; esac
  local ref="" project=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --ref)     ref="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [ -n "$ref" ]     || ref="$(jq -r '.focus.ref // ""' "$STATE")"
  [ -n "$project" ] || project="$(jq -r '.focus.project // ""' "$STATE")"
  # Bounded: this lives inside state.json, which is read on every brief.
  json_edit "$STATE" --arg k "$kind" --arg o "$outcome" --arg r "$ref" \
    --arg p "$project" --arg ts "$(now_iso)" \
    '.drift_events = (((.drift_events // []) + [{kind:$k, outcome:$o, ref:$r, project:$p, at:$ts}]) | .[-500:])'
  echo "drift: $kind → $outcome${ref:+ ($ref)}"
}

_drift_events() {
  require_init
  need_jq
  local days=7 as_json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --days) days="${2:-7}"; shift 2 ;;
      --json) as_json=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  local since; since="$(date -d "-${days} day" -Iseconds)"
  local events
  events="$(jq -c --arg s "$since" '[(.drift_events // [])[] | select(.at >= $s)]' "$STATE")"
  if [ "$as_json" -eq 1 ]; then printf '%s\n' "$events"; return 0; fi
  printf '%s' "$events" | jq -r '
    if length == 0 then "(no drift recorded in the window)" else
      "\(length) drift call\(if length == 1 then "" else "s" end):",
      (group_by(.kind) | map("  \(.[0].kind): \(length) — " +
        (group_by(.outcome) | map("\(length) \(.[0].outcome)") | join(", "))) | .[])
    end'
}
