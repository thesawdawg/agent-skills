#!/usr/bin/env bash
# Prepare a lockfile-keyed writable runtime without mutating the installed skill.
set -euo pipefail
source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
key=$(sha256sum "$source_dir/package-lock.json" | cut -c1-16)
cache="${DOGFOOD_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/agent-skills/dogfood}/$key"
mkdir -p "$cache"
cp "$source_dir/package.json" "$source_dir/package-lock.json" "$source_dir/browser-driver.mjs" "$cache/"
(cd "$cache" && npm ci --ignore-scripts >&2)
if [ "${1:-}" = --install-browser ]; then
  node "$cache/node_modules/playwright/cli.js" install chromium >&2
fi
printf '%s\n' "$cache/browser-driver.mjs"
