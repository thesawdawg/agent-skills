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
  # last_touched starts null deliberately. Registering a project is not working
  # on it, and stamping it here would make every newly registered project look
  # active — which is exactly the state the weekly sweep needs to contradict.
  jq -n --arg slug "$slug" --arg name "$name" --arg path "$path" --arg status "$status" \
        --arg goal "$goal" --arg cadence "$cadence" --arg added "$(today)" \
    '{slug:$slug, name:$name, path:$path, status:$status, goal:$goal, cadence:$cadence,
      refs:[], added:$added, last_touched:null}' > "$(_project_file "$slug")"
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
    "added: \(.added) · last touched: \(.last_touched // "(not yet)")"'

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

# ----------------------------------------------------------------- git scan

# The one signal that is always current. Boards are stale by design and Redmine
# needs an MCP; git is sitting right there, and it is how the weekly sweep knows
# a project has gone quiet without being told.
#
# Results are cached: the session-start hook must never pay for a walk across
# every registered repository, so it reads what is already known and stays quiet
# when nothing is.

_scan_days_since() {
  local iso="$1" at now
  [ -n "$iso" ] || { echo ""; return 0; }
  at="$(date -d "$iso" +%s 2>/dev/null)" || { echo ""; return 0; }
  now="$(date +%s)"
  echo $(( (now - at) / 86400 ))
}

# Open PR count, when the user has asked for it and the remote is actually
# GitHub. Every failure here is silent: a scan must not break because the network
# did, or because gh is logged out.
_scan_gh_prs() {
  local path="$1"
  [ "$(config_bool '.projects.use_gh' false)" = "true" ] || return 0
  command -v gh >/dev/null 2>&1 || return 0
  git -C "$path" remote get-url origin 2>/dev/null | grep -qi 'github\.com' || return 0
  local runner=""
  command -v timeout >/dev/null 2>&1 && runner="timeout 8"
  ( cd "$path" 2>/dev/null && $runner gh pr list --limit 30 --json number 2>/dev/null ) \
    | jq 'length' 2>/dev/null || true
}

# Local branches with no commit in 30 days. A count, not a list: the point is
# "this repository has accumulated loose ends", and naming eleven of them in a
# weekly sweep is how the sweep stops being read.
_scan_stale_branches() {
  local path="$1" cutoff
  git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || { echo 0; return 0; }
  cutoff="$(date -d '-30 day' +%s)"
  git -C "$path" --no-optional-locks for-each-ref --format='%(committerdate:unix)' refs/heads 2>/dev/null \
    | awk -v c="$cutoff" '$1 < c { n++ } END { print n+0 }' || echo 0
}

_scan_probe_all() {
  local include_archived="$1"
  local all; all="$(_projects_all)"
  local entries="{}" slug path status probe days prs stale_branches
  while IFS=$'\t' read -r slug path status; do
    [ -n "$slug" ] || continue
    [ "$include_archived" -eq 0 ] && [ "$status" = "archived" ] && continue
    probe="$(git_probe "$path")"
    days="$(_scan_days_since "$(printf '%s' "$probe" | jq -r '.last_commit // ""')")"
    prs="$(_scan_gh_prs "$path")"
    stale_branches="$(_scan_stale_branches "$path")"
    entries="$(jq -c --arg slug "$slug" --arg status "$status" \
      --argjson probe "$probe" \
      --argjson days "${days:-null}" --argjson prs "${prs:-null}" \
      --argjson stale "${stale_branches:-0}" \
      '.[$slug] = ($probe + {slug:$slug, status:$status, days_since_commit:$days,
                             open_prs:$prs, stale_branches:$stale})' \
      <<< "$entries")"
  done < <(printf '%s' "$all" | jq -r '.[] | "\(.slug)\t\(.path)\t\(.status)"')
  printf '%s\n' "$entries"
}

cmd_scan() {
  require_init
  need_jq
  local only="" as_json=0 fresh=0 include_archived=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json)  as_json=1; shift ;;
      --fresh) fresh=1; shift ;;
      --all)   include_archived=1; shift ;;
      -*) die "unknown flag: $1" ;;
      *) only="$(_project_norm "$1")"; shift ;;
    esac
  done

  local ttl gen age entries=""
  ttl="$(config_get '.projects.scan_ttl_seconds' 300)"
  if [ "$fresh" -eq 0 ] && [ -f "$SCAN_CACHE" ]; then
    gen="$(json_get "$SCAN_CACHE" '.generated')"
    if [ -n "$gen" ]; then
      age=$(( $(date +%s) - $(date -d "$gen" +%s 2>/dev/null || echo 0) ))
      [ "$age" -lt "$ttl" ] && entries="$(jq -c '.entries // {}' "$SCAN_CACHE")"
    fi
  fi
  if [ -z "$entries" ]; then
    entries="$(_scan_probe_all "$include_archived")"
    jq -n --arg ts "$(now_iso)" --argjson e "$entries" '{generated:$ts, entries:$e}' > "$SCAN_CACHE"
  fi

  [ -n "$only" ] && entries="$(printf '%s' "$entries" | jq -c --arg s "$only" \
    'with_entries(select(.key == $s))')"

  if [ "$as_json" -eq 1 ]; then printf '%s\n' "$entries"; return 0; fi
  printf '%s' "$entries" | jq -r '
    to_entries | sort_by(.key) |
    if length == 0 then "(nothing to scan — try: project add <path>)" else
      map(.value |
        if .exists == false then "\(.slug)\tPATH GONE\t\(.path)"
        elif .repo == false then "\(.slug)\t(not a repo)\t\(.path)"
        else "\(.slug)\t\(.branch)\t" +
             (if .dirty > 0 or .untracked > 0 then "\(.dirty) dirty, \(.untracked) untracked" else "clean" end)
             + "\t" +
             (if .days_since_commit == null then "no commits"
              elif .days_since_commit == 0 then "committed today"
              elif .days_since_commit == 1 then "committed yesterday"
              else "\(.days_since_commit)d since commit" end)
             + (if .ahead > 0 then "\t\(.ahead) unpushed" else "\t" end)
             + (if .open_prs != null and .open_prs > 0 then "\t\(.open_prs) open PRs" else "" end)
        end
      ) | join("\n")
    end' | { column -t -s "$(printf '\t')" 2>/dev/null || cat; }
}

