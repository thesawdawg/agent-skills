# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# review.sh — the weekly sweep.
#
# Orientation is daily and already exists. This is the thing that catches a
# project going quiet, a promise about to be missed, and a charge that was sent
# out and never came back.
#
# The design constraint that matters: **computed facts and judged material are
# kept apart.** A sweep that asserts judgment from thin data will be confidently
# wrong, which is the one failure this plugin's whole persona is built to avoid.
# So the script reports what it can measure, hands over what it cannot, and says
# which is which.
#
# The second constraint: a sweep that only ever lists problems trains the user to
# stop reading it. "Quiet and fine" is a real section and it is load-bearing.
#
# Sourced by dave.sh.

# How long a project of each cadence may go quiet before it is worth a mention.
# Only `active` projects can slip at all — a maintenance project's silence is the
# arrangement working, not a finding.
_review_quiet_threshold() {
  case "$1" in
    daily)   echo 3  ;;
    weekly)  echo 14 ;;
    monthly) echo 45 ;;
    dormant) echo -1 ;;
    *)       echo 14 ;;
  esac
}

_review_days_between() {
  local from="$1" a b
  [ -n "$from" ] || { echo ""; return 0; }
  a="$(date -d "$from" +%s 2>/dev/null)" || { echo ""; return 0; }
  b="$(date +%s)"
  echo $(( (b - a) / 86400 ))
}

# Most recent log file mentioning any of these refs. The log is stamped with the
# focus ref, so this is how "was this project actually worked on" is answered
# without asking the user.
_review_last_log_mention() {
  local f ref
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    for ref in "$@"; do
      [ -n "$ref" ] || continue
      if grep -qF -- "$ref" "$f" 2>/dev/null; then basename "$f" .md; return 0; fi
    done
  done < <(find "$LOGDIR" -maxdepth 1 -name '*.md' 2>/dev/null | sort -r)
  return 0
}

_review_first_log_mention() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qF -- "$1" "$f" 2>/dev/null; then basename "$f" .md; return 0; fi
  done < <(find "$LOGDIR" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
  return 0
}

# ------------------------------------------------------------------ gathering

