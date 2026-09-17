#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for mode in local repo; do
  project="$tmp/project-$mode"
  mkdir -p "$project/.agents" "$project/docs"
  git -C "$project" init -q
  git -C "$project" config user.name Test
  git -C "$project" config user.email test@example.invalid
  printf 'original\n' > "$project/docs/page.md"
  printf 'code\n' > "$project/code.txt"
  git -C "$project" add .
  git -C "$project" commit -qm 'test: seed'
  jq -n --arg mode "$mode" --arg path "$project" '{mode:$mode,local_docs:{docs_root:"docs"},doc_repo:{path:$path,docs_root:"docs"}}' > "$project/.agents/commit-documentor.json"
  printf 'changed\n' > "$project/code.txt"
  git -C "$project" add code.txt
  printf 'unrelated\n' > "$project/docs/untracked.md"
  printf 'draft\n' > "$project/docs/page.md"
  printf 'docs: update page\n' > "$tmp/message"
  printf 'docs/page.md\n' > "$tmp/approved"
  (cd "$project" && bash "$root/commit-documentor/scripts/doc-repo.sh" publish docs/test "$tmp/message" "$tmp/approved")
  test "$(git -C "$project" show --format= --name-only HEAD)" = docs/page.md
  test "$(git -C "$project" diff --cached --name-only)" = code.txt
  test -f "$project/docs/untracked.md"
  if (cd "$project" && bash "$root/commit-documentor/scripts/doc-repo.sh" revert); then
    echo 'Unsafe revert unexpectedly succeeded' >&2; exit 1
  fi
  test -f "$project/docs/untracked.md"
done
printf 'Documentation isolation tests passed\n'
