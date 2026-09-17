#!/usr/bin/env bash
# Manage a single, sequential Codex CLI session used as an external subagent.
#
# Usage:
#   codex-session.sh start <state-file> <sandbox> <prompt>
#   codex-session.sh send  <state-file> <prompt>
#   codex-session.sh id    <state-file>
#
# <sandbox> (start only): read-only | workspace-write | danger-full-access
#
# Prints Codex's final reply to stdout. On failure, prints the raw Codex
# JSONL event log to stderr and exits non-zero. Never runs two Codex
# processes at once — each call is a single blocking turn in one thread.

set -euo pipefail
umask 077
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 3; }
log=""; last=""
trap '[ -z "$log" ] || rm -f "$log"; [ -z "$last" ] || rm -f "$last"' EXIT

cmd="${1:-}"
[ -n "$cmd" ] || { echo "usage: codex-session.sh {start|send|id} ..." >&2; exit 2; }
shift

run_codex() {
  # run_codex <log-file> <last-file> <codex-args...>
  local log="$1" last="$2"
  shift 2
  if ! codex "$@" --json -o "$last" < /dev/null > "$log" 2>&1; then
    echo "codex exited non-zero; event log:" >&2
    cat "$log" >&2
    exit 1
  fi
}

case "$cmd" in
  start)
    state_file="${1:?state-file required}"; sandbox="${2:?sandbox required}"; prompt="${3:?prompt required}"
    [ ! -e "$state_file" ] || { echo 'state already exists; use send or a new state path' >&2; exit 2; }
    case "$sandbox" in read-only|workspace-write|danger-full-access) ;; *) echo 'invalid sandbox' >&2; exit 2 ;; esac
    log=$(mktemp); last=$(mktemp)
    run_codex "$log" "$last" exec "$prompt" -s "$sandbox"
    thread_id=$(jq -rs '[.[] | select(.type == "thread.started") | .thread_id | select(type == "string" and length > 0)][0] // empty' "$log")
    if [ -z "$thread_id" ]; then
      echo "could not find thread_id in codex output:" >&2
      cat "$log" >&2
      rm -f "$log" "$last"
      exit 1
    fi
    echo "$thread_id" > "$state_file"
    cat "$last"
    rm -f "$log" "$last"
    ;;
  send)
    state_file="${1:?state-file required}"; prompt="${2:?prompt required}"
    [ -f "$state_file" ] || { echo "no active session: $state_file not found (run 'start' first)" >&2; exit 1; }
    thread_id=$(cat "$state_file")
    log=$(mktemp); last=$(mktemp)
    run_codex "$log" "$last" exec resume "$thread_id" "$prompt"
    cat "$last"
    rm -f "$log" "$last"
    ;;
  id)
    state_file="${1:?state-file required}"
    [ -f "$state_file" ] || { echo "no active session: $state_file not found" >&2; exit 1; }
    cat "$state_file"
    ;;
  *)
    echo "usage: codex-session.sh {start|send|id} ..." >&2
    exit 2
    ;;
esac