_review_projects() {
  local all scan slug path status cadence refs last_commit days_commit
  local touched mention last_activity days_quiet threshold out="[]"
  all="$(_projects_all)"
  scan="$(cmd_scan --all --json 2>/dev/null || echo '{}')"

  while IFS=$'\t' read -r slug status cadence touched; do
    [ -n "$slug" ] || continue
    refs="$(printf '%s' "$all" | jq -r --arg s "$slug" '.[] | select(.slug == $s) | .refs[]?' | tr '\n' ' ')"
    # shellcheck disable=SC2086
    mention="$(_review_last_log_mention $refs)"
    last_commit="$(printf '%s' "$scan" | jq -r --arg s "$slug" '.[$s].last_commit // ""')"
    days_commit="$(printf '%s' "$scan" | jq -r --arg s "$slug" '.[$s].days_since_commit // "null"')"

    # Activity is the most recent of: a commit, a log entry against one of its
    # refs, or an explicit touch. Any one of them means the project is alive.
    last_activity=""
    local candidate
    for candidate in "${last_commit:0:10}" "$mention" "${touched:0:10}"; do
      [ -n "$candidate" ] || continue
      [ -z "$last_activity" ] && { last_activity="$candidate"; continue; }
      [[ "$candidate" > "$last_activity" ]] && last_activity="$candidate"
    done
    days_quiet="$(_review_days_between "$last_activity")"
    threshold="$(_review_quiet_threshold "$cadence")"

    out="$(jq -c --arg slug "$slug" --arg status "$status" --arg cadence "$cadence" \
      --arg last_activity "$last_activity" \
      --argjson days_quiet "${days_quiet:-null}" --argjson threshold "$threshold" \
      --argjson days_commit "${days_commit:-null}" \
      --argjson probe "$(printf '%s' "$scan" | jq -c --arg s "$slug" '.[$s] // {}')" \
      '. += [{slug:$slug, status:$status, cadence:$cadence,
              last_activity:$last_activity, days_quiet:$days_quiet,
              quiet_threshold:$threshold, days_since_commit:$days_commit,
              dirty:($probe.dirty // 0), untracked:($probe.untracked // 0),
              stale_branches:($probe.stale_branches // 0),
              repo:($probe.repo // false), exists:($probe.exists // true),
              slipping:($status == "active" and $threshold >= 0
                        and $days_quiet != null and $days_quiet > $threshold)}]' \
      <<< "$out")"
  done < <(printf '%s' "$all" | jq -r '.[] | "\(.slug)\t\(.status)\t\(.cadence)\t\(.last_touched // "")"')
  printf '%s\n' "$out"
}

_review_parked() {
  local threshold cutoff
  threshold="$(config_get '.parking.review_after_days' 14)"
  cutoff="$(date -d "-${threshold} day" +%F)"
  [ -f "$PARKING" ] || { echo '[]'; return 0; }
  # Captured whole, then validated. A trailing `|| echo '[]'` on the pipeline
  # would fire whenever grep matched nothing — after jq had already printed a
  # perfectly good empty array — and emit two JSON documents.
  local out
  # Lines look like: - [ ] text _(parked YYYY-MM-DD HH:MM, while on REF)_
  out="$(grep '^- \[ \]' "$PARKING" 2>/dev/null \
    | sed -n 's/^- \[ \] \(.*\) _(parked \([0-9-]\{10\}\).*/\2\t\1/p' \
    | awk -F'\t' -v cut="$cutoff" '$1 < cut' \
    | jq -R -s '
        split("\n") | map(select(length > 0))
        | map(split("\t") | {parked: .[0], text: .[1]})' 2>/dev/null || true)"
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 || out='[]'
  printf '%s\n' "$out"
}

_review_adhoc() {
  local grace cutoff refs ref first out="[]"
  grace="$(config_get '.review.adhoc_grace_days' 5)"
  cutoff="$(date -d "-${grace} day" +%F)"
  [ -f "$PRIORITIES" ] || { echo '[]'; return 0; }
  refs="$(grep -o 'AD-[A-Za-z0-9_-]\+' "$PRIORITIES" 2>/dev/null | sort -u || true)"
  [ -n "$refs" ] || { echo '[]'; return 0; }
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    first="$(_review_first_log_mention "$ref")"
    [ -n "$first" ] || continue
    [[ "$first" < "$cutoff" ]] || continue
    out="$(jq -c --arg ref "$ref" --arg first "$first" \
      --argjson age "$(_review_days_between "$first")" \
      '. += [{ref:$ref, first_seen:$first, days:$age}]' <<< "$out")"
  done <<< "$refs"
  printf '%s\n' "$out"
}

_review_missions() {
  [ -f "$MISSIONS_JSON" ] || { echo '[]'; return 0; }
  local slugs slug last opened out="[]"
  slugs="$(jq -r 'to_entries | map(select(.value.status == "open")) | .[].key' "$MISSIONS_JSON" 2>/dev/null || true)"
  [ -n "$slugs" ] || { echo '[]'; return 0; }
  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    last="$(_mission_assignments "$slug" | jq -r 'map(.ts) | max // ""')"
    opened="$(jq -r --arg s "$slug" '.[$s].opened // ""' "$MISSIONS_JSON")"
    [ -n "$last" ] || last="$opened"
    # How long the *oldest* unanswered charge has been outstanding. A charge sent
    # an hour ago is not a finding; one sent last Tuesday and never graded is.
    local oldest oldest_days
    oldest="$(_mission_open_assignments "$slug" | jq -r 'map(.assigned) | min // ""')"
    oldest_days="$(_review_days_between "$oldest")"
    out="$(jq -c --arg slug "$slug" --arg last "$last" \
      --argjson days "$(_review_days_between "$last")" \
      --argjson open_charges "$(_mission_open_assignments "$slug" | jq 'length')" \
      --argjson oldest_days "${oldest_days:-null}" \
      '. += [{slug:$slug, last_activity:$last, days:$days,
              open_charges:$open_charges, oldest_open_days:$oldest_days}]' \
      <<< "$out")"
  done <<< "$slugs"
  printf '%s\n' "$out"
}

