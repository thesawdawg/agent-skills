# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# common.sh — paths, constants and shared helpers for dave.sh.
#
# Sourced by dave.sh; not executable on its own. Every other lib may assume the
# names defined here exist. `set -euo pipefail` is the caller's job.

# Resolved from this file rather than from dave.sh, so a test can source the lib
# directly without standing up the dispatcher.
DAVE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$DAVE_LIB_DIR/.." && pwd)"
TEMPLATES="$SCRIPT_DIR/../templates"
# <plugin>/skills/dave/scripts -> <plugin>. Phase C reads agents/ from here.
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || echo "")"

DAVE_HOME="${DAVE_HOME:-$HOME/.dave}"

CONFIG="$DAVE_HOME/config.json"
STATE="$DAVE_HOME/state.json"
PRIORITIES="$DAVE_HOME/priorities.md"
PARKING="$DAVE_HOME/parking-lot.md"
LOGDIR="$DAVE_HOME/log"
MISSIONS="$DAVE_HOME/missions"
INTAKE="$DAVE_HOME/intake"

# Added by the projects/instrumentation/orchestration work. Created lazily —
# a tree without them is a valid tree, and every reader defaults gracefully.
PROJECTS="$DAVE_HOME/projects"
NOTES="$DAVE_HOME/notes.json"
COMMITMENTS="$DAVE_HOME/commitments.json"
SESSIONS="$DAVE_HOME/sessions.jsonl"
ASSIGNMENTS="$DAVE_HOME/assignments.jsonl"
MISSIONS_JSON="$DAVE_HOME/missions.json"
SCAN_CACHE="$DAVE_HOME/scan-cache.json"

# Bumped when the on-disk shape changes. `require_init` exits 4 below this.
SCHEMA_VERSION=2

die() { echo "dave: $*" >&2; exit 1; }

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
}

today() { date +%F; }
now_iso() { date -Iseconds; }

# Exit 3 is the agreed "not set up yet" signal, distinct from a real error.
# Exit 4 is "set up, but the state tree predates this version" — run `migrate`.
require_init() {
  [ -f "$CONFIG" ] || exit 3
  # The version check needs jq. Without it, skip rather than die: commands that
  # genuinely need jq call need_jq themselves, and `priorities` never did.
  command -v jq >/dev/null 2>&1 || return 0
  local v
  v="$(jq -r '.schema_version // 1' "$STATE" 2>/dev/null || echo 1)"
  case "$v" in
    ''|*[!0-9]*) v=1 ;;
  esac
  [ "$v" -ge "$SCHEMA_VERSION" ] || exit 4
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-60
}

# Atomically replace a JSON file with the result of a jq program.
json_edit() {
  local file="$1"; shift
  local tmp
  tmp="$(mktemp "${file}.XXXXXX")"
  if jq "$@" "$file" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    die "failed to update $file"
  fi
}

# Create a JSON file with a seed value if it does not exist yet. Lazy creation is
# what lets a v1 tree keep working until someone actually uses a new command.
json_ensure() {
  local file="$1" seed="$2"
  [ -f "$file" ] || printf '%s\n' "$seed" > "$file"
}

# --------------------------------------------------------------- JSONL helpers

# Append one JSON object as a single line. Locked where flock exists, because a
# charge can exceed the size a single write is guaranteed to make atomic.
#
# If a previous append was interrupted the file ends without a newline, and
# appending straight onto it would splice the new record onto the broken one --
# losing a good record to an old accident. So terminate the stray line first: the
# damaged record stays damaged and gets skipped on read, and this one survives.
jsonl_append() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  if command -v flock >/dev/null 2>&1; then
    (
      flock 9
      if [ -s "$file" ] && [ -n "$(tail -c1 "$file")" ]; then printf '\n' >&9; fi
      printf '%s\n' "$line" >&9
    ) 9>>"$file"
  else
    if [ -s "$file" ] && [ -n "$(tail -c1 "$file")" ]; then printf '\n' >> "$file"; fi
    printf '%s\n' "$line" >> "$file"
  fi
}

