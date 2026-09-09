#!/usr/bin/env bash
# run.sh — tests for the dave.sh state layer.
#
# Plain shell, no bats dependency. Every test runs against a throwaway DAVE_HOME
# under $TMPDIR, so running this can never touch the user's real ~/.dave.
#
#   ./test/run.sh            # run everything
#   ./test/run.sh focus      # run tests whose name matches a pattern

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAVE="$TEST_DIR/../dave.sh"
FILTER="${1:-}"

PASS=0; FAIL=0; FAILED_NAMES=()

# A fresh, isolated state tree per test.
new_home() {
  DAVE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/dave-test.XXXXXX")"
  export DAVE_HOME
}

dave() { "$DAVE" "$@"; }

jsonl_count() { [ -f "$1" ] && grep -c . "$1" || echo 0; }

ok() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi
}
# assert_contains <name> <haystack> <needle>
assert_contains() {
  case "$2" in *"$3"*) ok "$1" ;; *) no "$1" "output did not contain [$3]" ;; esac
}
# assert_exit <name> <expected-code> <command...>
assert_exit() {
  local name="$1" want="$2"; shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  assert_eq "$name" "$want" "$got"
}

run_test() {
  local name="$1"
  [ -z "$FILTER" ] || case "$name" in *"$FILTER"*) ;; *) return 0 ;; esac
  printf '%s\n' "$name"
  new_home
  "test_${name//[^a-zA-Z0-9]/_}"
  rm -rf "$DAVE_HOME"
}

# --------------------------------------------------------------------- setup

test_init() {
  local out; out="$(dave init)"
  assert_eq "init prints the home path" "$DAVE_HOME" "$out"
  assert_eq "init writes schema_version" "2" "$(jq -r .schema_version "$DAVE_HOME/state.json")"
  for f in config.json state.json priorities.md parking-lot.md; do
    [ -f "$DAVE_HOME/$f" ] && ok "init creates $f" || no "init creates $f" "missing"
  done
  for d in log missions intake projects; do
    [ -d "$DAVE_HOME/$d" ] && ok "init creates $d/" || no "init creates $d/" "missing"
  done
}

test_init_idempotent() {
  dave init >/dev/null
  echo "hand-edited" >> "$DAVE_HOME/priorities.md"
  local before; before="$(cat "$DAVE_HOME/priorities.md")"
  dave init >/dev/null
  assert_eq "init does not clobber priorities.md" "$before" "$(cat "$DAVE_HOME/priorities.md")"
}

test_not_set_up_exits_3() {
  assert_exit "config on an empty home exits 3" 3 dave config
  assert_exit "brief on an empty home exits 3" 3 dave brief
}

test_migrate() {
  # Build a v1 tree by hand: no schema_version, no projects dir, focus held.
  mkdir -p "$DAVE_HOME/log" "$DAVE_HOME/missions" "$DAVE_HOME/intake"
  cp "$TEST_DIR/../../templates/config-template.json" "$DAVE_HOME/config.json"
  cp "$TEST_DIR/../../templates/priorities-template.md" "$DAVE_HOME/priorities.md"
  jq -n '{focus:{ref:"RM-1",label:"old work",started:"2026-01-01T09:00:00+00:00"},
          last_intake:"2026-01-01 (board)", last_brief:null,
          created:"2026-01-01T08:00:00+00:00", drift_events:[]}' > "$DAVE_HOME/state.json"

  assert_exit "a v1 tree exits 4" 4 dave state
  local out; out="$(dave migrate)"
  assert_contains "migrate reports the version change" "$out" "schema 1 -> 2"
  assert_eq "migrate stamps the version" "2" "$(jq -r .schema_version "$DAVE_HOME/state.json")"
  assert_eq "migrate preserves focus"    "RM-1" "$(jq -r .focus.ref "$DAVE_HOME/state.json")"
  assert_eq "migrate preserves last_intake" "2026-01-01 (board)" "$(jq -r .last_intake "$DAVE_HOME/state.json")"
  assert_eq "migrate adds focus_stack"   "0" "$(jq -r '.focus_stack|length' "$DAVE_HOME/state.json")"
  assert_eq "migrate adds active_mission" "null" "$(jq -r '.active_mission' "$DAVE_HOME/state.json")"
  [ -d "$DAVE_HOME/projects" ] && ok "migrate creates projects/" || no "migrate creates projects/" "missing"

  local after; after="$(cat "$DAVE_HOME/state.json")"
  dave migrate >/dev/null
  assert_eq "migrate is idempotent" "$after" "$(cat "$DAVE_HOME/state.json")"
  assert_exit "a migrated tree stops exiting 4" 0 dave state
}

# --------------------------------------------------------------------- focus

test_focus() {
  dave init >/dev/null
  assert_contains "focus show with none set" "$(dave focus show)" "(none set)"
  dave focus set RM-4471 "retry double-fire" >/dev/null
  assert_contains "focus show after set" "$(dave focus show)" "RM-4471 — retry double-fire"
  assert_eq "focus is stored" "RM-4471" "$(jq -r .focus.ref "$DAVE_HOME/state.json")"
  dave focus clear >/dev/null
  assert_eq "focus clear empties it" "null" "$(jq -r '.focus // "null"' "$DAVE_HOME/state.json")"
}

test_drift() {
  dave init >/dev/null
  assert_contains "drift with no focus" "$(dave drift)" "no focus set"
  dave focus set RM-4471 "retry" >/dev/null
  local out; out="$(dave drift)"
  assert_contains "drift reports minutes" "$out" "m on focus"
  assert_contains "drift flags an unlisted ref" "$out" "on-list: NO"
  printf '\n1. **RM-4471** — retry\n' >> "$DAVE_HOME/priorities.md"
  assert_contains "drift sees a listed ref" "$(dave drift)" "on-list: yes"
}

# ------------------------------------------------------------------- capture

test_journal() {
  dave init >/dev/null
  dave focus set RM-4471 "retry" >/dev/null
  dave log "traced it to the retry middleware" >/dev/null
  assert_contains "log stamps the focus ref" "$(dave today)" "**RM-4471**"
  assert_contains "log keeps the text" "$(dave today)" "traced it to the retry middleware"
  dave park "rewrite the CSV exporter" >/dev/null
  local parked; parked="$(dave parked)"
  assert_contains "park records the item" "$parked" "rewrite the CSV exporter"
  assert_contains "park stamps what it pulled against" "$parked" "while on RM-4471"
  assert_contains "standup covers today" "$(dave standup 1)" "retry middleware"
  assert_contains "standup with no history" "$(dave standup 99)" "retry middleware"
}

