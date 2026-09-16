# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# mission.sh — missions and the delegation ledger.
#
# The delegation contract has always been good prose and no mechanism: nothing in
# the state layer represented a delegation, so the Assignments table was a
# markdown table an LLM had to remember to keep in sync. It didn't, reliably.
#
# Here a charge is an event and a verdict is an event, both append-only in
# assignments.jsonl. The table in the mission brief is *rendered* from them. That
# is what makes a mission resumable a week later, and what makes "what have I
# already asked the Scout" a lookup instead of a re-read.
#
# Sourced by dave.sh.

MISSION_VERDICTS="trust partial rerun discard"

# Agent definitions live in the plugin; a harness that installs them elsewhere can
# say so rather than losing the return-format contract.
_agents_dir() {
  if [ -n "${DAVE_AGENTS_DIR:-}" ]; then printf '%s\n' "$DAVE_AGENTS_DIR"; return 0; fi
  printf '%s\n' "$PLUGIN_ROOT/agents"
}

_mission_path() { printf '%s/%s.md\n' "$MISSIONS" "$1"; }

_mission_require() {
  [ -f "$(_mission_path "$1")" ] || die "no such mission: $1 (try: mission list)"
}

# Missions created before missions.json existed still have a brief on disk. Give
# them an entry on first touch rather than treating them as broken.
_mission_register() {
  local slug="$1" project="${2:-}" ref="${3:-}"
  json_ensure "$MISSIONS_JSON" '{}'
  jq -e --arg s "$slug" 'has($s)' "$MISSIONS_JSON" >/dev/null 2>&1 && return 0
  json_edit "$MISSIONS_JSON" --arg s "$slug" --arg p "$project" --arg r "$ref" \
    --arg d "$(today)" \
    '.[$s] = {project:$p, ref:$r, status:"open", opened:$d, closed:null, outcome:null}'
}

_mission_meta() {
  [ -f "$MISSIONS_JSON" ] || { printf '{}\n'; return 0; }
  jq -c --arg s "$1" '.[$s] // {}' "$MISSIONS_JSON"
}

# --------------------------------------------------------------- markdown bits

