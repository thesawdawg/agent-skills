#!/usr/bin/env bash
# D.A.V.E.'s state guarantees depend on Linux locking and path utilities.
set -euo pipefail
for required in bash jq flock realpath readlink stat mktemp sha256sum; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'dave preflight: missing required executable: %s\n' "$required" >&2
    exit 3
  }
done
printf 'dave preflight: local state dependencies available\n'