test_intake() {
  dave init >/dev/null
  local path; path="$(printf 'Doing\n- SSO rollout\n' | dave intake "platform board")"
  [ -f "$path" ] && ok "intake archives the raw board" || no "intake archives the raw board" "no file at $path"
  assert_contains "intake keeps the text verbatim" "$(cat "$path")" "SSO rollout"
  assert_contains "intake stamps last_intake" "$(jq -r .last_intake "$DAVE_HOME/state.json")" "platform board"
}

test_mission() {
  dave init >/dev/null
  local path; path="$(dave mission new "SSO rollout")"
  assert_contains "mission new returns a slugged path" "$path" "sso-rollout.md"
  assert_contains "mission show renders the template" "$(dave mission show sso-rollout)" "# Mission: sso-rollout"
  assert_contains "mission list names it" "$(dave mission list)" "sso-rollout"
  assert_exit "mission new refuses a duplicate" 1 dave mission new "SSO rollout"
}

test_brief() {
  dave init >/dev/null
  dave focus set RM-4471 "retry" >/dev/null
  dave log "something happened" >/dev/null
  local out; out="$(dave brief)"
  assert_contains "brief says when there is no project" "$out" "not in a registered project"
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler"
  dave project add "$root/webcrawler" --goal "crawl politely" >/dev/null
  dave project link webcrawler RM-4471 >/dev/null
  local inproj; inproj="$(cd "$root/webcrawler" && dave brief)"
  assert_contains "brief resolves the project from cwd" "$inproj" "webcrawler  ·  active"
  assert_contains "brief shows the project goal" "$inproj" "crawl politely"
  assert_contains "brief shows linked refs" "$inproj" "refs: RM-4471"

  for section in "=== IDENTITY ===" "=== PROJECT" "=== FOCUS ===" "=== PRIORITIES ===" "=== TODAY" "=== PARKED (open) ===" "=== LAST INTAKE ==="; do
    assert_contains "brief has $section" "$out" "$section"
  done
  assert_contains "brief reports elapsed time" "$out" "elapsed:"
  assert_contains "brief stamps last_brief" "$(jq -r .last_brief "$DAVE_HOME/state.json")" "-"
}

# ------------------------------------------------------------------ projects

test_project() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler/src/deep"
  assert_contains "project list when empty" "$(dave project list)" "(no projects registered"

  local out; out="$(dave project add "$root/webcrawler" --goal "crawl politely" --cadence daily)"
  assert_contains "project add confirms" "$out" "registered: webcrawler"
  assert_eq "project add stores a canonical path" "$root/webcrawler" \
    "$(jq -r .path "$DAVE_HOME/projects/webcrawler/project.json")"
  assert_eq "project add defaults status" "active" \
    "$(jq -r .status "$DAVE_HOME/projects/webcrawler/project.json")"
  assert_eq "project add takes cadence" "daily" \
    "$(jq -r .cadence "$DAVE_HOME/projects/webcrawler/project.json")"

  assert_contains "project list shows it" "$(dave project list)" "webcrawler"
  assert_exit "project add refuses a duplicate slug" 1 dave project add "$root/webcrawler"
  mkdir -p "$root/other"
  assert_exit "project add refuses a duplicate path" 1 \
    dave project add "$root/webcrawler" --slug second
  assert_exit "project add refuses a non-directory" 1 dave project add "$root/nope"
  assert_exit "project add validates cadence" 1 dave project add "$root/other" --cadence hourly
  assert_exit "project add validates status" 1 dave project add "$root/other" --status busy

  dave project status webcrawler paused >/dev/null
  assert_eq "project status changes it" "paused" \
    "$(jq -r .status "$DAVE_HOME/projects/webcrawler/project.json")"
  assert_exit "project status validates" 1 dave project status webcrawler elsewhere
  assert_contains "project list filters by status" "$(dave project list --status paused)" "webcrawler"
  assert_eq "project list --status excludes" "0" \
    "$(dave project list --status active --json | jq length)"

  dave project link webcrawler RM-4471 >/dev/null
  dave project link webcrawler RM-4471 >/dev/null   # idempotent
  assert_eq "project link is a set" "1" \
    "$(jq -r '.refs | length' "$DAVE_HOME/projects/webcrawler/project.json")"
  assert_eq "project of finds the owner" "webcrawler" "$(dave project of RM-4471)"
  assert_eq "project of an unlinked ref is silent" "" "$(dave project of RM-9999)"

  dave project add "$root/other" >/dev/null
  assert_exit "project link refuses a ref owned elsewhere" 1 dave project link other RM-4471
  dave project unlink webcrawler RM-4471 >/dev/null
  assert_eq "project unlink removes it" "0" \
    "$(jq -r '.refs | length' "$DAVE_HOME/projects/webcrawler/project.json")"

  assert_exit "project show on an unknown slug fails" 1 dave project show nosuch

  # A directory name that slugifies must still find its project — the user should
  # not have to remember what registration did to the name.
  mkdir -p "$root/dnd_5e_api"
  dave project add "$root/dnd_5e_api" >/dev/null
  assert_eq "add slugifies the directory name" "dnd-5e-api" \
    "$(jq -r .slug "$DAVE_HOME/projects/dnd-5e-api/project.json")"
  assert_exit "status accepts the raw directory name" 0 dave project status dnd_5e_api paused
  assert_eq "the raw name reached the right project" "paused" \
    "$(jq -r .status "$DAVE_HOME/projects/dnd-5e-api/project.json")"
  assert_exit "show accepts the raw directory name" 0 dave project show dnd_5e_api
  assert_exit "link accepts the raw directory name" 0 dave project link dnd_5e_api RM-77
  local show; show="$(dave project show webcrawler)"
  assert_contains "project show has the header" "$show" "=== PROJECT ==="
  assert_contains "project show reports goal" "$show" "crawl politely"
  assert_contains "project show handles a non-repo" "$show" "(not a git repository)"

  # A linked ref that the priority list no longer mentions is surfaced, not hidden.
  dave project link webcrawler RM-4471 >/dev/null
  assert_contains "project show flags a ref off the list" "$(dave project show webcrawler)" \
    "(not in priorities.md)"
  printf '\n1. **RM-4471** — retry\n' >> "$DAVE_HOME/priorities.md"
  case "$(dave project show webcrawler)" in
    *"(not in priorities.md)"*) no "project show clears the flag once listed" "still flagged" ;;
    *) ok "project show clears the flag once listed" ;;
  esac

  local before; before="$(jq -r .last_touched "$DAVE_HOME/projects/webcrawler/project.json")"
  sleep 1
  dave project touch webcrawler >/dev/null
  case "$(jq -r .last_touched "$DAVE_HOME/projects/webcrawler/project.json")" in
    "$before") no "project touch stamps the time" "unchanged" ;;
    *) ok "project touch stamps the time" ;;
  esac
}