# One section of a mission brief, with the template's HTML prompts stripped and
# surrounding blank lines trimmed. Empty output means the section was never
# filled in — which is a briefing error worth naming, not a section worth sending.
_md_section() {
  local file="$1" heading="$2"
  [ -f "$file" ] || return 0
  # Fence-aware: an agent's return format is a fenced block whose *contents* are
  # markdown headings, and a naive scan ends the section at the first one.
  awk -v h="## $heading" '
    !f && $0 == h { f = 1; next }
    f {
      if ($0 ~ /^```/) { fence = !fence; print; next }
      if (!fence && $0 ~ /^## /) { f = 0; next }
      print
    }
  ' "$file" \
    | sed -e 's/<!--[^>]*-->//g' \
    | awk 'BEGIN{n=0} {lines[n++]=$0}
           END{ s=0; e=n-1;
                while (s < n && lines[s] ~ /^[[:space:]]*$/) s++;
                while (e >= s && lines[e] ~ /^[[:space:]]*$/) e--;
                for (i = s; i <= e; i++) print lines[i] }'
}

# A section holding nothing but the template's own skeleton — an unticked `- [ ]`
# with no text after it — is empty. Counting it as filled would silence exactly
# the warning it should trigger.
_md_section_empty() {
  local body
  body="$(_md_section "$1" "$2" | sed -e 's/^[[:space:]]*[-*][[:space:]]*\[[ xX]\][[:space:]]*$//'                                       -e 's/^[[:space:]]*[-*][[:space:]]*$//')"
  [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]
}

# The section, or an explicit statement that it is empty. A blank heading tells a
# cold agent nothing; "none stated" tells it there is nothing to look for.
_md_section_or_none() {
  if _md_section_empty "$1" "$2"; then
    echo "_(none stated)_"
  else
    _md_section "$1" "$2"
  fi
}

# ------------------------------------------------------------------- dispatch

cmd_mission() {
  require_init
  need_jq
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    new)    _mission_new "$@" ;;
    show)   _mission_show "$@" ;;
    list)   _mission_list "$@" ;;
    open)   _mission_set_active "$@" ;;
    close)  _mission_close "$@" ;;
    assign) _mission_assign "$@" ;;
    record) _mission_record "$@" ;;
    status) _mission_status "$@" ;;
    pack)   _mission_pack "$@" ;;
    *) die "unknown mission subcommand: $sub (new|show|list|open|close|assign|record|status|pack)" ;;
  esac
}

_mission_new() {
  [ $# -ge 1 ] || die "usage: mission new <name> [--project P] [--ref R]"
  local name="$1"; shift
  local project="" ref=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project="${2:-}"; shift 2 ;;
      --ref)     ref="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  local slug path
  slug="$(slugify "$name")"
  path="$(_mission_path "$slug")"
  [ -f "$path" ] && die "mission already exists: $path"
  [ -n "$ref" ] && [ -z "$project" ] && project="$(_project_of_slug "$ref" 2>/dev/null || true)"
  [ -n "$project" ] || project="$(_project_resolve 2>/dev/null || true)"
  sed -e "s|{{SLUG}}|$slug|g" -e "s|{{DATE}}|$(today)|g" \
    "$TEMPLATES/mission-brief-template.md" > "$path"
  _mission_register "$slug" "$project" "$ref"
  echo "$path"
}

_mission_set_active() {
  [ $# -ge 1 ] || die "usage: mission open <slug>"
  local slug; slug="$(slugify "$1")"
  _mission_require "$slug"
  _mission_register "$slug"
  json_edit "$STATE" --arg s "$slug" '.active_mission = $s'
  echo "active mission: $slug"
}

_mission_close() {
  [ $# -ge 1 ] || die "usage: mission close <slug> [--outcome TEXT]"
  local slug; slug="$(slugify "$1")"; shift
  _mission_require "$slug"
  _mission_register "$slug"
  local outcome=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --outcome) outcome="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  local open_count
  open_count="$(_mission_open_assignments "$slug" | jq 'length')"
  json_edit "$MISSIONS_JSON" --arg s "$slug" --arg o "$outcome" --arg ts "$(now_iso)" \
    '.[$s].status = "closed" | .[$s].closed = $ts
     | .[$s].outcome = (if $o == "" then .[$s].outcome else $o end)'
  [ "$(json_get "$STATE" '.active_mission')" = "$slug" ] && \
    json_edit "$STATE" '.active_mission = null'
  echo "closed: $slug"
  # Not an error — a mission can legitimately close over an abandoned charge —
  # but silently dropping the audit trail's loose ends would be.
  [ "$open_count" -gt 0 ] && \
    echo "note: $open_count assignment(s) closed without a recorded verdict"
  return 0
}

_mission_list() {
  local only_open=0 project="" as_json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --open)    only_open=1; shift ;;
      --project) project="${2:-}"; shift 2 ;;
      --json)    as_json=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  local slugs=() f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    slugs+=("$(basename "$f" .md)")
  done < <(find "$MISSIONS" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
  if [ "${#slugs[@]}" -eq 0 ]; then
    [ "$as_json" -eq 1 ] && echo '[]' || echo "(no missions)"
    return 0
  fi

  local rows="[]" slug meta
  for slug in "${slugs[@]}"; do
    meta="$(_mission_meta "$slug")"
    rows="$(jq -c --arg s "$slug" --argjson m "$meta" \
      '. += [{slug:$s, project:($m.project // ""), ref:($m.ref // ""),
              status:($m.status // "open"), opened:($m.opened // "")}]' <<< "$rows")"
  done
  rows="$(jq -c --argjson only_open "$only_open" --arg project "$project" '
      map(select($only_open == 0 or .status == "open"))
    | map(select($project == "" or .project == $project))' <<< "$rows")"

  if [ "$as_json" -eq 1 ]; then printf '%s\n' "$rows"; return 0; fi
  local active; active="$(json_get "$STATE" '.active_mission')"
  printf '%s' "$rows" | jq -r --arg active "$active" '
    if length == 0 then "(no missions matching)" else
      map("\(if .slug == $active then "*" else " " end) \(.slug)\t\(.status)\t\(.project // "-")\t\(.ref // "-")")
      | join("\n")
    end' | { column -t -s "$(printf '\t')" 2>/dev/null || cat; }
}

# --------------------------------------------------------------- the ledger

_mission_assignments() {
  jsonl_fold "$ASSIGNMENTS" 'map(select(type == "object" and .mission == $m))' --arg m "$1"
}

# Fold the two event types into one row per charge: the last record event wins,
# and a charge with none is still open.
_mission_rows() {
  _mission_assignments "$1" | jq -c '
      (map(select(.type == "assign"))) as $a
    | (map(select(.type == "record"))) as $r
    | $a | map(. as $x
        | ($r | map(select(.id == $x.id)) | last) as $rec
        | {id: $x.id, agent: $x.agent, model: ($x.model // ""), charge: $x.charge,
           ref: ($x.ref // ""), assigned: $x.ts,
           verdict: ($rec.verdict // null), summary: ($rec.summary // ""),
           returned: ($rec.ts // null)})'
}

_mission_open_assignments() {
  _mission_rows "$1" | jq -c 'map(select(.verdict == null))'
}

_mission_assign() {
  local mission="" agent="" charge="" model="" ref=""
  # The active mission is the default, so a long session does not have to repeat
  # itself on every charge.
  if [ $# -ge 2 ] && [ -f "$(_mission_path "$(slugify "${1:-}")")" ]; then
    mission="$(slugify "$1")"; shift
  else
    mission="$(json_get "$STATE" '.active_mission')"
    [ -n "$mission" ] || die "usage: mission assign <mission> <agent> <charge>  (or: mission open <slug> first)"
  fi
  [ $# -ge 2 ] || die "usage: mission assign [mission] <agent> <charge> [--model M] [--ref R]"
  agent="$1"; charge="$2"; shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --model) model="${2:-}"; shift 2 ;;
      --ref)   ref="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  _mission_require "$mission"
  _mission_register "$mission"

  local meta n id project
  meta="$(_mission_meta "$mission")"
  project="$(printf '%s' "$meta" | jq -r '.project // ""')"
  [ -n "$ref" ] || ref="$(printf '%s' "$meta" | jq -r '.ref // ""')"
  n="$(_mission_assignments "$mission" | jq '[.[] | select(.type == "assign")] | length')"
  id="${mission}#$(( n + 1 ))"

  jsonl_append "$ASSIGNMENTS" "$(jq -nc --arg id "$id" --arg m "$mission" --arg a "$agent" \
    --arg model "$model" --arg charge "$charge" --arg ref "$ref" --arg p "$project" \
    --arg ts "$(now_iso)" \
    '{type:"assign", id:$id, mission:$m, agent:$a, model:$model, charge:$charge,
      ref:$ref, project:$p, ts:$ts}')"
  echo "$id"
}

_mission_record() {
  [ $# -ge 1 ] || die "usage: mission record <id> --verdict <$(echo "$MISSION_VERDICTS" | tr ' ' '|')> [--summary TEXT]"
  local id="$1"; shift
  local verdict="" summary=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --verdict) verdict="${2:-}"; shift 2 ;;
      --summary) summary="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [ -n "$verdict" ] || die "a verdict is required: $MISSION_VERDICTS"
  case " $MISSION_VERDICTS " in *" $verdict "*) ;; *) die "verdict must be one of: $MISSION_VERDICTS" ;; esac
  # An orphan verdict is worse than a missing one: it looks like an audit trail
  # and isn't attached to anything.
  local mission="${id%%#*}"
  _mission_assignments "$mission" | jq -e --arg id "$id" \
    'any(.[]; .type == "assign" and .id == $id)' >/dev/null 2>&1 \
    || die "no such assignment: $id (try: mission status)"
  jsonl_append "$ASSIGNMENTS" "$(jq -nc --arg id "$id" --arg m "$mission" --arg v "$verdict" \
    --arg s "$summary" --arg ts "$(now_iso)" \
    '{type:"record", id:$id, mission:$m, verdict:$v, summary:$s, ts:$ts}')"
  echo "$id: $verdict"
}

_mission_status() {
  local mission="${1:-}"
  if [ -n "$mission" ]; then
    mission="$(slugify "$mission")"
    _mission_open_assignments "$mission" | jq -r '
      if length == 0 then "(nothing outstanding)" else
        map("\(.id)  \(.agent)  — \(.charge | if length > 60 then .[0:57] + "..." else . end)")
        | join("\n") end'
    return 0
  fi
  # Every mission's outstanding charges, oldest first: what is still owed.
  jsonl_fold "$ASSIGNMENTS" '
      (map(select(.type == "assign"))) as $a
    | (map(select(.type == "record") | .id)) as $done
    | $a | map(select(([.id] | inside($done)) | not))
    | sort_by(.ts)
    | if length == 0 then ["(nothing outstanding)"] else
        map("\(.id)  \(.agent)  — \(.charge | if length > 50 then .[0:47] + "..." else . end)")
      end | .[]' | sed 's/^"//; s/"$//'
}

# ------------------------------------------------------------------ rendering

_mission_show() {
  [ $# -ge 1 ] || die "usage: mission show <slug>"
  local slug; slug="$(slugify "$1")"
  _mission_require "$slug"
  local path; path="$(_mission_path "$slug")"
  local meta; meta="$(_mission_meta "$slug")"

  # The brief, minus its Assignments table — that table is generated below rather
  # than maintained by hand, which is the whole point.
  awk '
    /^## Assignments/ { skip = 1; next }
    /^## / { skip = 0 }
    !skip { print }
  ' "$path"

  echo "## Assignments"
  echo
  local rows; rows="$(_mission_rows "$slug")"
  if [ "$(printf '%s' "$rows" | jq 'length')" -eq 0 ]; then
    echo "_(nothing delegated yet)_"
  else
    echo "| Id | Agent | Charge | Returned | Verdict |"
    echo "|---|---|---|---|---|"
    printf '%s' "$rows" | jq -r '
      .[] | "| \(.id) | \(.agent)\(if .model != "" then " (\(.model))" else "" end) "
            + "| \(.charge | gsub("\\|"; "\\\\|") | if length > 60 then .[0:57] + "..." else . end) "
            + "| \(if .returned == null then "—" else (.returned | .[0:10]) end) "
            + "| \(.verdict // "**open**")\(if (.summary // "") != "" then " — \(.summary)" else "" end) |"'
  fi

  # Log lines for the mission's ref. The ref is already the join key across
  # focus, logs and drift, so nothing new has to be stamped into the log format.
  local ref; ref="$(printf '%s' "$meta" | jq -r '.ref // ""')"
  if [ -n "$ref" ]; then
    local hits
    hits="$(grep -h -F -- "$ref" "$LOGDIR"/*.md 2>/dev/null | tail -12 || true)"
    if [ -n "$hits" ]; then
      echo
      echo "## Recent log for $ref"
      echo
      printf '%s\n' "$hits"
    fi
  fi
  return 0
}

# --------------------------------------------------------------- briefing pack

# Assembles the five-part charge from the mission brief rather than from the
# model's memory of it. The contract names part four -- the context an agent
# cannot discover -- as where delegation succeeds or fails; it is also the part
# a tired session paraphrases on the fourth charge of the day.
#
# This is a floor on quality, not a replacement for judgment: D.A.V.E. still adds
# what only he knows from the conversation.
_mission_pack() {
  [ $# -ge 1 ] || die "usage: mission pack <mission> --agent <name> [--extra TEXT]"
  local mission; mission="$(slugify "$1")"; shift
  local agent="" extra=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent="${2:-}"; shift 2 ;;
      --extra) extra="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [ -n "$agent" ] || die "which agent is this for? pass --agent <name>"
  _mission_require "$mission"
  local path; path="$(_mission_path "$mission")"
  local meta; meta="$(_mission_meta "$mission")"
  local project ref
  project="$(printf '%s' "$meta" | jq -r '.project // ""')"
  ref="$(printf '%s' "$meta" | jq -r '.ref // ""')"

  local agent_file; agent_file="$(_agents_dir)/$agent.md"
  [ -f "$agent_file" ] || die "no definition for agent '$agent' at $agent_file — a charge without a return contract is not a charge (set DAVE_AGENTS_DIR if they live elsewhere)"
  local return_format; return_format="$(_md_section "$agent_file" "Return format")"
  [ -n "$(printf '%s' "$return_format" | tr -d '[:space:]')" ] \
    || die "$agent's definition has no '## Return format' section — refusing to brief without one"

  local missing=""
  _md_section_empty "$path" "Objective"                 && missing="$missing objective"
  _md_section_empty "$path" "Definition of done"        && missing="$missing definition-of-done"
  _md_section_empty "$path" "Context the agent won't have" && missing="$missing context"

  echo "# Charge for $agent — mission $mission"
  [ -n "$ref" ] && echo "Serves: $ref"
  echo
  echo "## Objective"; echo; _md_section_or_none "$path" "Objective"; echo
  echo "## Definition of done"; echo; _md_section_or_none "$path" "Definition of done"; echo
  echo "## Constraints"; echo; _md_section_or_none "$path" "Constraints"; echo
  echo "## Context you cannot discover"; echo
  _md_section_or_none "$path" "Context the agent won't have"
  [ -n "$extra" ] && { echo; printf '%s\n' "$extra"; }

  if [ -n "$project" ] && [ -f "$PROJECTS/$project/dossier.md" ]; then
    echo
    echo "A codebase map for this project already exists — read it before exploring:"
    echo "  $PROJECTS/$project/dossier.md"
    local stale; stale="$(_dossier_staleness "$project")"
    [ -n "$stale" ] && echo "  ($stale)"
  fi

  # Prior charges on this mission, so the agent is not re-briefed into ground
  # already covered — and so a rerun knows what the last attempt got wrong.
  local prior; prior="$(_mission_rows "$mission")"
  if [ "$(printf '%s' "$prior" | jq 'length')" -gt 0 ]; then
    echo
    echo "Already asked on this mission:"
    printf '%s' "$prior" | jq -r '.[] |
      "  - \(.agent): \(.charge | if length > 80 then .[0:77] + "..." else . end)"
      + "  → \(.verdict // "still open")\(if (.summary // "") != "" then " (\(.summary))" else "" end)"'
  fi

  echo
  echo "## Return format"; echo
  printf '%s\n' "$return_format"

  if [ -n "$missing" ]; then
    echo
    echo "> **Incomplete brief.** These sections of the mission are still empty:$missing."
    echo "> Fill them in or supply them inline before sending this. An agent starts"
    echo "> cold, and the fourth section is where delegation usually fails."
  fi
  return 0
}
