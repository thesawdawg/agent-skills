# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# journal.sh — the append-only record: the day log, the parking lot, raw intake.
# Sourced by dave.sh.

cmd_park() {
  require_init
  # --local lands in the project instance's own lot: a detour that only means
  # something inside this directory should not sit on the global pile forever.
  local local_park=0 words=() a
  for a in "$@"; do
    case "$a" in --local) local_park=1 ;; *) words+=("$a") ;; esac
  done
  [ "${#words[@]}" -ge 1 ] || die "usage: park <text> [--local]"
  local lot="$PARKING"
  if [ "$local_park" -eq 1 ]; then
    [ -n "$PROJECT_HOME" ] || die "no project instance here (try: project spawn)"
    lot="$PROJECT_PARKING"
    mkdir -p "$(dirname "$lot")"
    [ -f "$lot" ] || _project_parking_header "$lot"
  fi
  printf -- '- [ ] %s _(parked %s' "${words[*]}" "$(date '+%F %H:%M')" >> "$lot"
  local ref
  ref="$(jq -r '.focus.ref // empty' "$STATE" 2>/dev/null || true)"
  if [ -n "$ref" ]; then printf ', while on %s' "$ref" >> "$lot"; fi
  printf ')_\n' >> "$lot"
  echo "parked: ${words[*]}"
}

cmd_parked() {
  require_init
  grep '^- \[ \]' "$PARKING" 2>/dev/null || echo "(nothing parked)"
  if [ -n "$PROJECT_PARKING" ] && [ -f "$PROJECT_PARKING" ] \
     && grep -q '^- \[ \]' "$PROJECT_PARKING" 2>/dev/null; then
    echo "--- project-local ---"
    grep '^- \[ \]' "$PROJECT_PARKING" 2>/dev/null || true
  fi
}

cmd_log() {
  require_init
  [ $# -ge 1 ] || die "usage: log <text>"
  local f; f="$LOGDIR/$(today).md"
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
  json_edit "$STATE" --arg ts "$(now_iso)" --arg src "$source_name" \
    '.last_intake = ($ts + " (" + $src + ")")'
  echo "$path"
}