test_project_resolve() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler/src/deep/dir"
  dave project add "$root/webcrawler" >/dev/null

  assert_eq "resolve at the project root" "webcrawler" "$(dave project resolve "$root/webcrawler")"
  assert_eq "resolve from a nested path" "webcrawler" \
    "$(dave project resolve "$root/webcrawler/src/deep/dir")"
  assert_eq "resolve outside any project is silent" "" "$(dave project resolve "$root")"
  assert_exit "resolve outside any project still exits 0" 0 dave project resolve /tmp
  assert_eq "resolve on a missing path is silent" "" "$(dave project resolve "$root/gone")"

  # cwd, not just an argument — this is how the hook and brief call it.
  assert_eq "resolve defaults to cwd" "webcrawler" \
    "$(cd "$root/webcrawler/src" && dave project resolve)"
  assert_eq "project show defaults to cwd" "webcrawler" \
    "$(cd "$root/webcrawler/src" && dave project show | sed -n 's/^slug: //p')"
}

# An un-migrated tree must degrade to a note, never to a broken hook.
test_hook_schema_note() {
  dave init >/dev/null
  jq 'del(.schema_version)' "$DAVE_HOME/state.json" > "$DAVE_HOME/s" && mv "$DAVE_HOME/s" "$DAVE_HOME/state.json"
  local ctx
  ctx="$(bash "$TEST_DIR/../../../../hooks/session-start.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')"
  assert_contains "hook notes a stale schema" "$ctx" "run \`dave.sh migrate\`"
  dave migrate >/dev/null
  ctx="$(bash "$TEST_DIR/../../../../hooks/session-start.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')"
  case "$ctx" in
    *"dave.sh migrate"*) no "hook drops the note after migrating" "note still present" ;;
    *) ok "hook drops the note after migrating" ;;
  esac
}

test_project_candidates() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/a" "$root/b"
  dave project add "$root/a" >/dev/null
  json_edit_config() { local t; t="$(mktemp)"; jq "$1" "$DAVE_HOME/config.json" > "$t" && mv "$t" "$DAVE_HOME/config.json"; }
  json_edit_config ".projects.root = \"$root\""
  case "$(dave project list)" in
    *unregistered*) no "candidates stay off unless asked" "listed with autodiscover false" ;;
    *) ok "candidates stay off unless asked" ;;
  esac
  json_edit_config '.projects.autodiscover = true'
  local out; out="$(dave project list)"
  assert_contains "autodiscover names a candidate" "$out" "$root/b"
  case "$out" in
    *"unregistered under"*"/a"*) no "autodiscover skips registered projects" "listed /a" ;;
    *) ok "autodiscover skips registered projects" ;;
  esac
}

# --------------------------------------------------------------- focus stack

test_focus_stack() {
  dave init >/dev/null
  local out; out="$(dave focus push RM-1 "parent")"
  assert_contains "push with nothing focused says so" "$out" "nothing was focused to stack"
  out="$(dave focus push RM-2 "detour")"
  assert_contains "push stacks the parent" "$out" "stacked over RM-1"
  assert_eq "the detour is current" "RM-2" "$(jq -r .focus.ref "$DAVE_HOME/state.json")"
  assert_eq "the parent is stacked" "1" "$(jq -r '.focus_stack | length' "$DAVE_HOME/state.json")"
  assert_contains "show lists the stack" "$(dave focus show)" "RM-1 — parent"

  out="$(dave focus pop)"
  assert_contains "pop returns to the parent" "$out" "RM-1 — parent"
  assert_eq "the stack is empty again" "0" "$(jq -r '.focus_stack | length' "$DAVE_HOME/state.json")"
  # The parent's clock restarts: its earlier time is already banked, and the
  # detour must not be billed to it.
  local started; started="$(jq -r .focus.started "$DAVE_HOME/state.json")"
  assert_eq "pop restarts the parent's clock" "$(date -d "$started" +%F)" "$(date +%F)"

  out="$(dave focus pop)"
  assert_contains "pop with an empty stack clears" "$out" "nothing stacked to return to"
  assert_eq "focus is cleared" "null" "$(jq -r '.focus // "null"' "$DAVE_HOME/state.json")"

  dave focus push RM-9 >/dev/null
  dave focus clear >/dev/null
  assert_eq "clear empties the stack too" "0" "$(jq -r '.focus_stack | length' "$DAVE_HOME/state.json")"
}

