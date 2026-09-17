#!/usr/bin/env bash
# Pass the actual installed dogfood path; never infer it from the user's cwd.
set -euo pipefail
if [ -z "${1:-}" ]; then
  echo 'Accessibility: dogfood dependency is checked at invocation with preflight.sh /installed/dogfood.'
  exit 0
fi
[ -f "$1/scripts/preflight.sh" ] && [ -f "$1/scripts/setup.sh" ] || {
  echo 'Missing dogfood dependency; install it or select an equivalent native browser.' >&2
  exit 3
}
bash "$1/scripts/preflight.sh"
