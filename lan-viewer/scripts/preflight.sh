#!/usr/bin/env bash
set -euo pipefail
command -v python3 >/dev/null || { echo "Missing required executable: python3" >&2; exit 3; }
dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for asset in index.html app.js style.css vendor/marked.umd.js vendor/highlight.min.js vendor/mermaid.min.js; do
  [ -f "$dir/../assets/$asset" ] || { echo "Missing asset: $asset" >&2; exit 3; }
done
python3 "$dir/viewer.py" --selftest >/dev/null
printf 'lan-viewer: python3 and bundled assets available; start with viewer.py <files>.\n'