test_time_ledger() {
  dave init >/dev/null
  assert_contains "time with nothing recorded" "$(dave time)" "(nothing recorded)"

  # Backdate a focus so a closed segment has real minutes in it.
  dave focus set RM-4471 "retry" >/dev/null
  jq --arg t "$(date -d '-90 min' -Iseconds)" '.focus.started = $t' "$DAVE_HOME/state.json" > "$DAVE_HOME/s" \
    && mv "$DAVE_HOME/s" "$DAVE_HOME/state.json"
  dave log "found the double-fire" >/dev/null
  dave focus set RM-9999 "something else" >/dev/null

  assert_eq "a segment was banked" "1" "$(jsonl_count "$DAVE_HOME/sessions.jsonl")"
  local rec; rec="$(head -1 "$DAVE_HOME/sessions.jsonl")"
  assert_eq "the segment names the ref" "RM-4471" "$(printf '%s' "$rec" | jq -r .ref)"
  assert_eq "the segment has ~90 minutes" "90" "$(printf '%s' "$rec" | jq -r .minutes)"
  assert_eq "the segment counted log activity" "1" "$(printf '%s' "$rec" | jq -r .log_lines)"

  local out; out="$(dave time RM-4471)"
  assert_contains "time reports the total" "$out" "1h30m across 1 segment"
  assert_contains "time reports the open segment" "$(dave time)" "open now:"
  assert_eq "time --json is machine readable" "RM-4471" "$(dave time --json | jq -r '.segments[0].ref')"
  assert_eq "time filters by ref" "0" "$(dave time RM-0 --json | jq '.segments | length')"

  # Time with no log activity behind it is real elapsed time with no evidence,
  # and must be reported separately rather than folded into the total.
  # The log is cleared first: backdating a segment would otherwise pull the
  # earlier test's log line inside this window, which real segments never do.
  rm -f "$DAVE_HOME/log/$(date +%F).md"
  dave focus set RM-5 "unverified work" >/dev/null
  jq --arg t "$(date -d '-40 min' -Iseconds)" '.focus.started = $t' "$DAVE_HOME/state.json" > "$DAVE_HOME/s" \
    && mv "$DAVE_HOME/s" "$DAVE_HOME/state.json"
  dave focus clear >/dev/null
  assert_contains "unverified time is split out" "$(dave time RM-5)" "40m unverified"
}

test_time_open_cap() {
  dave init >/dev/null
  dave focus set RM-1 "held forever" >/dev/null
  jq --arg t "$(date -d '-16 hour' -Iseconds)" '.focus.started = $t' "$DAVE_HOME/state.json" > "$DAVE_HOME/s" \
    && mv "$DAVE_HOME/s" "$DAVE_HOME/state.json"
  local out; out="$(dave time)"
  assert_contains "an overnight focus is capped, not asserted" "$out" "4h0m"
  assert_contains "and the cap is disclosed" "$out" "capped"
  case "$out" in *16h*) no "the raw 16 hours never appears" "found 16h" ;; *) ok "the raw 16 hours never appears" ;; esac
}

test_drift_events() {
  dave init >/dev/null
  dave focus set RM-1 "work" >/dev/null
  assert_contains "drift still reports by default" "$(dave drift)" "on focus"
  dave drift record third-repo parked >/dev/null
  dave drift record third-repo continued >/dev/null
  dave drift record unlisted promoted >/dev/null
  assert_eq "events are recorded" "3" "$(jq -r '.drift_events | length' "$DAVE_HOME/state.json")"
  assert_eq "the focus ref is captured" "RM-1" "$(jq -r '.drift_events[0].ref' "$DAVE_HOME/state.json")"
  local out; out="$(dave drift events)"
  assert_contains "events summarise by kind" "$out" "third-repo: 2"
  assert_contains "events name the outcomes" "$out" "1 parked"
  assert_exit "an invalid kind is refused" 1 dave drift record nonsense parked
  assert_exit "an invalid outcome is refused" 1 dave drift record unlisted maybe
  assert_eq "events --json" "3" "$(dave drift events --json | jq length)"
}

# ------------------------------------------------------------------ tracking

test_next() {
  dave init >/dev/null
  assert_contains "next with nothing recorded" "$(dave next show)" "(no next actions recorded)"
  dave next set RM-4471 "instrument retry middleware ~line 88" >/dev/null
  assert_contains "next show returns it" "$(dave next show)" "instrument retry middleware"
  assert_contains "next show filters by ref" "$(dave next show RM-4471)" "line 88"
  assert_contains "next show on an unknown ref" "$(dave next show RM-0)" "(no next actions recorded)"
  dave next set RM-4471 "revised" >/dev/null
  assert_eq "next set overwrites" "revised" "$(jq -r '."RM-4471".text' "$DAVE_HOME/notes.json")"
  dave next clear RM-4471 >/dev/null
  assert_contains "next clear removes it" "$(dave next show)" "(no next actions recorded)"
}

test_promise() {
  dave init >/dev/null
  assert_contains "promise list when empty" "$(dave promise list)" "(no commitments recorded)"
  local out; out="$(dave promise add "Maya" "SSO demo build" "$(date -d '+2 day' +%F)" --ref RM-4471)"
  assert_contains "promise add returns an id" "$out" "c1: promised Maya"
  dave promise add "Sam" "the exporter" "$(date -d '+30 day' +%F)" >/dev/null
  assert_eq "ids increment" "c2" "$(jq -r '.[1].id' "$DAVE_HOME/commitments.json")"
  assert_exit "an unreadable date is refused" 1 dave promise add "X" "y" "not-a-date"

  # A date a human would actually say.
  dave promise add "Ana" "the review" "friday" >/dev/null
  assert_eq "a spoken date is normalized" "10" \
    "$(jq -r '.[2].due | length' "$DAVE_HOME/commitments.json")"

  assert_contains "list shows all" "$(dave promise list)" "Maya — SSO demo build"
  local soon; soon="$(dave promise list --open --due-within 3)"
  assert_contains "due-within finds the near one" "$soon" "Maya"
  case "$soon" in *Sam*) no "due-within excludes the far one" "Sam listed" ;; *) ok "due-within excludes the far one" ;; esac

  dave promise move c1 "$(date -d '+9 day' +%F)" >/dev/null
  assert_eq "move keeps the history" "1" "$(jq -r '.[0].moved | length' "$DAVE_HOME/commitments.json")"
  assert_eq "move keeps it open" "open" "$(jq -r '.[0].status' "$DAVE_HOME/commitments.json")"
  dave promise keep c1 >/dev/null
  assert_eq "keep closes it" "kept" "$(jq -r '.[0].status' "$DAVE_HOME/commitments.json")"
  dave promise miss c2 >/dev/null
  assert_eq "miss closes it" "missed" "$(jq -r '.[1].status' "$DAVE_HOME/commitments.json")"
  assert_exit "an unknown id is refused" 1 dave promise keep c99

  # Overdue has to be visible without arithmetic on the reader's part.
  dave promise add "Lee" "the thing" "$(date -d '-2 day' +%F)" >/dev/null
  assert_contains "overdue is flagged" "$(dave promise list --open)" "OVERDUE"
}

