#!/usr/bin/env bash
set -euo pipefail
for command in curl jq; do
  command -v "$command" >/dev/null || { echo "Missing required executable: $command" >&2; exit 3; }
done
dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash -n "$dir/systemone.sh"
printf 'System One helper: curl/jq available; run systemone.sh probe to verify an endpoint.\n'
