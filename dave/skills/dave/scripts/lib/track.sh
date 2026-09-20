# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# track.sh — the two records D.A.V.E.'s own rules asked for and never had:
# where you left off, and what you promised someone.
#
# `next` exists because re-orientation cost is what kills systems like this. The
# ref tells you what; the note tells you where you were standing in it.
#
# `promise` exists because "a commitment made to someone" is the first ranking
# factor in the priority model — deliberately above deadlines — and until now it
# could only live as prose inside a priority line, where nothing could see it.
#
# Sourced by dave.sh.

# --------------------------------------------------------------- next actions

cmd_next() {
  require_init
  need_jq
  local sub="${1:-show}"
  shift || true
  case "$sub" in
    set)   _next_set "$@" ;;
    clear) _next_clear "$@" ;;
    show)  _next_show "$@" ;;
    *) die "unknown next subcommand: $sub (set|show|clear)" ;;
  esac
}

_next_set() {
  [ $# -ge 2 ] || die "usage: next set <ref> <text>"
  local ref="$1"; shift
  local project; project="$(_focus_project_for "$ref")"
  event_append "next.set" "$(jq -nc \
    --arg ref "$ref" --arg text "$*" --arg project "$project" \
    --arg ts "$(now_iso)" \
    '{ref:$ref, text:$text, project:$project, ts:$ts}')"
  echo "next for $ref: $*"
}

_next_clear() {
  [ $# -ge 1 ] || die "usage: next clear <ref>"
  event_append "next.clear" "$(jq -nc --arg ref "$1" '{ref:$ref}')"
  echo "cleared next for $1"
}

_next_show() {
  local ref="" project=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project="${2:-}"; shift 2 ;;
      -*) die "unknown flag: $1" ;;
      *) ref="$1"; shift ;;
    esac
  done
  [ -f "$NOTES" ] || { echo "(no next actions recorded)"; return 0; }
  # A note records the project it was written under, but that is a hint, not the
  # authority: a ref linked to a project after the fact would otherwise leave its
  # note orphaned. The project's own ref list — a derived view — wins.
  local refs_json="[]"
  if [ -n "$project" ] && [ -f "$PROJECTS_JSON" ]; then
    refs_json="$(jq -c --arg s "$project" '.[$s].refs // []' "$PROJECTS_JSON")"
  fi
  jq -r --arg ref "$ref" --arg project "$project" --argjson refs "$refs_json" '
      to_entries
    | map(select($ref == "" or .key == $ref))
    | map(select(. as $e
                 | $project == ""
                 or ($e.value.project // "") == $project
                 or (($refs | index($e.key)) != null)))
    | sort_by(.value.updated) | reverse
    | if length == 0 then "(no next actions recorded)"
      else map("\(.key): \(.value.text)") | join("\n") end' "$NOTES"
}

# The one-line form brief and the hook use. Silent when there is nothing to say.
_next_for() {
  [ -f "$NOTES" ] || return 0
  jq -r --arg ref "$1" '.[$ref].text // empty' "$NOTES" 2>/dev/null || true
}

# --------------------------------------------------------------- commitments

cmd_promise() {
  require_init
  need_jq
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    add)  _promise_add "$@" ;;
    list) _promise_list "$@" ;;
    keep) _promise_close "$1" kept ;;
    miss) _promise_close "$1" missed ;;
    move) _promise_move "$@" ;;
    repair) _promise_repair "$@" ;;
    *) die "unknown promise subcommand: $sub (add|list|keep|miss|move)" ;;
  esac
}

# Resolve a familiar display alias to the immutable identity stored in a view.
# An unsuffixed alias is accepted only when it names one row; this is the point
# at which a user's selection becomes durable event data.
_promise_entity_id() {
  local reference="${1:-}" matches count
  [ -n "$reference" ] || die "a promise id or entity_id is required"
  [ -f "$COMMITMENTS" ] || die "no commitments recorded"
  matches="$(jq -c --arg ref "$reference" \
    '[.[] | select(.entity_id == $ref or .id == $ref)]' "$COMMITMENTS")"
  count="$(printf '%s' "$matches" | jq 'length')"
  [ "$count" -gt 0 ] || die "no such commitment: $reference (try: promise list)"
  [ "$count" -eq 1 ] || die "ambiguous commitment alias: $reference (use entity_id)"
  printf '%s\n' "$matches" | jq -r '.[0].entity_id'
}

_promise_any() {
  [ -f "$COMMITMENTS" ] && jq -e 'length > 0' "$COMMITMENTS" >/dev/null 2>&1
}

_promise_require() {
  _promise_any || die "no commitments recorded"
  jq -e --arg id "$1" 'any(.[]; .id == $id)' "$COMMITMENTS" >/dev/null 2>&1 \
    || die "no such commitment: $1 (try: promise list)"
}