test_scan() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/repo" "$root/plain"
  git -C "$root/repo" init -q
  git -C "$root/repo" config user.email t@t; git -C "$root/repo" config user.name t
  echo a > "$root/repo/f.txt"; git -C "$root/repo" add -A; git -C "$root/repo" commit -qm "feat: one"
  dave project add "$root/repo" >/dev/null
  dave project add "$root/plain" >/dev/null

  local out; out="$(dave scan)"
  assert_contains "scan reports the branch" "$out" "repo"
  assert_contains "scan reports a clean tree" "$out" "clean"
  assert_contains "scan tolerates a non-repo" "$out" "(not a repo)"
  assert_contains "scan dates the last commit" "$out" "committed today"
  [ -f "$DAVE_HOME/scan-cache.json" ] && ok "scan writes a cache" || no "scan writes a cache" "missing"

  echo b >> "$root/repo/f.txt"
  case "$(dave scan)" in
    *clean*) ok "a cached scan is served from cache" ;;
    *) no "a cached scan is served from cache" "re-probed within the TTL" ;;
  esac
  assert_contains "--fresh bypasses the cache" "$(dave scan --fresh)" "1 dirty"
  assert_eq "scan filters to one project" "1" "$(dave scan repo --json | jq 'keys | length')"

  # A registered path that vanishes must not take the scan down with it.
  rm -rf "$root/plain"
  assert_contains "a missing path is reported" "$(dave scan --fresh)" "PATH GONE"

  dave project status repo archived >/dev/null
  assert_eq "archived projects are skipped" "0" "$(dave scan --fresh --json | jq 'keys | map(select(. == "repo")) | length')"
  assert_eq "--all includes them" "1" "$(dave scan --fresh --all --json | jq 'keys | map(select(. == "repo")) | length')"
}

test_brief_phase_b() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler"
  dave project add "$root/webcrawler" >/dev/null
  dave project link webcrawler RM-4471 >/dev/null
  dave focus set RM-4471 "retry" >/dev/null
  dave next set RM-4471 "instrument the middleware" >/dev/null
  dave promise add "Maya" "SSO demo" "$(date -d '+1 day' +%F)" --ref RM-4471 >/dev/null

  local out; out="$(cd "$root/webcrawler" && dave brief)"
  assert_contains "brief shows where you left off" "$out" "next: instrument the middleware"
  assert_contains "brief surfaces a promise coming due" "$out" "PROMISED, DUE SOON"
  assert_contains "brief names who it was made to" "$out" "Maya"
  # The focused ref's note is on the focus line already; printing it twice is noise.
  assert_eq "the focused ref is not repeated below" "0" \
    "$(printf '%s' "$out" | grep -c '^RM-4471: instrument' || true)"
  dave next set RM-77 "a different ref" >/dev/null
  dave project link webcrawler RM-77 >/dev/null
  assert_contains "other refs still appear" "$(cd "$root/webcrawler" && dave brief)" "RM-77: a different ref"

  # Both sections vanish when empty rather than printing "(none)".
  dave next clear RM-4471 >/dev/null
  dave next clear RM-77 >/dev/null
  dave promise keep c1 >/dev/null
  out="$(cd "$root/webcrawler" && dave brief)"
  case "$out" in *"PROMISED, DUE SOON"*) no "the promise section vanishes when empty" "still shown" ;; *) ok "the promise section vanishes when empty" ;; esac
  case "$out" in *"WHERE YOU LEFT OFF"*) no "the notes section vanishes when empty" "still shown" ;; *) ok "the notes section vanishes when empty" ;; esac
}

# ------------------------------------------------------------------ missions

test_mission_ledger() {
  dave init >/dev/null
  dave mission new "SSO rollout" --ref RM-4471 >/dev/null
  assert_eq "mission new registers metadata" "RM-4471" \
    "$(jq -r '."sso-rollout".ref' "$DAVE_HOME/missions.json")"
  assert_eq "a new mission is open" "open" \
    "$(jq -r '."sso-rollout".status' "$DAVE_HOME/missions.json")"

  local id; id="$(dave mission assign sso-rollout scout "find out why the retry double-fires")"
  assert_eq "assign returns a readable id" "sso-rollout#1" "$id"
  local id2; id2="$(dave mission assign sso-rollout ideator "three approaches" --model opus)"
  assert_eq "ids increment per mission" "sso-rollout#2" "$id2"

  assert_contains "status lists what is outstanding" "$(dave mission status)" "sso-rollout#1"
  assert_contains "status names the agent" "$(dave mission status sso-rollout)" "scout"

  dave mission record "$id" --verdict partial --summary "cache claim unverified" >/dev/null
  local st; st="$(dave mission status sso-rollout)"
  case "$st" in *"sso-rollout#1"*) no "a recorded charge leaves the outstanding list" "still listed" ;;
                *) ok "a recorded charge leaves the outstanding list" ;; esac
  assert_contains "the other charge is still open" "$st" "sso-rollout#2"

  # The table is rendered from the ledger, not maintained by hand.
  local show; show="$(dave mission show sso-rollout)"
  assert_contains "show renders a table header" "$show" "| Id | Agent | Charge | Returned | Verdict |"
  assert_contains "show renders the verdict" "$show" "partial — cache claim unverified"
  assert_contains "show marks an open charge" "$show" "**open**"
  assert_contains "show notes the model when given" "$show" "ideator (opus)"
  assert_eq "the template table is not duplicated" "1" \
    "$(printf '%s' "$show" | grep -c '^## Assignments')"

  assert_exit "an orphan verdict is refused" 1 dave mission record "sso-rollout#99" --verdict trust
  assert_exit "an invalid verdict is refused" 1 dave mission record "$id2" --verdict lovely
  assert_exit "a verdict is required" 1 dave mission record "$id2"

  # The active mission is the default target, so a long session stops repeating itself.
  dave mission open sso-rollout >/dev/null
  assert_eq "open sets the active mission" "sso-rollout" "$(jq -r .active_mission "$DAVE_HOME/state.json")"
  local id3; id3="$(dave mission assign critic "attack the plan")"
  assert_eq "assign defaults to the active mission" "sso-rollout#3" "$id3"

  local out; out="$(dave mission close sso-rollout --outcome "shipped")"
  assert_contains "close flags unrecorded charges" "$out" "closed without a recorded verdict"
  assert_eq "close clears the active mission" "null" "$(jq -r '.active_mission // "null"' "$DAVE_HOME/state.json")"
  assert_eq "close records the outcome" "shipped" "$(jq -r '."sso-rollout".outcome' "$DAVE_HOME/missions.json")"
  assert_eq "list --open excludes it" "0" "$(dave mission list --open --json | jq length)"
}

