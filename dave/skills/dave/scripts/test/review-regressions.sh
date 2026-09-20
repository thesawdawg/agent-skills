#!/usr/bin/env bash
# shellcheck disable=SC2016
# review-regressions.sh — deterministic fixtures for the 2026 sync review.
#
# These are deliberately separate from run.sh.  The reviewed behavior is the
# assertion; failures in the current implementation are reported as XFAIL by
# default so the fixture can live in the tree before all remediation work is
# complete.  Pass --strict to make any remaining XFAIL fail the process.

set -Euo pipefail
# jq programs below intentionally use single quotes so the shell passes them
# unchanged to jq.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAVE="$(cd "$TEST_DIR/.." && pwd)/dave.sh"
REPO_ROOT="$(cd "$TEST_DIR/../../../../.." && pwd)"
DASHBOARD_DIR="$REPO_ROOT/dave/skills/dave/dashboard"

PASS=0
FAIL=0
XFAIL=0
XPASS=0
STRICT=0
CASE_ROOT=""

# The five reviewed defects are expected until their corresponding remediation
# lands. A maintainer can narrow this list as fixes arrive without changing an
# assertion or making a test conditional on the implementation.
EXPECTED_FAILURES="${DAVE_REVIEW_EXPECTED_FAILURES:-dashboard-refresh}"

contains_csv() {
  local needle="$1" item
  IFS=',' read -r -a items <<< "$EXPECTED_FAILURES"
  for item in "${items[@]}"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

selected() {
  local name="$1" selector
  [ "${#SELECTORS[@]}" -eq 0 ] && return 0
  for selector in "${SELECTORS[@]}"; do
    [ "$selector" = "$name" ] && return 0
    case "$name" in
      *"$selector"*) return 0 ;;
    esac
  done
  return 1
}

fail_test() {
  printf '%s\n' "${1:-assertion failed}" >&2
  return 1
}

assert_eq() {
  local label="$1" want="$2" got="$3"
  [ "$want" = "$got" ] || fail_test "$label: expected [$want], got [$got]"
}

assert_file_contains() {
  local label="$1" file="$2" text="$3"
  grep -Fqx -- "$text" "$file" || fail_test "$label: missing [$text] in $file"
}

new_case() {
  CASE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dave-review-regression.XXXXXX")"
  mkdir -p "$CASE_ROOT/home-config"
  export HOME="$CASE_ROOT/home-config"
  export XDG_CONFIG_HOME="$CASE_ROOT/home-config/.config"
  export XDG_STATE_HOME="$CASE_ROOT/home-config/.state"
  export SYNCTHING_BIN="$CASE_ROOT/no-syncthing"
  export SYNCTHING_CONFIG="$CASE_ROOT/no-syncthing-config.xml"
  export SYNCTHING_API_KEY=""
  export DAVE_REVIEW_NO_NETWORK=1
}

finish_case() {
  [ -n "$CASE_ROOT" ] || return 0
  rm -rf -- "$CASE_ROOT"
  CASE_ROOT=""
}

dave_at() {
  local home="$1"
  shift
  DAVE_HOME="$home" HOME="$CASE_ROOT/home-config" \
    XDG_CONFIG_HOME="$CASE_ROOT/home-config/.config" \
    XDG_STATE_HOME="$CASE_ROOT/home-config/.state" \
    SYNCTHING_BIN="$CASE_ROOT/no-syncthing" \
    SYNCTHING_CONFIG="$CASE_ROOT/no-syncthing-config.xml" \
    SYNCTHING_API_KEY="" \
    bash "$DAVE" "$@"
}

init_home() {
  dave_at "$1" init >/dev/null
}

write_event() {
  local file="$1"
  shift
  jq -nc "$@" >> "$file"
}

