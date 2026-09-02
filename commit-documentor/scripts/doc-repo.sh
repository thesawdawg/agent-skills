#!/usr/bin/env bash
# Helper for commit-documentor: resolve, sync, search, and publish documentation.
#
# Two modes, set by "mode" in the config:
#   repo  (default) — docs live in a SEPARATE repository, cloned locally.
#                     publish = branch + commit + push + PR.
#   local           — docs live in THIS project repo under docs_root.
#                     No remote, no branch, no push: publish = commit on the
#                     current branch, leaving pushing to the user.
#
# All doc reads are local git/grep — no API calls — so repeated queries are cheap.
#
# Usage:
#   doc-repo.sh config                          # print resolved config as JSON
#   doc-repo.sh mode                            # print resolved mode (repo|local)
#   doc-repo.sh path                            # print the repo path docs live in
#   doc-repo.sh root                            # print docs_root
#   doc-repo.sh sync                            # repo: clone or fetch+ff. local: no-op check
#   doc-repo.sh list                            # list tracked doc files under docs_root
#   doc-repo.sh search <term> [term...]         # grep doc files for terms (OR), file:line:text
#   doc-repo.sh diff                            # working-tree diff, scoped to docs_root
#   doc-repo.sh revert                          # discard drafted doc changes under docs_root
#   doc-repo.sh publish <branch> <commit-msg-file> [pr-body-file]
#                                               # local mode ignores <branch>
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
  echo "Run the first-run setup in SKILL.md — do not guess a documentation location." >&2
  exit 3
fi

command -v jq >/dev/null || { echo "commit-documentor: jq is required" >&2; exit 3; }
jq -e . "$config_file" >/dev/null 2>&1 || { echo "commit-documentor: $config_file is not valid JSON" >&2; exit 3; }

cfg() { jq -r "$1 // empty" "$config_file"; }

mode=$(cfg '.mode'); mode="${mode:-repo}"

case "$mode" in
  repo)
    raw_path=$(cfg '.doc_repo.path')
    remote=$(cfg '.doc_repo.remote')
    branch=$(cfg '.doc_repo.branch'); branch="${branch:-main}"
    docs_root=$(cfg '.doc_repo.docs_root'); docs_root="${docs_root:-.}"
    doc_path="${raw_path/#\~/$HOME}"
    [ -n "$doc_path" ] || { echo "commit-documentor: mode is \"repo\" but doc_repo.path is not set in $config_file" >&2; exit 3; }
    ;;
  local)
    doc_path="$project_root"
    remote=""
    branch=""
    docs_root=$(cfg '.local_docs.docs_root'); docs_root="${docs_root:-docs/}"
    ;;
  *)
    echo "commit-documentor: unknown mode \"$mode\" in $config_file (expected \"repo\" or \"local\")" >&2
    exit 3
    ;;
esac

in_docs() { git -C "$doc_path" "$@"; }

cmd="${1:-}"
[ -n "$cmd" ] || { echo "usage: doc-repo.sh {config|mode|path|root|sync|list|search|diff|revert|publish} ..." >&2; exit 2; }
shift || true

case "$cmd" in
  config)  jq '.' "$config_file" ;;
  mode)    echo "$mode" ;;
  path)    echo "$doc_path" ;;
  root)    echo "$docs_root" ;;

  sync)
    if [ "$mode" = "local" ]; then
      mkdir -p "$doc_path/$docs_root"
      echo "local mode: docs live in this repo under $docs_root — nothing to sync."
      in_docs log -1 --oneline
      exit 0
    fi
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
    # Scoped to docs_root so local mode never shows the user's unrelated code changes.
    in_docs --no-pager diff -- "$docs_root"
    # Untracked drafts (new doc pages) don't appear in `git diff` — show them too,
    # in full, so approval covers the whole proposed change.
    in_docs ls-files --others --exclude-standard -- "$docs_root" | while read -r f; do
      in_docs --no-pager diff --no-index -- /dev/null "$f" || true
    done
    ;;

  revert)
    in_docs checkout -- "$docs_root" 2>/dev/null || true
    in_docs clean -fd -- "$docs_root"
    echo "reverted drafted doc changes under $docs_root"
    ;;

  publish)
    new_branch="${1:?branch name required (ignored in local mode)}"
    msg_file="${2:?commit message file required}"
    body_file="${3:-}"
    [ -f "$msg_file" ] || { echo "commit-documentor: commit message file not found: $msg_file" >&2; exit 2; }
    if [ -z "$(in_docs status --porcelain -- "$docs_root")" ]; then
      echo "commit-documentor: no doc changes under $docs_root to publish" >&2
      exit 5
    fi

    if [ "$mode" = "local" ]; then
      # Stay on the user's current branch and commit ONLY the docs, so unrelated
      # working-tree changes are never swept into the commit. Never pushes.
      in_docs add -A -- "$docs_root"
      in_docs commit -F "$msg_file" -- "$docs_root"
      in_docs log -1 --oneline
      echo "local mode: committed on $(in_docs rev-parse --abbrev-ref HEAD); not pushed — push with the rest of your work." >&2
      exit 0
    fi

    in_docs checkout -b "$new_branch"
    in_docs add -A -- "$docs_root"
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