test_mission_legacy() {
  dave init >/dev/null
  # A brief written before missions.json existed must not read as broken.
  sed -e 's|{{SLUG}}|old-thing|g' -e "s|{{DATE}}|$(today)|g" \
    "$TEST_DIR/../../templates/mission-brief-template.md" > "$DAVE_HOME/missions/old-thing.md"
  assert_contains "list finds an unregistered brief" "$(dave mission list)" "old-thing"
  local id; id="$(dave mission assign old-thing scout "have a look")"
  assert_eq "assigning backfills its metadata" "sso" "$(jq -r 'if ."old-thing" then "sso" else "missing" end' "$DAVE_HOME/missions.json")"
  assert_eq "and the id is well formed" "old-thing#1" "$id"
}

test_mission_pack() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler"
  dave project add "$root/webcrawler" >/dev/null
  dave mission new "retry bug" --ref RM-4471 --project webcrawler >/dev/null
  local path="$DAVE_HOME/missions/retry-bug.md"

  # An unfilled brief must say so rather than emitting a confident empty charge.
  local pack; pack="$(dave mission pack retry-bug --agent scout)"
  assert_contains "pack flags an empty brief" "$pack" "Incomplete brief"
  assert_contains "pack names the empty sections" "$pack" "objective"

  cat > "$path" <<'BRIEF'
# Mission: retry-bug

## Priority ref

RM-4471

## Objective

The retry middleware fires once per request.

## Definition of done

- [x] a failing test reproduces the double-fire

## Constraints

Do not touch the billing path.

## Context the agent won't have

The retry wrapper lives in src/mw/retry.py and was rewritten in June.

## Assignments

| Agent | Charge | Returned | Verdict |
|---|---|---|---|

## Open questions

## Outcome
BRIEF

  pack="$(dave mission pack retry-bug --agent scout)"
  case "$pack" in *"Incomplete brief"*) no "a filled brief packs cleanly" "still flagged" ;;
                  *) ok "a filled brief packs cleanly" ;; esac
  assert_contains "pack carries the objective" "$pack" "fires once per request"
  assert_contains "pack carries the done conditions" "$pack" "failing test reproduces"
  assert_contains "pack carries undiscoverable context" "$pack" "src/mw/retry.py"
  assert_contains "pack names the ref it serves" "$pack" "Serves: RM-4471"
  assert_contains "pack ends with the agent's return format" "$pack" "## Return format"
  assert_contains "pack quotes the real return contract" "$pack" "## Answer"
  case "$pack" in *"<!--"*) no "pack strips the template's prompts" "HTML comment leaked" ;;
                  *) ok "pack strips the template's prompts" ;; esac

  # A charge with no return contract is not a charge.
  assert_exit "pack refuses an unknown agent" 1 dave mission pack retry-bug --agent nosuch
  assert_exit "pack requires an agent" 1 dave mission pack retry-bug

  # Prior charges travel with the brief so a rerun knows what went wrong.
  local id; id="$(dave mission assign retry-bug scout "first look")"
  dave mission record "$id" --verdict rerun --summary "answered an easier question" >/dev/null
  pack="$(dave mission pack retry-bug --agent scout)"
  assert_contains "pack lists prior charges" "$pack" "Already asked on this mission"
  assert_contains "pack carries the prior verdict" "$pack" "rerun (answered an easier question)"

  # And the project's dossier is offered rather than re-derived.
  echo "# webcrawler map" | dave dossier set webcrawler >/dev/null
  pack="$(dave mission pack retry-bug --agent scout)"
  assert_contains "pack points at the cached dossier" "$pack" "dossier.md"

  # An untouched brief: every section empty, and the template's own unticked
  # checkbox must read as a skeleton rather than as a filled definition of done.
  dave mission new "skeleton" >/dev/null
  local bare; bare="$(dave mission pack skeleton --agent scout)"
  assert_contains "an empty section says so" "$bare" "_(none stated)_"
  assert_contains "a skeleton done-list still counts as empty" "$bare" "definition-of-done"
}

test_dossier() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/repo"
  git -C "$root/repo" init -q
  git -C "$root/repo" config user.email t@t; git -C "$root/repo" config user.name t
  echo a > "$root/repo/f"; git -C "$root/repo" add -A; git -C "$root/repo" commit -qm one
  dave project add "$root/repo" >/dev/null

  assert_contains "no dossier yet" "$(dave dossier get repo)" "(no dossier for repo"
  printf '# Map

It is a crawler.
' | dave dossier set repo >/dev/null
  assert_contains "dossier get returns it" "$(dave dossier get repo)" "It is a crawler."
  assert_contains "a fresh dossier is current" "$(dave dossier get repo)" "has not moved since"
  assert_eq "the dossier is stamped with a commit" "40" \
    "$(jq -r '.dossier.head | length' "$DAVE_HOME/projects/repo/project.json")"

  echo b > "$root/repo/f2"; git -C "$root/repo" add -A; git -C "$root/repo" commit -qm two
  assert_contains "one commit on is still current" "$(dave dossier get repo)" "1 commit(s) since"

  # Past the threshold it must say so plainly rather than being quietly trusted.
  jq '.projects.dossier_stale_commits = 1' "$DAVE_HOME/config.json" > "$DAVE_HOME/c" \
    && mv "$DAVE_HOME/c" "$DAVE_HOME/config.json"
  assert_contains "past the threshold it is stale" "$(dave dossier get repo)" "STALE"

  # A rewritten history must not produce a confident wrong answer.
  jq '.dossier.head = "0000000000000000000000000000000000000000"' \
    "$DAVE_HOME/projects/repo/project.json" > "$DAVE_HOME/p" \
    && mv "$DAVE_HOME/p" "$DAVE_HOME/projects/repo/project.json"
  assert_contains "an unknown commit is admitted" "$(dave dossier get repo)" "no longer in this repository"
}