# What the hook shows: known-fresh git state, or nothing at all. Never probes.
_scan_cached_line() {
  local slug="$1" ttl gen age
  [ -f "$SCAN_CACHE" ] || return 0
  ttl="$(config_get '.projects.scan_ttl_seconds' 300)"
  gen="$(json_get "$SCAN_CACHE" '.generated')"
  [ -n "$gen" ] || return 0
  age=$(( $(date +%s) - $(date -d "$gen" +%s 2>/dev/null || echo 0) ))
  [ "$age" -lt "$ttl" ] || return 0
  jq -r --arg s "$slug" '
    .entries[$s] // empty
    | select(.repo == true)
    | "Git: \(.branch)"
      + (if .dirty > 0 or .untracked > 0 then ", \(.dirty) dirty/\(.untracked) untracked" else ", clean" end)
      + (if .days_since_commit == null then ""
         elif .days_since_commit == 0 then ", last commit today"
         elif .days_since_commit == 1 then ", last commit yesterday"
         else ", last commit \(.days_since_commit)d ago" end)
      + (if .ahead > 0 then ", \(.ahead) unpushed" else "" end)' \
    "$SCAN_CACHE" 2>/dev/null || true
}

# ------------------------------------------------------------------ dossier

# A cached codebase map, per project. The delegation contract says Cartographer
# "runs once per unfamiliar repo, not per ticket" and that its brief is worth
# keeping — with no store to keep it in. This is the store.
#
# Per project rather than per mission, because a map describes a repository and
# outlives any single mission against it.

_dossier_path() { printf '%s/%s/dossier.md\n' "$PROJECTS" "$1"; }

_dossier_set() {
  local slug="${1:-}"
  if [ -n "$slug" ]; then slug="$(_project_norm "$slug")"; else slug="$(_project_resolve)"; fi
  [ -n "$slug" ] || die "no project given, and this directory is not in a registered project"
  _project_require "$slug"
  local path head
  path="$(_dossier_path "$slug")"
  cat > "$path"
  # Stamped with the commit it describes, so staleness is measurable rather than
  # a guess about how long ago someone ran Cartographer.
  head="$(git -C "$(json_get "$(_project_file "$slug")" '.path')" rev-parse HEAD 2>/dev/null || echo "")"
  json_edit "$(_project_file "$slug")" --arg h "$head" --arg ts "$(now_iso)" \
    '.dossier = {head:$h, at:$ts}'
  echo "$path"
}

# A human phrase describing how far the repo has moved since the map was made,
# or nothing at all when there is no dossier to judge.
_dossier_staleness() {
  local slug="$1" pf head path n threshold
  pf="$(_project_file "$slug")"
  [ -f "$pf" ] || return 0
  [ -f "$(_dossier_path "$slug")" ] || return 0
  head="$(json_get "$pf" '.dossier.head')"
  path="$(json_get "$pf" '.path')"
  if [ -z "$head" ]; then echo "age unknown — it was not stamped with a commit"; return 0; fi
  n="$(git -C "$path" rev-list --count "$head..HEAD" 2>/dev/null || echo "")"
  if [ -z "$n" ]; then echo "age unknown — that commit is no longer in this repository"; return 0; fi
  threshold="$(config_get '.projects.dossier_stale_commits' 50)"
  if [ "$n" -ge "$threshold" ]; then
    echo "STALE — $n commits since it was made, threshold $threshold"
  elif [ "$n" -eq 0 ]; then
    echo "current — the repository has not moved since"
  else
    echo "current — $n commit(s) since it was made"
  fi
}

_dossier_get() {
  local slug="${1:-}"
  if [ -n "$slug" ]; then slug="$(_project_norm "$slug")"; else slug="$(_project_resolve)"; fi
  [ -n "$slug" ] || die "no project given, and this directory is not in a registered project"
  _project_require "$slug"
  local path; path="$(_dossier_path "$slug")"
  [ -f "$path" ] || { echo "(no dossier for $slug — have Cartographer map it, then: dossier set $slug < map.md)"; return 0; }
  cat "$path"
  echo
  echo "---"
  echo "dossier: $(_dossier_staleness "$slug")"
}

cmd_dossier() {
  require_init
  need_jq
  local sub="${1:-get}"
  shift || true
  case "$sub" in
    set) _dossier_set "$@" ;;
    get) _dossier_get "$@" ;;
    *) die "unknown dossier subcommand: $sub (set|get)" ;;
  esac
}