_review_time() {
  local since="$1"
  jsonl_fold "$SESSIONS" '
      map(select(type == "object" and .end >= $since))
    | { total: (map(.minutes) | add // 0),
        unverified: (map(select(.log_lines == 0) | .minutes) | add // 0),
        by_project: (group_by(.project // "")
          | map({project: (.[0].project // ""), minutes: (map(.minutes) | add // 0)})
          | sort_by(-.minutes)),
        by_ref: (group_by(.ref)
          | map({ref: .[0].ref, minutes: (map(.minutes) | add // 0)})
          | sort_by(-.minutes) | .[0:5]) }' --arg since "$since"
}

cmd_review() {
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
  local since since_date
  since="$(date -d "-${days} day" -Iseconds)"
  since_date="$(date -d "-${days} day" +%F)"

  local projects promises time drift missions parked adhoc blocked
  projects="$(_review_projects)"
  promises="$(_promise_list --open --json 2>/dev/null || echo '[]')"
  time="$(_review_time "$since")"
  drift="$(_drift_events --days "$days" --json 2>/dev/null || echo '[]')"
  missions="$(_review_missions)"
  parked="$(_review_parked)"
  adhoc="$(_review_adhoc)"
  # Prose, and it stays prose: which blockers have gone unchased is a judgment
  # about people, not a computation. The script surfaces the section; the model
  # reads it.
  blocked="$(awk '/^## Blocked/{f=1;next} /^## /{f=0} f' "$PRIORITIES" 2>/dev/null \
    | grep -E '^[[:space:]]*([0-9]+\.|[-*])[[:space:]]' || true)"

  local data
  data="$(jq -n \
    --arg since "$since_date" --argjson days "$days" \
    --argjson projects "$projects" --argjson promises "$promises" \
    --argjson time "$time" --argjson drift "$drift" --argjson missions "$missions" \
    --argjson parked "$parked" --argjson adhoc "$adhoc" \
    --arg blocked "$blocked" --arg today "$(today)" \
    '{window:{since:$since, days:$days}, projects:$projects, promises:$promises,
      time:$time, drift:$drift, missions:$missions, parked:$parked, adhoc:$adhoc,
      blocked:$blocked, today:$today}')"

  if [ "$as_json" -eq 1 ]; then printf '%s\n' "$data"; return 0; fi
  _review_render "$data"
}

# ----------------------------------------------------------------- rendering

_review_render() {
  # Rendered in bash rather than one enormous jq program: the ordering is the
  # message, and it needs to stay readable by whoever edits it next.
  local d="$1"
  local since total unverified
  since="$(printf '%s' "$d" | jq -r '.window.since')"
  total="$(printf '%s' "$d" | jq -r '.time.total // 0')"
  unverified="$(printf '%s' "$d" | jq -r '.time.unverified // 0')"

  printf 'Since %s: %s recorded' "$since" \
    "$(printf '%s' "$d" | jq -r "$JQ_HM"'.time.total // 0 | hm')"
  [ "${unverified:-0}" -gt 0 ] && printf ' (%s of it unverified)' \
    "$(printf '%s' "$d" | jq -r "$JQ_HM"'.time.unverified // 0 | hm')"
  printf '.\n'

  # ---- worst first
  local slipping
  slipping="$(printf '%s' "$d" | jq -r '
    [.projects[] | select(.slipping)] | sort_by(-.days_quiet) | .[] |
    "  \(.slug) — \(.cadence) cadence, nothing for \(.days_quiet)d"
    + (if .dirty > 0 then ", \(.dirty) uncommitted file(s)" else "" end)')"
  local overdue
  overdue="$(printf '%s' "$d" | jq -r --arg today "$(today)" '
    [.promises[] | select(.due < $today)] | sort_by(.due) | .[] |
    "  \(.who) — \(.what), due \(.due) (OVERDUE)"')"
  local duesoon
  duesoon="$(printf '%s' "$d" | jq -r --arg today "$(today)" '
    [.promises[] | select(.due >= $today)] | sort_by(.due) | .[] |
    "  \(.who) — \(.what), due \(.due)"')"

  if [ -n "$slipping$overdue" ]; then
    echo
    echo "Slipping:"
    [ -n "$overdue" ]  && printf '%s\n' "$overdue"
    [ -n "$slipping" ] && printf '%s\n' "$slipping"
  fi

  # ---- owed: charges and missions that went quiet
  local owed
  owed="$(printf '%s' "$d" | jq -r '
    [.missions[] | select(((.oldest_open_days // 0) >= 2) or ((.days // 0) > 7))]
    | sort_by(-((.oldest_open_days // 0))) | .[] |
    if .open_charges > 0 then
      "  \(.slug) — \(.open_charges) charge(s) outstanding, oldest sent \(.oldest_open_days)d ago"
    else
      "  \(.slug) — open, but nothing has moved in \(.days)d"
    end')"
  if [ -n "$owed" ]; then
    echo
    echo "Owed:"
    printf '%s\n' "$owed"
  fi

  # ---- rotting
  local rot_parked rot_adhoc
  rot_parked="$(printf '%s' "$d" | jq -r '
    if (.parked | length) == 0 then empty
    else "  \(.parked | length) parked item(s) older than the review threshold — oldest: \(.parked | sort_by(.parked) | .[0].text)"
    end')"
  rot_adhoc="$(printf '%s' "$d" | jq -r '
    .adhoc[]? | "  \(.ref) first logged \(.days)d ago and still has no ticket"')"
  if [ -n "$rot_parked$rot_adhoc" ]; then
    echo
    echo "Rotting:"
    [ -n "$rot_parked" ] && printf '%s\n' "$rot_parked"
    [ -n "$rot_adhoc" ]  && printf '%s\n' "$rot_adhoc"
  fi

  # ---- quiet and fine. Load-bearing: a sweep that only lists problems stops
  # being read, and then the problems stop being seen too.
  local fine
  fine="$(printf '%s' "$d" | jq -r '
    [.projects[] | select(.slipping | not)] |
    if length == 0 then empty
    else "  " + (map("\(.slug) (\(if .status == "active" then .cadence else .status end))") | join(", "))
    end')"
  if [ -n "$fine" ]; then
    echo
    echo "Quiet and fine:"
    printf '%s\n' "$fine"
  fi

  # ---- drift, as a pattern rather than a scolding
  local drift_line
  drift_line="$(printf '%s' "$d" | jq -r '
    if (.drift | length) == 0 then empty
    else "\(.drift | length) drift call(s): " +
         (.drift | group_by(.kind) | map("\(.[0].kind) ×\(length)") | join(", ")) +
         ((.drift | map(select((.project // "") != "")) | group_by(.project)
           | sort_by(-length) | .[0]) as $top
          | if $top == null or ($top | length) < 2 then ""
            else " — \($top | length) of them into \($top[0].project)" end)
    end')"
  if [ -n "$drift_line" ]; then
    echo
    printf 'Drift: %s\n' "$drift_line"
  fi

  # ---- what the script cannot decide
  echo
  echo "Needs your judgment:"
  local blocked
  blocked="$(printf '%s' "$d" | jq -r '.blocked // ""')"
  if [ -n "$blocked" ]; then
    echo "  Blocked items — which of these has nobody chased?"
    printf '%s\n' "$blocked" | sed 's/^/    /'
  else
    echo "  Nothing is marked Blocked."
  fi
  [ -n "$duesoon" ] && { echo "  Coming due:"; printf '%s\n' "$duesoon" | sed 's/^  /    /'; }
  # Stated every time, deliberately. Closure is not recorded anywhere, so any
  # claim about what finished this week is an inference from the log — and an
  # inference presented as a record is exactly the failure this sweep avoids.
  echo "  What actually closed this week is not recorded anywhere — read the log"
  echo "  and the list rather than trusting a summary of it."
  return 0
}