# -------------------------------------------------------------------- review

# Builds a repo whose only commit is dated <age> days ago.
mkrepo() {
  local d="$1" when="$2"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo x > "$d/f"; git -C "$d" add -A
  GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" git -C "$d" commit -qm "feat: seed"
}

test_review_empty() {
  dave init >/dev/null
  local out; out="$(dave review)"
  assert_exit "review on a fresh tree exits 0" 0 dave review
  case "$out" in
    *Slipping*|*Rotting*|*Owed*) no "a fresh tree produces no alarms" "found a findings section" ;;
    *) ok "a fresh tree produces no alarms" ;;
  esac
  assert_contains "review always states the closure gap" "$out" "not recorded anywhere"
  assert_contains "review names the window" "$out" "Since "
  assert_eq "review --json is consumable" "7" "$(dave review --json | jq -r '.window.days')"
}

test_review_cadence() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"
  mkrepo "$root/daily-one"  "$(date -d '-1 day' -Iseconds)"
  mkrepo "$root/weekly-one" "$(date -d '-24 day' -Iseconds)"
  mkrepo "$root/maint-one"  "$(date -d '-60 day' -Iseconds)"
  mkrepo "$root/dormant-one" "$(date -d '-400 day' -Iseconds)"
  dave project add "$root/daily-one"   --cadence daily >/dev/null
  dave project add "$root/weekly-one"  --cadence weekly >/dev/null
  dave project add "$root/maint-one"   --cadence monthly >/dev/null
  dave project status maint-one maintenance >/dev/null
  dave project add "$root/dormant-one" --cadence dormant >/dev/null

  local j; j="$(dave review --json)"
  assert_eq "an active weekly project 24d quiet is slipping" "true" \
    "$(printf '%s' "$j" | jq -r '.projects[] | select(.slug == "weekly-one") | .slipping')"
  assert_eq "a daily project committed yesterday is fine" "false" \
    "$(printf '%s' "$j" | jq -r '.projects[] | select(.slug == "daily-one") | .slipping')"
  # The two that keep the sweep honest.
  assert_eq "a maintenance project quiet for 60d is not a finding" "false" \
    "$(printf '%s' "$j" | jq -r '.projects[] | select(.slug == "maint-one") | .slipping')"
  assert_eq "a dormant project never slips" "false" \
    "$(printf '%s' "$j" | jq -r '.projects[] | select(.slug == "dormant-one") | .slipping')"

  local out; out="$(dave review)"
  assert_contains "slipping is reported with its number" "$out" "weekly-one — weekly cadence, nothing for 2"
  assert_contains "quiet and fine is a real section" "$out" "Quiet and fine:"
  assert_contains "the maintenance project is listed as fine" "$out" "maint-one (maintenance)"

  # Registration is not activity: a project registered today whose repo has been
  # silent for a month must still read as silent.
  assert_eq "registering does not reset the clock" "null" \
    "$(jq -r '.last_touched // "null"' "$DAVE_HOME/projects/weekly-one/project.json")"
}

test_review_findings() {
  dave init >/dev/null
  # An overdue promise outranks everything: it is the one thing here the user
  # cannot see for themselves.
  dave promise add "Maya" "SSO demo" "$(date -d '-2 day' +%F)" >/dev/null
  dave promise add "Sam" "exporter" "$(date -d '+2 day' +%F)" >/dev/null
  local out; out="$(dave review)"
  assert_contains "an overdue promise is slipping" "$out" "Maya — SSO demo"
  assert_contains "and it is marked overdue" "$out" "OVERDUE"
  assert_contains "a future promise is only coming due" "$out" "Coming due:"
  case "$(printf '%s' "$out" | sed -n '/Slipping:/,/^$/p')" in
    *Sam*) no "a future promise is not slipping" "listed under Slipping" ;;
    *) ok "a future promise is not slipping" ;;
  esac

  # Parked items rot.
  printf -- '- [ ] rewrite the exporter _(parked %s 14:00, while on RM-1)_\n' \
    "$(date -d '-30 day' +%F)" >> "$DAVE_HOME/parking-lot.md"
  printf -- '- [ ] something recent _(parked %s 09:00)_\n' "$(date +%F)" >> "$DAVE_HOME/parking-lot.md"
  assert_eq "only the old parked item counts" "1" "$(dave review --json | jq '.parked | length')"
  assert_contains "rotting names the oldest" "$(dave review)" "rewrite the exporter"

  # An AD- item that outlived its grace period should have become a ticket.
  printf '\n1. **AD-cache-warmup** — warm it\n' >> "$DAVE_HOME/priorities.md"
  printf -- '- `09:00` **AD-cache-warmup** — started\n' > "$DAVE_HOME/log/$(date -d '-11 day' +%F).md"
  assert_contains "an aged ad-hoc item is flagged" "$(dave review)" "AD-cache-warmup first logged 11d ago"

  # Blocked items stay prose and get handed over, not judged.
  printf '\n## Blocked\n\n- **RM-88** — waiting on Ana for the schema\n' >> "$DAVE_HOME/priorities.md"
  out="$(dave review)"
  assert_contains "blocked items are handed to the reader" "$out" "which of these has nobody chased?"
  assert_contains "and quoted verbatim" "$out" "waiting on Ana"
}

test_review_owed() {
  dave init >/dev/null
  dave mission new "sso rollout" >/dev/null
  dave mission assign sso-rollout scout "have a look" >/dev/null
  # A charge sent moments ago is not a finding.
  case "$(dave review)" in
    *Owed*) no "a fresh charge is not owed" "listed under Owed" ;;
    *) ok "a fresh charge is not owed" ;;
  esac
  # One sent last week and never graded is exactly the thing to surface.
  local old_ts; old_ts="$(date -d '-5 day' -Iseconds)"
  jq -c --arg ts "$old_ts" '.ts = $ts' "$DAVE_HOME/assignments.jsonl" > "$DAVE_HOME/a.tmp" \
    && mv "$DAVE_HOME/a.tmp" "$DAVE_HOME/assignments.jsonl"
  local out; out="$(dave review)"
  assert_contains "an aged open charge is owed" "$out" "sso-rollout — 1 charge(s) outstanding"
  assert_contains "and it says how old" "$out" "oldest sent 5d ago"

  # Grading it closes the loop.
  dave mission record "sso-rollout#1" --verdict trust >/dev/null
  case "$(dave review)" in
    *"charge(s) outstanding"*) no "a graded charge stops being owed" "still listed" ;;
    *) ok "a graded charge stops being owed" ;;
  esac
}

