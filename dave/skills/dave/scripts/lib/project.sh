# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# project.sh — the project layer: registration, resolution, and per-project state.
#
# A project is a durable container the ranked list has no room for: a directory,
# a goal, a cadence, and the refs that serve it. `priorities.md` stays the single
# ranked list and its format is untouched — projects reference refs, never the
# other way round, so nothing here has to parse the user's document.
#
# Sourced by dave.sh.

PROJECT_STATUSES="active paused maintenance archived"
PROJECT_CADENCES="daily weekly monthly dormant"

_project_dir()  { printf '%s/%s\n' "$PROJECTS" "$1"; }
_project_file() { printf '%s/%s/project.json\n' "$PROJECTS" "$1"; }

# Accepts the slug or the name it was derived from. slugify is idempotent, so
# `dnd_5e_api` and `dnd-5e-api` both find the same project — the user should not
# have to remember which transformation happened at registration.
_project_norm() { slugify "$1"; }

_project_require() {
  local slug="$1"
  [ -f "$(_project_file "$slug")" ] || die "no such project: $slug (try: project list)"
}

# Every registered project as one JSON array. The find guard matters: a bare glob
# with no matches expands to a literal path and takes jq down with it.
_projects_all() {
  [ -d "$PROJECTS" ] || { printf '[]\n'; return 0; }
  local files=() f
  while IFS= read -r -d '' f; do files+=("$f"); done \
    < <(find "$PROJECTS" -mindepth 2 -maxdepth 2 -name project.json -print0 2>/dev/null)
  [ "${#files[@]}" -gt 0 ] || { printf '[]\n'; return 0; }
  jq -s 'map(select(type == "object"))' "${files[@]}" 2>/dev/null || printf '[]\n'
}

_canonical() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

cmd_project() {
  require_init
  need_jq
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    add)      _project_add "$@" ;;
    list)     _project_list "$@" ;;
    show)     _project_show "$@" ;;
    status)   _project_status "$@" ;;
    link)     _project_link "$@" ;;
    unlink)   _project_unlink "$@" ;;
    of)       _project_of "$@" ;;
    resolve)  _project_resolve "$@" ;;
    touch)    _project_touch "$@" ;;
    *) die "unknown project subcommand: $sub (add|list|show|status|link|unlink|of|resolve|touch)" ;;
  esac
}

_project_add() {
  [ $# -ge 1 ] || die "usage: project add <path> [--name N] [--slug S] [--cadence C] [--goal TEXT] [--status S]"
  local path="$1"; shift
  [ -d "$path" ] || die "not a directory: $path"
  path="$(_canonical "$path")"

  local name="" slug="" cadence="weekly" goal="" status="active"
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)    name="${2:-}"; shift 2 ;;
      --slug)    slug="${2:-}"; shift 2 ;;
      --cadence) cadence="${2:-}"; shift 2 ;;
      --goal)    goal="${2:-}"; shift 2 ;;
      --status)  status="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  [ -n "$slug" ] || slug="$(basename "$path")"
  slug="$(slugify "$slug")"
  [ -n "$name" ] || name="$(basename "$path")"
  case " $PROJECT_CADENCES " in *" $cadence "*) ;; *) die "cadence must be one of: $PROJECT_CADENCES" ;; esac
  case " $PROJECT_STATUSES " in *" $status "*) ;; *) die "status must be one of: $PROJECT_STATUSES" ;; esac

  [ -f "$(_project_file "$slug")" ] && die "project already registered: $slug"
  local clash
  clash="$(_projects_all | jq -r --arg p "$path" '.[] | select(.path == $p) | .slug' | head -1)"
  [ -n "$clash" ] && die "that path is already registered as: $clash"

  mkdir -p "$(_project_dir "$slug")"
  jq -n --arg slug "$slug" --arg name "$name" --arg path "$path" --arg status "$status" \
        --arg goal "$goal" --arg cadence "$cadence" --arg added "$(today)" --arg ts "$(now_iso)" \
    '{slug:$slug, name:$name, path:$path, status:$status, goal:$goal, cadence:$cadence,
      refs:[], added:$added, last_touched:$ts}' > "$(_project_file "$slug")"
  echo "registered: $slug — $path ($status, $cadence)"
}

_project_list() {
  local want_status="" as_json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --status) want_status="${2:-}"; shift 2 ;;
      --json)   as_json=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  local all; all="$(_projects_all)"
  [ -n "$want_status" ] && all="$(printf '%s' "$all" | jq --arg s "$want_status" 'map(select(.status == $s))')"

  if [ "$as_json" -eq 1 ]; then printf '%s\n' "$all"; return 0; fi
  if [ "$(printf '%s' "$all" | jq 'length')" -eq 0 ]; then
    echo "(no projects registered — try: project add <path>)"
    _project_candidates
    return 0
  fi
  printf '%s' "$all" | jq -r '
    sort_by(.status, .slug)[]
    | "\(.slug)\t\(.status)\t\(.cadence)\t\(.refs | length) refs\t\(.path)"' \
    | column -t -s "$(printf '\t')" 2>/dev/null \
    || printf '%s' "$all" | jq -r 'sort_by(.slug)[] | "\(.slug)  \(.status)  \(.path)"'
  _project_candidates
}

# Directories under projects.root that look like projects and are not registered.
# Suggested, never added: registration stays a decision the user makes.
_project_candidates() {
  local root; root="$(config_get '.projects.root')"
  [ -n "$root" ] || return 0
  [ "$(config_bool '.projects.autodiscover' false)" = "true" ] || return 0
  [ -d "$root" ] || return 0
  local all d shown=0
  all="$(_projects_all)"
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    d="$(_canonical "$d")"
    printf '%s' "$all" | jq -e --arg p "$d" 'any(.[]; .path == $p)' >/dev/null 2>&1 && continue
    [ "$shown" -eq 0 ] && { echo; echo "unregistered under $root:"; shown=1; }
    printf '  %s\n' "$d"
  done
}