# Emit every well-formed record in a .jsonl file, one per line.
#
# An append interrupted mid-write leaves a truncated final line, and jq stops
# streaming at the first bad record — which would silently hide every record
# before it in the buffer and every record after it in the file. So: try the fast
# path whole, and only if it fails fall back to filtering line by line.
jsonl_stream() {
  local file="$1" out
  [ -f "$file" ] || return 0
  if out="$(jq -c . "$file" 2>/dev/null)"; then
    [ -n "$out" ] && printf '%s\n' "$out"
    return 0
  fi
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    printf '%s\n' "$line" | jq -c . 2>/dev/null || true
  done < "$file"
}

# jsonl_fold <file> <jq-program> [jq-args...] — the records arrive as one array.
jsonl_fold() {
  local file="$1" prog="$2"; shift 2
  jsonl_stream "$file" | jq -s "$@" "$prog"
}

# ---------------------------------------------------------------- JSON readers

# json_get <file> <jq-path> [default] — never fails, never prints "null".
json_get() {
  local file="$1" path="$2" dflt="${3:-}" v
  if [ ! -f "$file" ]; then printf '%s\n' "$dflt"; return 0; fi
  v="$(jq -r "$path // empty" "$file" 2>/dev/null || true)"
  if [ -n "$v" ]; then printf '%s\n' "$v"; else printf '%s\n' "$dflt"; fi
}

config_get() { json_get "$CONFIG" "$1" "${2:-}"; }

# Booleans need their own reader: jq's `//` yields the right-hand side for `false`
# as well as null, so `.x // true` can never return false. The session-start hook
# learned this the hard way; do not "simplify" this back into json_get.
config_bool() {
  local path="$1" dflt="$2"
  jq -r "if $path == null then \"$dflt\" else ($path | tostring) end" "$CONFIG" \
    2>/dev/null || printf '%s\n' "$dflt"
}

# ------------------------------------------------------------------------ git

# git_probe <path> — one JSON object describing a working tree, or a flagged
# object saying why there isn't one. Never fatal: a project whose directory was
# moved or deleted must not take down a scan of nine others.
#
# Deliberately never fetches. ahead/behind is measured against the last-known
# remote ref, and callers say so rather than implying freshness they don't have.
git_probe() {
  local path="$1"
  if [ ! -d "$path" ]; then
    jq -n --arg p "$path" '{path:$p, exists:false, repo:false}'
    return 0
  fi
  if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    jq -n --arg p "$path" '{path:$p, exists:true, repo:false}'
    return 0
  fi

  local branch porcelain dirty untracked last_ts last_subj ahead behind counts
  branch="$(git -C "$path" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  porcelain="$(git -C "$path" --no-optional-locks status --porcelain 2>/dev/null || true)"
  dirty="$(printf '%s' "$porcelain" | grep -c -v '^??' || true)"
  untracked="$(printf '%s' "$porcelain" | grep -c '^??' || true)"
  [ -n "$porcelain" ] || { dirty=0; untracked=0; }
  last_ts="$(git -C "$path" --no-optional-locks log -1 --format=%cI 2>/dev/null || echo '')"
  last_subj="$(git -C "$path" --no-optional-locks log -1 --format=%s 2>/dev/null || echo '')"

  ahead=0; behind=0
  if counts="$(git -C "$path" --no-optional-locks rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)"; then
    behind="$(printf '%s' "$counts" | awk '{print $1}')"
    ahead="$(printf '%s' "$counts" | awk '{print $2}')"
  fi

  jq -n --arg p "$path" --arg b "$branch" --arg ts "$last_ts" --arg subj "$last_subj" \
        --argjson dirty "${dirty:-0}" --argjson untracked "${untracked:-0}" \
        --argjson ahead "${ahead:-0}" --argjson behind "${behind:-0}" \
    '{path:$p, exists:true, repo:true, branch:$b, dirty:$dirty, untracked:$untracked,
      ahead:$ahead, behind:$behind, last_commit:($ts|select(. != "")), last_subject:$subj}'
}
