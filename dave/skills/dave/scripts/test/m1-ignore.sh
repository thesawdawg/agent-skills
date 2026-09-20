#!/usr/bin/env bash
# Focused M1 coverage for local Syncthing ignore preparation.

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$TEST_DIR/../lib"

# The helper is intentionally tested in isolation so these cases never need a
# daemon, network access, a package manager, or the user's personal vault.
. "$LIB_DIR/common.sh"
. "$LIB_DIR/sync.sh"

PASS=0
FAIL=0
TEST_HOME=""

cleanup() {
  [ -z "$TEST_HOME" ] || rm -rf "$TEST_HOME"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAIL=$((FAIL + 1))
}

ok() {
  printf 'ok: %s\n' "$*"
  PASS=$((PASS + 1))
}

new_home() {
  cleanup
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/dave-m1-ignore.XXXXXX")"
  DAVE_HOME="$TEST_HOME"
  LOCAL="$DAVE_HOME/.local"
  mkdir -p "$LOCAL"
  export DAVE_HOME
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$name"; else fail "$name: expected [$expected], got [$actual]"; fi
}

assert_contains() {
  local name="$1" text="$2" needle="$3"
  case "$text" in *"$needle"*) ok "$name" ;; *) fail "$name: missing [$needle]" ;; esac
}

assert_status() {
  local name="$1" expected="$2"
  shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  assert_eq "$name" "$expected" "$actual"
}

test_fresh_and_custom_rules() {
  new_home
  _sync_prepare_ignores
  local text
  text="$(cat "$DAVE_HOME/.stignore")"
  assert_contains "fresh file has a managed block" "$text" "$_SYNC_IGNORE_BEGIN"
  assert_contains "fresh file protects local state" "$text" '/.local'
  assert_contains "fresh file protects migration archives" "$text" '/.migrated-*'
  assert_eq "fresh file starts with the managed block" \
    "$_SYNC_IGNORE_BEGIN" "$(head -n 1 "$DAVE_HOME/.stignore")"

  printf '!/.local\nprivate/\n// user comment\n' > "$DAVE_HOME/.stignore"
  chmod 640 "$DAVE_HOME/.stignore"
  _sync_prepare_ignores
  text="$(cat "$DAVE_HOME/.stignore")"
  assert_contains "custom negation survives" "$text" '!/.local'
  assert_contains "custom pattern survives" "$text" 'private/'
  assert_contains "custom comment survives" "$text" '// user comment'
  assert_eq "required rule precedes custom negation" \
    "1" "$(awk '$0 == "/.local" {required=NR} $0 == "!/.local" {custom=NR} END {print required < custom}' "$DAVE_HOME/.stignore")"
  assert_eq "existing mode survives replacement" "640" \
    "$(stat -c '%a' "$DAVE_HOME/.stignore")"
}

test_escape_header_and_idempotence() {
  new_home
  printf '#escape=\\\\\nprivate/\n' > "$DAVE_HOME/.stignore"
  _sync_prepare_ignores
  assert_eq "escape directive remains first" '#escape=\\' \
    "$(head -n 1 "$DAVE_HOME/.stignore")"
  local first second
  first="$(sha256sum "$DAVE_HOME/.stignore")"
  _sync_prepare_ignores
  second="$(sha256sum "$DAVE_HOME/.stignore")"
  assert_eq "repeated preparation is byte stable" "$first" "$second"
}

test_malformed_is_atomic() {
  new_home
  printf '// BEGIN DAVE MANAGED IGNORE RULES\n/.local\ncustom/\n' \
    > "$DAVE_HOME/.stignore"
  local before after
  before="$(sha256sum "$DAVE_HOME/.stignore")"
  assert_status "malformed markers are rejected" 1 _sync_prepare_ignores
  after="$(sha256sum "$DAVE_HOME/.stignore")"
  assert_eq "malformed preparation leaves the original intact" "$before" "$after"
}

test_callers_use_shared_helper() {
  assert_status "migration references shared preparation" 0 \
    grep -q '_sync_prepare_ignores' "$LIB_DIR/migrate.sh"
  assert_status "initialization references shared preparation" 0 \
    grep -q '_sync_prepare_ignores' "$LIB_DIR/state.sh"
  assert_status "setup references shared preparation" 0 \
    grep -q '_sync_prepare_ignores' "$LIB_DIR/sync.sh"
}

test_fresh_and_custom_rules
test_escape_header_and_idempotence
test_malformed_is_atomic
test_callers_use_shared_helper

printf '\npassed: %d   failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
  DAVE_HOME="$TEST_HOME"
  export DAVE_HOME
  DAVE_HOME="$TEST_HOME"
  LOCAL="$DAVE_HOME/.local"
  mkdir -p "$LOCAL"
  export DAVE_HOME