_project_show() {
  local slug="${1:-}"
  if [ -n "$slug" ]; then slug="$(_project_norm "$slug")"; else slug="$(_project_resolve)"; fi
  [ -n "$slug" ] || die "no project given, and this directory is not in a registered project"
  _project_require "$slug"
  local p; p="$(cat "$(_project_file "$slug")")"

  printf '%s' "$p" | jq -r '
    "=== PROJECT ===",
    "slug: \(.slug)",
    "name: \(.name)",
    "path: \(.path)",
    "status: \(.status) · cadence: \(.cadence)",
    "goal: \(if (.goal // "") == "" then "(none set)" else .goal end)",
    "added: \(.added) · last touched: \(.last_touched)"'

  echo
  echo "=== REFS ==="
  local refs; refs="$(printf '%s' "$p" | jq -r '.refs[]?' )"
  if [ -z "$refs" ]; then
    echo "(no refs linked — try: project link $slug RM-1234)"
  else
    local r
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      if grep -qF -- "$r" "$PRIORITIES" 2>/dev/null; then
        printf '  %s\n' "$r"
      else
        # Worth surfacing rather than hiding: the two records disagree, and that
        # is usually the ref having been closed out of the list.
        printf '  %s   (not in priorities.md)\n' "$r"
      fi
    done <<< "$refs"
  fi

  echo
  echo "=== GIT ==="
  local path probe; path="$(printf '%s' "$p" | jq -r .path)"
  probe="$(git_probe "$path")"
  printf '%s' "$probe" | jq -r '
    if .exists == false then "(path is gone: \(.path))"
    elif .repo == false then "(not a git repository)"
    else "branch: \(.branch) · dirty: \(.dirty) · untracked: \(.untracked) · ahead \(.ahead) / behind \(.behind) (no fetch)",
         "last commit: \(.last_commit // "(none)") — \(.last_subject // "")"
    end'

  # missions.json arrives with the assignment ledger; absent, this stays quiet.
  if [ -f "$MISSIONS_JSON" ]; then
    local missions
    missions="$(jq -r --arg s "$slug" 'to_entries | map(select(.value.project == $s and .value.status == "open")) | .[].key' "$MISSIONS_JSON" 2>/dev/null || true)"
    if [ -n "$missions" ]; then
      echo
      echo "=== OPEN MISSIONS ==="
      printf '%s\n' "$missions" | sed 's/^/  /'
    fi
  fi
}

_project_status() {
  [ $# -ge 2 ] || die "usage: project status <slug> <$(echo "$PROJECT_STATUSES" | tr ' ' '|')>"
  local slug status; slug="$(_project_norm "$1")"; status="$2"
  _project_require "$slug"
  case " $PROJECT_STATUSES " in *" $status "*) ;; *) die "status must be one of: $PROJECT_STATUSES" ;; esac
  json_edit "$(_project_file "$slug")" --arg s "$status" '.status = $s'
  echo "$slug: $status"
}

_project_link() {
  [ $# -ge 2 ] || die "usage: project link <slug> <ref>"
  local slug ref; slug="$(_project_norm "$1")"; ref="$2"
  _project_require "$slug"
  local owner
  owner="$(_project_of_slug "$ref")"
  [ -n "$owner" ] && [ "$owner" != "$slug" ] && die "$ref is already linked to $owner (unlink it first)"
  json_edit "$(_project_file "$slug")" --arg r "$ref" '.refs = ((.refs // []) + [$r] | unique)'
  echo "$slug: linked $ref"
}

_project_unlink() {
  [ $# -ge 2 ] || die "usage: project unlink <slug> <ref>"
  local slug ref; slug="$(_project_norm "$1")"; ref="$2"
  _project_require "$slug"
  json_edit "$(_project_file "$slug")" --arg r "$ref" '.refs = ((.refs // []) - [$r])'
  echo "$slug: unlinked $ref"
}

_project_of_slug() {
  _projects_all | jq -r --arg r "$1" '.[] | select(any(.refs[]?; . == $r)) | .slug' | head -1
}

_project_of() {
  [ $# -ge 1 ] || die "usage: project of <ref>"
  local slug; slug="$(_project_of_slug "$1")"
  [ -n "$slug" ] && printf '%s\n' "$slug"
  return 0
}

# cwd -> slug. Walks up to the filesystem root so a session started deep inside a
# project still resolves. Silent and exit 0 when nothing matches: the hook and
# brief both call this in directories that have nothing to do with D.A.V.E.
_project_resolve() {
  local start="${1:-$PWD}" all dir slug
  start="$(_canonical "$start")"
  all="$(_projects_all)"
  [ "$all" = "[]" ] && return 0
  dir="$start"
  while : ; do
    slug="$(printf '%s' "$all" | jq -r --arg d "$dir" '.[] | select(.path == $d) | .slug' | head -1)"
    if [ -n "$slug" ]; then printf '%s\n' "$slug"; return 0; fi
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  return 0
}

_project_touch() {
  local slug="${1:-}"
  if [ -n "$slug" ]; then slug="$(_project_norm "$slug")"; else slug="$(_project_resolve)"; fi
  [ -n "$slug" ] || die "no project given, and this directory is not in a registered project"
  _project_require "$slug"
  json_edit "$(_project_file "$slug")" --arg ts "$(now_iso)" '.last_touched = $ts'
  echo "$slug: touched"
}
