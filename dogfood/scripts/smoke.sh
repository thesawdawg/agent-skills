#!/usr/bin/env bash
# smoke.sh — quick HTTP route check, no browser needed.
# Use this FIRST: it is fast and catches dead/500 pages before deeper testing.
#
# Usage:
#   bash smoke.sh <base_url> [path1 path2 ...]
# Example:
#   bash smoke.sh http://127.0.0.1:5000 / /login /signup /dashboard

set -u
base="${1:-}"
if [ -z "$base" ]; then
  echo "Usage: bash smoke.sh <base_url> [path ...]" >&2
  exit 1
fi
shift || true
paths=("$@")
[ ${#paths[@]} -eq 0 ] && paths=("/")

printf "%-6s %-8s %s\n" "STATUS" "ms" "PATH"
for p in "${paths[@]}"; do
  out=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" "${base}${p}" 2>/dev/null) || out="000 0"
  code="${out%% *}"; t="${out##* }"
  ms=$(awk "BEGIN{printf \"%d\", ${t}*1000}")
  printf "%-6s %-8s %s\n" "$code" "$ms" "$p"
done
