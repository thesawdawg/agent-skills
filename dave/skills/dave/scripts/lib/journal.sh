# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# journal.sh — the append-only record: the day log, the parking lot, raw intake.
# Sourced by dave.sh.

cmd_park() {
  require_init
  need_jq
  [ $# -ge 1 ] || die "usage: park <text>"
  local ref
  ref="$(jq -r '.focus.ref // empty' "$STATE" 2>/dev/null || true)"
  # data.ts is local wall-clock: the rendered line's "(parked <stamp>)" and the
  # day it files under are both local concepts. The id is minted inside
  # event_append, where ts/dev/seq are all known.
  event_append "park.add" "$(jq -nc \
    --arg text "$*" --arg ref "$ref" --arg ts "$(now_iso)" \
    '{text:$text, ref:$ref, ts:$ts}')"
  echo "parked: $*"
}

# One parked item rendered the way the markdown always showed it; shared by
# `parked` and `parked done` so both number and print identically.
_parked_line() {
  jq -r 'select(.done == null)
    | "- [ ] \(.text) _(parked \(.parked_at)"
    + (if (.ref // "") != "" then ", while on \(.ref)" else "" end) + ")_"'
}

cmd_parked() {
  require_init
  need_jq
  case "${1:-}" in
    "")
      local lines
      lines="$(jq -c '.[] | select(.done == null)' "$VIEWS/parked.json" 2>/dev/null \
        | _parked_line || true)"
      [ -n "$lines" ] && printf '%s\n' "$lines" || echo "(nothing parked)"
      ;;
    done) _parked_done "${2:-}" ;;
    *) die "usage: parked [done <n>]" ;;
  esac
}

# Retires the n-th open item (1-based, counting open items in view order —
# the same numbering `parked` shows and the dashboard passes back).
_parked_done() {
  local n="$1"
  case "$n" in ''|*[!0-9]*) die "usage: parked done <n>" ;; esac
  local open
  open="$(jq -c '[.[] | select(.done == null)]' "$VIEWS/parked.json" 2>/dev/null || echo '[]')"
  local total; total="$(printf '%s' "$open" | jq 'length')"
  [ "$n" -ge 1 ] && [ "$n" -le "$total" ] || die "no such parked item: $n"
  local id text
  id="$(printf '%s' "$open" | jq -r ".[$((n - 1))].id")"
  text="$(printf '%s' "$open" | jq ".[$((n - 1))]" | _parked_line | sed 's/^- \[ \] //')"
  event_append "park.done" "$(jq -nc \
    --arg id "$id" --arg ts "$(now_iso)" '{id:$id, ts:$ts}')"
  echo "retired: $text"
}

cmd_log() {
  require_init
  need_jq
  [ $# -ge 1 ] || die "usage: log <text>"
  local ref
  ref="$(jq -r '.focus.ref // empty' "$STATE" 2>/dev/null || true)"
  event_append "log.add" "$(jq -nc \
    --arg ts "$(now_iso)" --arg ref "$ref" --arg text "$*" \
    '{ts:$ts, ref:$ref, text:$text}')"
  echo "logged"
}

cmd_today() {
  require_init
  local f; f="$LOGDIR/$(today).md"
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

# Archives a raw pasted board (read from stdin) so intake is auditable and the
# same board is never re-parsed from scratch.
cmd_intake() {
  require_init
  need_jq
  local source_name="${1:-board}"
  local path; path="$INTAKE/$(today)-$(slugify "$source_name").md"
  cat > "$path"
  event_append "intake.archive" "$(jq -nc \
    --arg ts "$(now_iso)" --arg src "$source_name" \
    '{ts:$ts, source:$src}')"
  echo "$path"
}
