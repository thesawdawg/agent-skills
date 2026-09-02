#!/usr/bin/env bash
# Helper for commit-documentor: resolve, sync, search, and publish to the
# configured documentation repository. All doc reads are local git/grep
# against a clone — no API calls — so repeated queries are cheap.
#
# Usage:
#   doc-repo.sh config                          # print resolved config as JSON
#   doc-repo.sh path                            # print resolved doc repo clone path
#   doc-repo.sh sync                            # clone if missing, else fetch+fast-forward
#   doc-repo.sh list                            # list tracked doc files under docs_root
#   doc-repo.sh search <term> [term...]         # grep doc files for terms (OR), file:line:text
#   doc-repo.sh diff                            # working-tree diff of the doc repo
#   doc-repo.sh publish <branch> <commit-msg-file> [pr-body-file]
#
# Config is read from the FIRST of these that exists in the project repo:
#   .claude/commit-documentor.json
#   .commit-documentor.json
# See templates/config-template.json for the schema.

set -euo pipefail

project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

config_file=""
for candidate in "$project_root/.claude/commit-documentor.json" "$project_root/.commit-documentor.json"; do
  [ -f "$candidate" ] && { config_file="$candidate"; break; }
done

if [ -z "$config_file" ]; then
  echo "commit-documentor: no config found. Expected $project_root/.claude/commit-documentor.json" >&2
  echo "Copy templates/config-template.json there and fill in doc_repo.path/remote." >&2
  exit 3
fi

command -v jq >/dev/null || { echo "commit-documentor: jq is required" >&2; exit 3; }

cfg() { jq -r "$1 // empty" "$config_file"; }

raw_path=$(cfg '.doc_repo.path')
remote=$(cfg '.doc_repo.remote')
branch=$(cfg '.doc_repo.branch'); branch="${branch:-main}"
docs_root=$(cfg '.doc_repo.docs_root'); docs_root="${docs_root:-.}"
doc_path="${raw_path/#\~/$HOME}"

[ -n "$doc_path" ] || { echo "commit-documentor: doc_repo.path is not set in $config_file" >&2; exit 3; }

in_docs() { git -C "$doc_path" "$@"; }

cmd="${1:-}"
[ -n "$cmd" ] || { echo "usage: doc-repo.sh {config|path|sync|list|search|diff|publish} ..." >&2; exit 2; }
shift || true

case "$cmd" in
  config)
    jq '.' "$config_file"
    ;;

  path)
    echo "$doc_path"
    ;;

  sync)
    if [ ! -d "$doc_path/.git" ]; then
      [ -n "$remote" ] || { echo "commit-documentor: $doc_path is not a clone and doc_repo.remote is unset" >&2; exit 3; }
      git clone "$remote" "$doc_path"
    fi
    if ! in_docs remote get-url origin >/dev/null 2>&1; then
      echo "commit-documentor: $doc_path has no 'origin' remote; set doc_repo.remote and re-clone." >&2
      exit 3
    fi
    in_docs fetch --prune origin
    # Refuse to move a dirty tree; the user may have work in progress there.
    if [ -n "$(in_docs status --porcelain)" ]; then
      echo "commit-documentor: doc repo at $doc_path has uncommitted changes; not switching branches." >&2
      in_docs status --short >&2
      exit 4
    fi
    in_docs checkout "$branch"
    in_docs merge --ff-only "origin/$branch"
    in_docs log -1 --oneline
    ;;

  list)
    in_docs ls-files -- "$docs_root" | grep -Ei '\.(md|mdx|markdown|rst|txt|adoc)$' || true
    ;;

  search)
    [ "$#" -gt 0 ] || { echo "usage: doc-repo.sh search <term> [term...]" >&2; exit 2; }
    pattern=$(printf '%s\n' "$@" | paste -sd '|' -)
    in_docs grep -n -I -i -E "$pattern" -- "$docs_root" || true
    ;;

  diff)
    in_docs --no-pager diff
    ;;

  publish)
    new_branch="${1:?branch name required}"
    msg_file="${2:?commit message file required}"
    body_file="${3:-}"
    [ -f "$msg_file" ] || { echo "commit-documentor: commit message file not found: $msg_file" >&2; exit 2; }
    [ -n "$(in_docs status --porcelain)" ] || { echo "commit-documentor: no doc changes to publish" >&2; exit 5; }
    in_docs checkout -b "$new_branch"
    in_docs add -A
    in_docs commit -F "$msg_file"
    in_docs push -u origin "$new_branch"
    if command -v gh >/dev/null; then
      if [ -n "$body_file" ] && [ -f "$body_file" ]; then
        (cd "$doc_path" && gh pr create --base "$branch" --head "$new_branch" \
          --title "$(head -1 "$msg_file")" --body-file "$body_file") \
          || echo "commit-documentor: branch pushed, but 'gh pr create' failed — open the PR manually against $branch." >&2
      else
        (cd "$doc_path" && gh pr create --base "$branch" --head "$new_branch" \
          --title "$(head -1 "$msg_file")" --body "$(tail -n +2 "$msg_file")") \
          || echo "commit-documentor: branch pushed, but 'gh pr create' failed — open the PR manually against $branch." >&2
      fi
    else
      echo "gh CLI not found — branch pushed; open the PR manually against $branch." >&2
    fi
    ;;

  *)
    echo "unknown command: $cmd" >&2
    exit 2
    ;;
esac
