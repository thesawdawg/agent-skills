#!/usr/bin/env bash
# dave.sh - state layer for D.A.V.E. (Digital Assistant for Various Endeavors)
#
# Every piece of durable state lives under $DAVE_HOME (default ~/.dave) as plain
# markdown and JSON, so the user can read and hand-edit any of it without D.A.V.E.
# in the loop. This script is the only thing that writes there.
#
# The implementation is split across lib/ by concern; this file is dispatch and
# help only. Exit 3 means "not set up"; exit 4 means "set up, but run migrate".
#
# Usage: dave.sh <command> [args]   -- run `dave.sh help` for the full list.

set -euo pipefail

DAVE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
. "$DAVE_SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/state.sh
. "$DAVE_SCRIPT_DIR/lib/state.sh"
# shellcheck source=lib/focus.sh
. "$DAVE_SCRIPT_DIR/lib/focus.sh"
# shellcheck source=lib/journal.sh
. "$DAVE_SCRIPT_DIR/lib/journal.sh"
# shellcheck source=lib/mission.sh
. "$DAVE_SCRIPT_DIR/lib/mission.sh"
# shellcheck source=lib/project.sh
. "$DAVE_SCRIPT_DIR/lib/project.sh"
# shellcheck source=lib/track.sh
. "$DAVE_SCRIPT_DIR/lib/track.sh"
# shellcheck source=lib/review.sh
. "$DAVE_SCRIPT_DIR/lib/review.sh"
# shellcheck source=lib/sync.sh
. "$DAVE_SCRIPT_DIR/lib/sync.sh"
# shellcheck source=lib/dashboard.sh
. "$DAVE_SCRIPT_DIR/lib/dashboard.sh"

cmd_help() {
  cat <<'HELP'
dave.sh — state layer for D.A.V.E.  (state lives in $DAVE_HOME, default ~/.dave)

 setup
  init                      create the state tree from templates (idempotent)
  migrate                   bring an older state tree up to the current schema
  home                      print the state directory path
  config                    print config.json          (exit 3 if not set up)
  state                     print state.json

 orientation
  brief                     composite read: project, focus, priorities, today, parked
  review [--days N]         the weekly sweep: what is slipping, owed, rotting  [--json]
  priorities [set]          print priorities.md, or replace it from stdin

 projects
  project add <path>        register a project  [--name --slug --cadence --goal --status]
  project list              registered projects  [--status S] [--json]
  project show [slug]       one project: refs, git state, open missions
  project status <slug> <s> active | paused | maintenance | archived
  project link <slug> <ref> attach a priority ref to a project  (also: unlink)
  project of <ref>          which project owns a ref
  project resolve [path]    which project a directory belongs to (silent if none)
  project touch [slug]      stamp last activity
  scan [slug]               git state across projects  [--json] [--fresh] [--all]

 tracking
  next set <ref> <text>     record where you left off  (also: next show, next clear)
  promise add <who> <what> <due>   record a commitment  [--ref R] [--project P]
  promise list              commitments  [--open] [--due-within N] [--json]
  promise keep|miss <id>    close one out
  promise move <id> <due>   renegotiate a date, keeping the history

 focus
  focus set <ref> [label]   set the current focus (banks the previous one)
  focus push <ref> [label]  keep the current focus and stack it under a detour
  focus pop                 close the detour and return to what it interrupted
  focus clear               clear it
  focus show                print it, plus anything stacked under it
  time [ref]                recorded time  [--since D] [--project P] [--json]
  drift                     minutes on focus + whether the ref is still on the list
  drift record <kind> <out> log a resolved drift episode (kind: unlisted,
                            third-repo, parked-resurfaced, no-focus; outcome:
                            parked, promoted, continued)
  drift events [--days N]   what drift has looked like lately

 capture
  park <text>               capture a detour without acting on it
  parked [done <n>]         list open parked items, or retire the n-th one
  log <text>                append a timestamped line to today's log
  today                     print today's log
  standup [days]            print the last N days of log (default 1)
  intake <source>           archive a board pasted on stdin, print path

 missions
  mission new <name>        create a mission brief  [--project P] [--ref R]
  mission open <slug>       make it the active mission (assign then defaults to it)
  mission close <slug>      close it  [--outcome TEXT]
  mission show <slug>       the brief, with its assignments table rendered
  mission list              missions  [--open] [--project P] [--json]
  mission assign [m] <agent> <charge>   record a delegation, print its id
                            [--model M] [--ref R]
  mission record <id> --verdict <trust|partial|rerun|discard> [--summary TEXT]
  mission status [slug]     charges still outstanding
  mission pack <slug> --agent <name>    assemble the five-part briefing

 dossiers
  dossier set [slug]        cache a codebase map, read from stdin
  dossier get [slug]        print it, with how far the repo has moved since

 sync
  sync setup <remote-url>   make ~/.dave a git repo tracking a private remote
  sync pull                 rebase local state onto remote (runs inside brief)
  sync push                 commit + push state (user-run only)
  sync status               ahead/behind/dirty vs remote

 dashboard
  dashboard [--port N]      serve the local web dashboard (127.0.0.1 only)

Exit codes: 3 = not set up (run init) · 4 = state schema is behind (run migrate)
HELP
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    init) cmd_init "$@" ;;
    migrate) cmd_migrate "$@" ;;
    home) cmd_home "$@" ;;
    config) cmd_config "$@" ;;
    state) cmd_state "$@" ;;
    brief) cmd_brief "$@" ;;
    review) cmd_review "$@" ;;
    priorities) cmd_priorities "$@" ;;
    focus) cmd_focus "$@" ;;
    drift) cmd_drift "$@" ;;
    park) cmd_park "$@" ;;
    parked) cmd_parked "$@" ;;
    log) cmd_log "$@" ;;
    today) cmd_today "$@" ;;
    standup) cmd_standup "$@" ;;
    mission) cmd_mission "$@" ;;
    project) cmd_project "$@" ;;
    dossier) cmd_dossier "$@" ;;
    scan) cmd_scan "$@" ;;
    time) cmd_time "$@" ;;
    next) cmd_next "$@" ;;
    promise) cmd_promise "$@" ;;
    intake) cmd_intake "$@" ;;
    sync) cmd_sync "$@" ;;
    dashboard) cmd_dashboard "$@" ;;
    help|-h|--help) cmd_help ;;
    *) die "unknown command: $cmd (try: dave.sh help)" ;;
  esac
}

main "$@"