_promise_add() {
  [ $# -ge 3 ] || die "usage: promise add <who> <what> <due> [--ref R] [--project P]"
  local who="$1" what="$2" due="$3"; shift 3
  local ref="" project=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --ref)     ref="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  # Accepts anything `date` understands — "friday" is a perfectly good way to
  # record a promise — and normalizes to a real date so it can be compared.
  local due_norm
  due_norm="$(date -d "$due" +%F 2>/dev/null)" || die "unreadable date: $due"
  [ -n "$project" ] || project="$(_focus_project_for "${ref:-}")"

  local id entity_id effective_id
  # The display alias remains familiar, but identity is minted before append and
  # is never derived from this view-derived counter.
  id="c$(( $(jq -r '[.[].id | ltrimstr("c") | split("~")[0] | tonumber? // 0] | max // 0' "$COMMITMENTS" 2>/dev/null || echo 0) + 1 ))"
  entity_id="$(entity_id_new)"
  event_append "promise.add" "$(jq -nc \
    --arg id "$id" --arg who "$who" --arg what "$what" \
    --arg due "$due_norm" --arg ref "$ref" --arg project "$project" \
    --arg entity_id "$entity_id" --arg ts "$(now_iso)" \
    '{id:$id, entity_id:$entity_id, who:$who, what:$what, due:$due, ref:$ref, project:$project,
      status:"open", created:$ts, closed:null, moved:[]}')"
  effective_id="$(jq -r --arg eid "$entity_id" '.[] | select(.entity_id == $eid) | .id' "$COMMITMENTS" 2>/dev/null || true)"
  [ -n "$effective_id" ] || effective_id="$id"
  echo "$effective_id: promised $who — $what, due $due_norm (entity_id $entity_id)"
}

_promise_list() {
  local only_open=0 within="" as_json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --open)       only_open=1; shift ;;
      --due-within) within="${2:-}"; shift 2 ;;
      --json)       as_json=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  _promise_any || { [ "$as_json" -eq 1 ] && echo '[]' || echo "(no commitments recorded)"; return 0; }

  local horizon=""
  [ -n "$within" ] && horizon="$(date -d "+${within} day" +%F)"

  local rows
  rows="$(jq -c --argjson only_open "$only_open" --arg horizon "$horizon" '
      map(select($only_open == 0 or .status == "open"))
    | map(select($horizon == "" or (.status == "open" and .due <= $horizon)))
    | sort_by(.due)' "$COMMITMENTS")"

  if [ "$as_json" -eq 1 ]; then printf '%s\n' "$rows"; return 0; fi
  printf '%s' "$rows" | jq -r --arg today "$(today)" '
    if length == 0 then "(nothing matching)" else
      map(
        "\(.id)  \(.due)  \(.who) — \(.what)"
        + (if .ref != "" then "  [\(.ref)]" else "" end)
        + (if .status != "open" then "  (\(.status))"
           elif .due < $today then "  ** OVERDUE **"
           elif .due == $today then "  ** due today **"
           else "" end)
      ) | join("\n")
    end'
}

_promise_close() {
  [ -n "${1:-}" ] || die "usage: promise keep|miss <id>"
  local entity_id; entity_id="$(_promise_entity_id "$1")"
  local ev="promise.keep"; [ "$2" = "missed" ] && ev="promise.miss"
  event_append "$ev" "$(jq -nc \
    --arg id "$1" --arg entity_id "$entity_id" --arg s "$2" --arg ts "$(now_iso)" \
    '{id:$id, entity_id:$entity_id, status:$s, ts:$ts}')"
  echo "$1: $2"
}

# A moved promise stays open and keeps its history. Renegotiating a date is a
# normal thing to do; quietly overwriting it is how a slipped commitment stops
# looking like one.
_promise_move() {
  [ $# -ge 2 ] || die "usage: promise move <id> <new-due>"
  local entity_id; entity_id="$(_promise_entity_id "$1")"
  local due_norm
  due_norm="$(date -d "$2" +%F 2>/dev/null)" || die "unreadable date: $2"
  event_append "promise.move" "$(jq -nc \
    --arg id "$1" --arg entity_id "$entity_id" --arg due "$due_norm" --arg ts "$(now_iso)" \
    '{id:$id, entity_id:$entity_id, due:$due, ts:$ts}')"
  local times
  times="$(jq -r --arg id "$1" '.[] | select(.id == $id) | (.moved | length)' "$COMMITMENTS")"
  echo "$1: now due $due_norm (moved $times time$( [ "$times" = "1" ] || echo s ))"
}

# Record an explicit repair for an ambiguous legacy mutation. The original
# journal line remains untouched; replay joins the original envelope id to the
# selected stable entity.
_promise_repair() {
  [ $# -ge 2 ] || die "usage: promise repair <original-event-id> <entity_id>"
  local original="$1" entity_id="$2"
  [ -n "$entity_id" ] || die "entity_id is required"
  jq -e --arg eid "$entity_id" 'any(.[]; .entity_id == $eid)' "$COMMITMENTS" \
    >/dev/null 2>&1 || die "no such commitment entity_id: $entity_id"
  event_append "entity.repair" "$(jq -nc --arg original "$original" \
    --arg entity_id "$entity_id" '{original_event_id:$original, entity_id:$entity_id,
      entity_type:"promise"}')"
  echo "repair recorded: $original -> $entity_id"
}
