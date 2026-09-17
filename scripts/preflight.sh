#!/usr/bin/env bash
# Aggregate local executable checks; do not install or contact services.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
while IFS= read -r -d '' fragment; do
  bash "$fragment"
done < <(find "$root" -path '*/node_modules' -prune -o -path '*/scripts/preflight.sh' ! -path "$root/scripts/preflight.sh" -print0)