test_offline_identity() {
  local a="$CASE_ROOT/a" b="$CASE_ROOT/b" a_journal b_journal
  init_home "$a"
  init_home "$b"

  # Keep both the envelope identities and timestamps stable. B's keep event was
  # authored while it still had its own c1, before A's journal was exchanged.
  jq -n '{id:"device-a",hostname:"review-a",created:"2026-09-19T09:00:00+00:00"}' \
    > "$a/.local/device.json"
  jq -n '{id:"device-b",hostname:"review-b",created:"2026-09-19T09:00:00+00:00"}' \
    > "$b/.local/device.json"
  a_journal="$a/journal/device-a.jsonl"
  b_journal="$b/journal/device-b.jsonl"
  write_event "$a_journal" --arg ts "2026-09-19T10:00:00+00:00" \
    '{ts:$ts,seq:1,dev:"device-a",sid:"a",type:"promise.add",data:{id:"c1",entity_id:"entity-ann",who:"Ann",what:"task from Ann",due:"2030-01-01",ref:"",project:"",status:"open",created:$ts,closed:null,moved:[]}}'
  write_event "$b_journal" --arg ts "2026-09-19T10:01:00+00:00" \
    '{ts:$ts,seq:1,dev:"device-b",sid:"b",type:"promise.add",data:{id:"c1",entity_id:"entity-bob",who:"Bob",what:"task from Bob",due:"2030-01-01",ref:"",project:"",status:"open",created:$ts,closed:null,moved:[]}}'
  write_event "$b_journal" --arg ts "2026-09-19T10:02:00+00:00" \
    '{ts:$ts,seq:2,dev:"device-b",sid:"b",type:"promise.keep",data:{id:"c1",entity_id:"entity-bob",status:"kept",ts:$ts}}'
  cp "$a_journal" "$b/journal/device-a.jsonl"
  cp "$b_journal" "$a/journal/device-b.jsonl"

  dave_at "$a" state >/dev/null
  dave_at "$b" state >/dev/null
  local ann_a bob_a ann_b bob_b bob_id_a bob_id_b
  ann_a="$(jq -r '.[] | select(.who == "Ann") | .status' "$a/.local/views/commitments.json")"
  bob_a="$(jq -r '.[] | select(.who == "Bob") | .status' "$a/.local/views/commitments.json")"
  ann_b="$(jq -r '.[] | select(.who == "Ann") | .status' "$b/.local/views/commitments.json")"
  bob_b="$(jq -r '.[] | select(.who == "Bob") | .status' "$b/.local/views/commitments.json")"
  bob_id_a="$(jq -r '.[] | select(.who == "Bob") | .entity_id' "$a/.local/views/commitments.json")"
  bob_id_b="$(jq -r '.[] | select(.who == "Bob") | .entity_id' "$b/.local/views/commitments.json")"
  assert_eq "device A leaves Ann's promise open" open "$ann_a"
  assert_eq "device A keeps Bob's selected promise" kept "$bob_a"
  assert_eq "device B leaves Ann's promise open" open "$ann_b"
  assert_eq "device B keeps Bob's selected promise" kept "$bob_b"
  assert_eq "device A retains Bob's immutable identity" entity-bob "$bob_id_a"
  assert_eq "device B retains Bob's immutable identity" entity-bob "$bob_id_b"
  cmp -s <(jq -S . "$a/.local/views/commitments.json") \
    <(jq -S . "$b/.local/views/commitments.json") \
    || fail_test "exchanged devices do not converge on the same commitments"
}

test_rebuild_arrival() {
  local home="$CASE_ROOT/rebuild"
  init_home "$home"
  dave_at "$home" next set BASE "before rebuild" >/dev/null

  # _journal_events emits the existing input, then a deterministic barrier
  # writes one arriving journal. A correct builder retries from a stable input;
  # it cannot stamp the late journal's fingerprint onto the old reduction.
  if ! DAVE_HOME="$home" REVIEW_LIB_DIR="$REPO_ROOT/dave/skills/dave/scripts/lib" \
    bash -s <<'BASH'
set -Eeuo pipefail
source "$REVIEW_LIB_DIR/common.sh"
source "$REVIEW_LIB_DIR/journal-core.sh"
source "$REVIEW_LIB_DIR/integrity.sh"
source "$REVIEW_LIB_DIR/views.sh"
source "$REVIEW_LIB_DIR/render.sh"

eval "$(declare -f _journal_snapshot | sed 's/_journal_snapshot/_review_original_snapshot/g')"
_journal_snapshot() {
  _review_original_snapshot "$@"
  if [ ! -e "$LOCAL/review-arrival-injected" ]; then
    : > "$LOCAL/review-arrival-injected"
    jq -nc '{ts:"2026-09-19T10:03:00+00:00",seq:1,dev:"late-device",sid:"late",type:"next.set",data:{ref:"LATE",text:"arrived during rebuild",project:"",ts:"2026-09-19T10:03:00+00:00"}}' \
      > "$JOURNAL_DIR/late-device.jsonl"
  fi
}

views_rebuild
jq -e 'has("LATE")' "$NOTES" >/dev/null
[ "$(_journal_fingerprint)" = "$(cat "$VIEWS/.fingerprint")" ]
BASH
  then
    return 1
  fi
}

