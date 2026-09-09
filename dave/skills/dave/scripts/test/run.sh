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
  for c in init migrate brief focus drift park log standup mission intake project; do
    assert_contains "help lists $c" "$out" "  $c"
  done
  assert_exit "an unknown command fails" 1 dave frobnicate
}

# ----------------------------------------------------------------------- run

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

for t in init init_idempotent not_set_up_exits_3 migrate focus drift journal \
         intake mission project project_resolve project_candidates \
         hook_schema_note brief \
         helpers git_probe help; do
  run_test "$t"
done

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed tests:\n'; printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
