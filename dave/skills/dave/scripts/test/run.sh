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
  for section in "=== IDENTITY ===" "=== FOCUS ===" "=== PRIORITIES ===" "=== TODAY" "=== PARKED (open) ===" "=== LAST INTAKE ==="; do
    assert_contains "brief has $section" "$out" "$section"
  done
  assert_contains "brief reports elapsed time" "$out" "elapsed:"
  assert_contains "brief stamps last_brief" "$(jq -r .last_brief "$DAVE_HOME/state.json")" "-"
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
  for c in init migrate brief focus drift park log standup mission intake; do
    assert_contains "help lists $c" "$out" "  $c"
  done
  assert_exit "an unknown command fails" 1 dave frobnicate
}

# ----------------------------------------------------------------------- run

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

for t in init init_idempotent not_set_up_exits_3 migrate focus drift journal \
         intake mission brief helpers git_probe help; do
  run_test "$t"
done

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed tests:\n'; printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
