#!/usr/bin/env bash
set -euo pipefail
for command in node npm; do
  command -v "$command" >/dev/null || { echo "Missing required executable: $command" >&2; exit 3; }
done
node -e 'if (Number(process.versions.node.split(".")[0]) < 18) process.exit(3)'
printf 'Node/npm available; use setup.sh and launch to verify Chromium runtime.\n'
