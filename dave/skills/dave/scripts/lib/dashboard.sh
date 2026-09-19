# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# dashboard.sh — the local web dashboard.
# Sourced by dave.sh.
#
# The dashboard is a read-mostly view over the same state tree; every write it
# offers goes back through dave.sh, so this file stays the only writer. The
# server binds loopback only — the state tree is personal and never leaves the
# machine.

cmd_dashboard() {
  require_init
  command -v python3 >/dev/null 2>&1 || die "python3 is required for the dashboard"
  local port=8766
  while [ $# -gt 0 ]; do
    case "$1" in
      --port) port="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1 (usage: dashboard [--port N])" ;;
    esac
  done
  case "$port" in ''|*[!0-9]*) die "port must be a number" ;; esac
  echo "dashboard: http://127.0.0.1:$port/ (Ctrl-C to stop)"
  export DAVE_HOME
  exec python3 "$SCRIPT_DIR/../dashboard/server.py" --port "$port" --dave-sh "$SCRIPT_DIR/dave.sh"
}