test_ignore_preservation() {
  local home="$CASE_ROOT/ignore" mode_before mode_after
  init_home "$home"
  printf '%s\n' '# user exclusions' 'private/' '!private/keep.md' '# keep this comment' \
    > "$home/.stignore"
  chmod 640 "$home/.stignore"
  mode_before="$(stat -c '%a' "$home/.stignore")"
  dave_at "$home" sync setup >/dev/null
  mode_after="$(stat -c '%a' "$home/.stignore")"
  assert_file_contains "setup preserves a user directory exclusion" "$home/.stignore" "private/"
  assert_file_contains "setup preserves a user negation" "$home/.stignore" "!private/keep.md"
  assert_file_contains "setup preserves a user comment" "$home/.stignore" "# keep this comment"
  assert_file_contains "setup protects migration archives" "$home/.stignore" '/.migrated-*'
  assert_file_contains "setup protects local state" "$home/.stignore" '/.local'
  assert_eq "setup preserves ignore permissions" "$mode_before" "$mode_after"
}

test_traversal() {
  local home="$CASE_ROOT/traversal" outside="$CASE_ROOT/outside.sync-conflict-20260919-120000-ABC.md" rc
  init_home "$home"
  printf '%s\n' 'outside the vault' > "$outside"
  set +e
  dave_at "$home" sync conflicts resolve "../$(basename "$outside")" keep-local \
    >/dev/null 2>"$CASE_ROOT/traversal.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail_test "traversal conflict resolution unexpectedly succeeded"
  [ -e "$outside" ] || fail_test "traversal resolution deleted a file outside the vault"
}

test_dashboard_refresh() {
  local home="$CASE_ROOT/dashboard"
  mkdir -p "$home/journal"
  printf '%s\n' '{"ts":"2026-09-19T10:00:00+00:00"}' > "$home/journal/newest.jsonl"
  python3 - "$home" "$DASHBOARD_DIR" <<'PY'
import os
import sys
import threading
from pathlib import Path

home = Path(sys.argv[1])
sys.path.insert(0, sys.argv[2])
from server import ChangeWatcher  # noqa: E402

os.utime(home / "journal/newest.jsonl", (2_000_000_000, 2_000_000_000))
calls = []
second_callback = threading.Event()

def callback() -> None:
    calls.append("called")
    if len(calls) == 1:
        raise RuntimeError("one transient refresh failure")
    second_callback.set()

watcher = ChangeWatcher(home, interval=0.01, on_journal_change=callback)
before = watcher._scan_journal()
peer = home / "journal/older-peer.jsonl"
peer.write_text('{"ts":"2026-09-19T09:00:00+00:00"}\n', encoding="utf-8")
os.utime(peer, (1_999_999_999, 1_999_999_999))
after = watcher._scan_journal()
if before == after:
    raise AssertionError("an older-mtime peer arrival did not change the journal signature")

watcher.start()
if not second_callback.wait(3):
    watcher.stop()
    watcher._thread.join(1)
    raise AssertionError(f"refresh callback was not retried after failure (calls={len(calls)})")
watcher.stop()
watcher._thread.join(1)
if len(calls) < 2:
    raise AssertionError(f"expected a callback retry, got {len(calls)} call(s)")
PY
}

run_case() {
  local name="$1" status=0
  selected "$name" || return 0
  printf '%s\n' "$name"
  new_case
  # Invoke the case in a subshell with errexit enabled. Calling a function in
  # an `if`/`||` list disables errexit for its entire body, which would let a
  # failed assertion be hidden by a later successful assertion.
  set +e
  ( set -Eeuo pipefail; "test_${name//-/_}" )
  status=$?
  set -e
  finish_case
  if [ "$status" -eq 0 ]; then
    PASS=$((PASS + 1))
    if contains_csv "$name"; then
      XPASS=$((XPASS + 1))
      printf '  XPASS %s\n' "$name"
    else
      printf '  PASS   %s\n' "$name"
    fi
  elif contains_csv "$name"; then
    XFAIL=$((XFAIL + 1))
    printf '  XFAIL  %s (reviewed behavior is not implemented yet)\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL   %s\n' "$name"
  fi
}

usage() {
  cat <<'EOF'
usage: review-regressions.sh [--strict] [selector ...]

selectors: offline-identity rebuild-arrival ignore-preservation traversal dashboard-refresh
By default, the five known review regressions are reported as XFAIL until fixed.
--strict makes any remaining XFAIL fail the process.
EOF
}

SELECTORS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    --list) usage; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --*) usage >&2; exit 2 ;;
    *) SELECTORS+=("$arg") ;;
  esac
done

trap finish_case EXIT
run_case offline-identity
run_case rebuild-arrival
run_case ignore-preservation
run_case traversal
run_case dashboard-refresh

printf '\nreview regressions: %d pass, %d xfail, %d fail\n' "$PASS" "$XFAIL" "$FAIL"
if [ "$STRICT" -eq 1 ] && [ "$XFAIL" -gt 0 ]; then
  exit 1
fi
[ "$FAIL" -eq 0 ]
