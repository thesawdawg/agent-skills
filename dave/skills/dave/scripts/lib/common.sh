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

_canonical() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

# ------------------------------------------------------ project-tuned instances
#
# A directory can hold a `.<slug>-dave/` folder that overlays the global config
# and adds project-only role contracts. It is deliberately not a second
# DAVE_HOME: priorities, log, missions and the time ledger stay in ~/.dave so the
# ranked list remains single.
#
# `project_home_resolve` is the discovery half: from a start directory it walks
# up to / looking for the one directory whose name is exactly `.<slug of its own
# basename>-dave` — self-naming, so a copied folder cannot accidentally tune a
# different parent. Silent, exit 0 when there is none: the hook and brief call
# this in directories that have nothing to do with D.A.V.E.
#
# DAVE_PROJECT_HOME overrides discovery. "none" disables it (tests and any
# hook-free path need a way to say "there is no project here" that does not
# depend on cwd); any other value is used verbatim and must point at a real
# instance — a bad override is a loud error, not a silent fallback.
project_home_resolve() {
  if [ -n "${DAVE_PROJECT_HOME:-}" ]; then
    [ "$DAVE_PROJECT_HOME" = "none" ] && return 0
    [ -f "$DAVE_PROJECT_HOME/config.json" ] \
      || die "DAVE_PROJECT_HOME has no config.json: $DAVE_PROJECT_HOME"
    printf '%s\n' "$DAVE_PROJECT_HOME"
    return 0
  fi
  local dir slug
  dir="$(_canonical "${1:-$PWD}")"
  [ -n "$dir" ] && [ -d "$dir" ] || return 0
  while : ; do
    slug="$(slugify "$(basename "$dir")")"
    if [ -f "$dir/.$slug-dave/config.json" ]; then
      printf '%s\n' "$dir/.$slug-dave"
      return 0
    fi
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  return 0
}

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

# ------------------------------------------------------------- effective config
#
# With a project instance present, reads see global config overlaid by the
# project's config.json: `jq .[0] * .[1]` deep-merges, so the overlay only needs
# the leaf it changes and inherits everything else. `_comment*` keys are
# documentation for hand-editers, not settings — they are stripped at every
# level so `config` never prints them.
#
# The merge is materialized once into a temp file and cached for the rest of
# the process. Writers (sync setup, spawn --set) must keep writing the real
# file — config_get is the only reader redirected here.
_DAVE_TMP_FILES=()
_dave_cleanup_tmp() { [ "${#_DAVE_TMP_FILES[@]}" -gt 0 ] && rm -f "${_DAVE_TMP_FILES[@]}"; return 0; }

_EFFECTIVE_CONFIG=""
config_effective_file() {
  [ -n "$_EFFECTIVE_CONFIG" ] && { printf '%s\n' "$_EFFECTIVE_CONFIG"; return 0; }
  if [ -z "$PROJECT_HOME" ] || [ ! -f "$PROJECT_CONFIG" ] || [ ! -f "$CONFIG" ]; then
    _EFFECTIVE_CONFIG="$CONFIG"
  else
    _EFFECTIVE_CONFIG="$(mktemp "${TMPDIR:-/tmp}/dave-effective.XXXXXX")"
    _DAVE_TMP_FILES+=("$_EFFECTIVE_CONFIG")
    # Clean up only when nobody else owns EXIT — appending to a foreign trap
    # risks mangling its quoting, and a leftover mktemp file is harmless.
    [ -z "$(trap -p EXIT)" ] && trap '_dave_cleanup_tmp' EXIT
    if ! jq -s '.[0] * .[1]
                | walk(if type == "object"
                       then with_entries(select(.key | startswith("_comment") | not))
                       else . end)' "$CONFIG" "$PROJECT_CONFIG" > "$_EFFECTIVE_CONFIG"; then
      # A corrupt overlay must degrade to the global config, not to empty reads.
      rm -f "$_EFFECTIVE_CONFIG"
      _EFFECTIVE_CONFIG="$CONFIG"
    fi
  fi
  printf '%s\n' "$_EFFECTIVE_CONFIG"
}

config_get() { json_get "$(config_effective_file)" "$1" "${2:-}"; }

# Booleans need their own reader: jq's `//` yields the right-hand side for `false`
# as well as null, so `.x // true` can never return false. The session-start hook
# learned this the hard way; do not "simplify" this back into json_get.
config_bool() {
  local path="$1" dflt="$2"
  jq -r "if $path == null then \"$dflt\" else ($path | tostring) end" \
    "$(config_effective_file)" 2>/dev/null || printf '%s\n' "$dflt"
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

# ------------------------------------------------------------------- markdown

# One ## section of a markdown file, with HTML prompts stripped and surrounding
# blank lines trimmed. Lives here rather than in mission.sh because both the
# briefing pack and `brief` (the project instance's rules section) read sections.
_md_section() {
  local file="$1" heading="$2"
  [ -f "$file" ] || return 0
  # Fence-aware: an agent's return format is a fenced block whose *contents* are
  # markdown headings, and a naive scan ends the section at the first one.
  awk -v h="## $heading" '
    !f && $0 == h { f = 1; next }
    f {
      if ($0 ~ /^```/) { fence = !fence; print; next }
      if (!fence && $0 ~ /^## /) { f = 0; next }
      print
    }
  ' "$file" \
    | sed -e 's/<!--[^>]*-->//g' \
    | awk 'BEGIN{n=0} {lines[n++]=$0}
           END{ s=0; e=n-1;
                while (s < n && lines[s] ~ /^[[:space:]]*$/) s++;
                while (e >= s && lines[e] ~ /^[[:space:]]*$/) e--;
                for (i = s; i <= e; i++) print lines[i] }'
}

# ------------------------------------------------- project instance, resolved
#
# Resolved once at source time: a dave.sh invocation is one command in one cwd,
# so there is nothing to re-resolve. Sourced scripts that never touch a project
# still pay only the walk-up — which is a handful of stat calls.
# `|| exit 1` matters: die inside $( ) exits the subshell, and without it a bad
# DAVE_PROJECT_HOME would degrade to "no project" instead of the loud error.
PROJECT_HOME="$(project_home_resolve)" || exit 1
if [ -n "$PROJECT_HOME" ]; then
  PROJECT_CONFIG="$PROJECT_HOME/config.json"
  PROJECT_PARKING="$PROJECT_HOME/scratch/parking-lot.md"
  PROJECT_ROLES="$PROJECT_HOME/roles"
  PROJECT_BRIEF="$PROJECT_HOME/project.md"
else
  PROJECT_CONFIG="" PROJECT_PARKING="" PROJECT_ROLES="" PROJECT_BRIEF=""
fi

# Prime the merged config here, in the main shell: materializing it lazily from
# inside a command substitution would register the cleanup trap in a subshell
# that deletes the file the moment the substitution ends.
if [ -n "$PROJECT_HOME" ] && [ -f "$PROJECT_CONFIG" ] && [ -f "$CONFIG" ]; then
  config_effective_file >/dev/null
fi
