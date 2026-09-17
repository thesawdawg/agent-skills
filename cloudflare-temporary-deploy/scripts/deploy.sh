#!/usr/bin/env bash
# Run only after public deployment authorization; retain private raw output.
set -euo pipefail
umask 077
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
log="${1:?provide a NEW private log path}"
# Exclusive creation prevents replacing previous deployment credentials.
(set -o noclobber; : > "$log") || exit 2
status=0
npx --yes wrangler@4.102.0 deploy --temporary > "$log" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
  printf 'Deployment failed (exit %s). Private log: %s\n' "$status" "$log" >&2
  exit "$status"
fi
python3 "$script_dir/parse_deploy_output.py" < "$log"