test_review_drift() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler"
  dave project add "$root/webcrawler" >/dev/null
  dave drift record third-repo continued --project webcrawler >/dev/null
  dave drift record third-repo parked --project webcrawler >/dev/null
  dave drift record unlisted promoted --project webcrawler >/dev/null
  local out; out="$(dave review)"
  assert_contains "drift is summarised by kind" "$out" "third-repo ×2"
  assert_contains "and points at where it went" "$out" "into webcrawler"
  # Old events fall outside the window rather than accumulating forever. Aged
  # explicitly rather than by asking for a zero-day window: the boundary is
  # inclusive and timestamps are second-resolution, so a zero-day window is a
  # race with the clock rather than a test.
  dave drift record no-focus parked >/dev/null
  jq --arg old "$(date -d '-30 day' -Iseconds)" \
     '.drift_events[3].at = $old' "$DAVE_HOME/state.json" > "$DAVE_HOME/s.tmp" \
    && mv "$DAVE_HOME/s.tmp" "$DAVE_HOME/state.json"
  assert_eq "the window excludes an old event" "3" "$(dave review --json | jq '.drift | length')"
  assert_eq "a wider window includes it" "4" "$(dave review --days 60 --json | jq '.drift | length')"
}

# ------------------------------------------------------------------- helpers

test_helpers() {
  dave init >/dev/null
  # shellcheck disable=SC1090
  . "$TEST_DIR/../lib/common.sh"

  local f="$DAVE_HOME/t.jsonl"
  printf '{"a":1}\n{"a":2}\n' > "$f"
  assert_eq "jsonl_stream reads clean records" "2" "$(jsonl_stream "$f" | wc -l)"
  printf '{"a":3' >> "$f"   # an append interrupted mid-write
  assert_eq "jsonl_stream survives a truncated tail" "2" "$(jsonl_stream "$f" | wc -l)"
  assert_eq "jsonl_fold folds to an array" "3" "$(jsonl_fold "$f" 'map(.a) | add')"
  assert_eq "jsonl_fold on a missing file" "null" "$(jsonl_fold "$DAVE_HOME/nope.jsonl" 'map(.a) | add')"

  jsonl_append "$f" '{"a":4}'
  assert_eq "jsonl_append adds a record" "3" "$(jsonl_stream "$f" | wc -l)"
  # The appended record must survive landing after a truncated one.
  assert_eq "jsonl_append survives a truncated tail" "4" "$(jsonl_fold "$f" 'map(.a) | max')"
  jsonl_append "$DAVE_HOME/fresh.jsonl" '{"a":9}'
  assert_eq "jsonl_append creates the file" "9" "$(jsonl_fold "$DAVE_HOME/fresh.jsonl" 'map(.a) | add')"

  assert_eq "json_get returns a value" "dry" "$(json_get "$CONFIG" '.personality.wit')"
  assert_eq "json_get falls back" "fallback" "$(json_get "$CONFIG" '.nothing.here' 'fallback')"
  assert_eq "json_get on a missing file" "d" "$(json_get "$DAVE_HOME/nope.json" '.x' 'd')"

  # The bug the session-start hook documents: `.x // true` cannot return false.
  json_edit "$CONFIG" '.hooks.session_start = false'
  assert_eq "config_bool respects an explicit false" "false" "$(config_bool '.hooks.session_start' true)"
  json_edit "$CONFIG" 'del(.hooks.session_start)'
  assert_eq "config_bool defaults when absent" "true" "$(config_bool '.hooks.session_start' true)"
}

test_git_probe() {
  dave init >/dev/null
  # shellcheck disable=SC1090
  . "$TEST_DIR/../lib/common.sh"

  assert_eq "git_probe on a missing path" "false" "$(git_probe "$DAVE_HOME/nope" | jq -r .exists)"
  mkdir -p "$DAVE_HOME/plain"
  assert_eq "git_probe on a non-repo" "false" "$(git_probe "$DAVE_HOME/plain" | jq -r .repo)"

  local repo="$DAVE_HOME/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hello > "$repo/f.txt"
  git -C "$repo" add f.txt && git -C "$repo" commit -qm "feat: first"
  local probe; probe="$(git_probe "$repo")"
  assert_eq "git_probe finds a repo"        "true"       "$(printf '%s' "$probe" | jq -r .repo)"
  assert_eq "git_probe reads the subject"   "feat: first" "$(printf '%s' "$probe" | jq -r .last_subject)"
  assert_eq "git_probe on a clean tree"     "0"          "$(printf '%s' "$probe" | jq -r .dirty)"
  echo dirty >> "$repo/f.txt"; echo new > "$repo/untracked.txt"
  probe="$(git_probe "$repo")"
  assert_eq "git_probe counts dirty files"  "1" "$(printf '%s' "$probe" | jq -r .dirty)"
  assert_eq "git_probe counts untracked"    "1" "$(printf '%s' "$probe" | jq -r .untracked)"
  assert_eq "git_probe with no upstream"    "0" "$(printf '%s' "$probe" | jq -r .ahead)"
}

test_help() {
  local out; out="$(dave help)"
  for c in init migrate brief focus drift park log standup mission intake project \
           scan time next promise dossier review; do
    assert_contains "help lists $c" "$out" "  $c"
  done
  assert_exit "an unknown command fails" 1 dave frobnicate
}

# ----------------------------------------------------------------------- run

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

for t in init init_idempotent not_set_up_exits_3 migrate focus drift journal \
         intake mission project project_resolve project_candidates \
         hook_schema_note brief focus_stack time_ledger time_open_cap \
         drift_events next promise scan brief_phase_b \
         mission_ledger mission_legacy mission_pack dossier \
         review_empty review_cadence review_findings review_owed review_drift \
         helpers git_probe help; do
  run_test "$t"
done

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed tests:\n'; printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
