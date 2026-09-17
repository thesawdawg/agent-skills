#!/usr/bin/env bash
# Ensure a fixture failure in command substitution cannot produce a green suite.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R "$root/dave/skills/dave" "$tmp/dave"
sed -i 's/$(date +%F)/$(missing_fixture_command)/g' "$tmp/dave/scripts/test/run.sh"
if bash "$tmp/dave/scripts/test/run.sh" mission_legacy > "$tmp/log" 2>&1; then
  echo 'Broken fixture incorrectly passed' >&2
  exit 1
fi
grep -q 'unexpected failure' "$tmp/log"
echo 'Unexpected fixture failure correctly fails the suite'
