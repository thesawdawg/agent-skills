# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# sync.sh — the vault's transport layer.
#
# Transport is Syncthing, not git. dave.sh never pushes and never pulls: it
# writes journals and views, Syncthing moves the files between devices, and
# _views_ensure folds whatever arrived into the views on the next command.
# This file is therefore the *setup and inspection* surface for that folder —
# plus the resolver for the conflict copies Syncthing leaves behind.
#
# Sourced by dave.sh.

# Is the local config opting in to sync bookkeeping? Brief no longer pulls, so
# this only gates whether `sync status` reports as "enabled" vs "not set up".
sync_ready() {
  [ "$(config_bool '.sync.enabled' false)" = "true" ]
}

cmd_sync() {
  require_init
  need_jq
  local sub="${1:-status}"
  shift || true
  case "$sub" in
    setup)     _sync_setup "$@" ;;
    status)    _sync_status "$@" ;;
    conflicts) _sync_conflicts "$@" ;;
    rebuild)   views_rebuild; echo "rebuilt: $VIEWS" ;;
    *) die "unknown sync subcommand: $sub (setup|status|conflicts|rebuild)" ;;
  esac
}

# --------------------------------------------------------------------- setup

# Syncthing's REST API is optional: when an api key and url are configured it
# can answer "is this folder actually registered" without leaving the shell.
# Never required, always bounded by --max-time.
_sync_api_key() {
  if [ -n "${SYNCTHING_API_KEY:-}" ]; then
    printf '%s\n' "$SYNCTHING_API_KEY"
  else
    config_get '.sync.syncthing_api_key'
  fi
}

_sync_api_url() {
  config_get '.sync.syncthing_url' 'http://127.0.0.1:8384'
}

# 0 = Syncthing answered and a folder whose path is $DAVE_HOME exists;
# 1 = answered but no such folder; 2 = unreachable / not configured.
_sync_folder_state() {
  local key url
  key="$(_sync_api_key)"; url="$(_sync_api_url)"
  [ -n "$key" ] || return 2
  local body
  body="$(curl -sf --max-time 5 -H "X-API-Key: $key" \
    "$url/rest/config/folders" 2>/dev/null)" || return 2
  printf '%s' "$body" | jq -e --arg p "$DAVE_HOME" \
    'any(.[]; .path == $p)' >/dev/null 2>&1 \
    && return 0 || return 1
}

_sync_setup() {
  local vault=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --vault) vault="${2:-}"; shift 2 ;;
      *) die "usage: sync setup [--vault PATH]" ;;
    esac
  done
  if [ -n "$vault" ]; then
    local canon
    canon="$(cd "$vault" 2>/dev/null && pwd -P || printf '%s' "$vault")"
    if [ "$canon" != "$DAVE_HOME" ]; then
      die "sync setup --vault: $canon is not this DAVE_HOME ($DAVE_HOME) — point DAVE_HOME at the vault instead: export DAVE_HOME=$canon (nothing was moved)"
    fi
  fi

  # Syncthing's own ignore file keeps device-local state (.local/) and editor
  # noise out of the folder it shares.
  cat > "$DAVE_HOME/.stignore" <<'STIGNORE'
.local/
.obsidian/workspace*
*.tmp
*.swp
.DS_Store
STIGNORE

  device_id >/dev/null
  # An empty .obsidian/app.json is enough for Obsidian to treat the folder as
  # a vault; only written when no Obsidian state exists at all.
  if [ ! -d "$DAVE_HOME/.obsidian" ]; then
    mkdir -p "$DAVE_HOME/.obsidian"
    printf '{}\n' > "$DAVE_HOME/.obsidian/app.json"
  fi

  [ -f "$LOCAL_CONFIG" ] || printf '{}\n' > "$LOCAL_CONFIG"
  json_edit "$LOCAL_CONFIG" '.sync.enabled = true'

  cat <<EOF
syncthing checklist (same on both devices):
  1. add $DAVE_HOME as a Syncthing folder
  2. use the same Folder ID on both devices
  3. enable Staggered File Versioning (conflict copies land as
     *.sync-conflict-* and 'sync conflicts' resolves them)
  4. ignore patterns are already in $DAVE_HOME/.stignore
EOF

  local state=0
  _sync_folder_state || state=$?
  case $state in
    0) echo "syncthing: folder is registered for this path" ;;
    1) echo "syncthing: reachable, but no folder covers $DAVE_HOME yet" ;;
    2) echo "syncthing: not checked (no api key configured, or unreachable)" ;;
  esac
  echo "sync: enabled in .local/config.json"
}

# -------------------------------------------------------------------- status

# One JSON object per journal file: {file, dev, events, last_ts}. Files are
# named <device>.jsonl so the id is the basename.
_sync_journals() {
  local f dev n last
  printf '['
  local first=1
  for f in "$JOURNAL_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    dev="$(basename "$f" .jsonl)"
    n="$(jsonl_stream "$f" | wc -l | tr -d ' ')"
    last="$(jsonl_stream "$f" | jq -r '.ts' 2>/dev/null | sort | tail -1)"
    [ "$first" -eq 0 ] && printf ','
    first=0
    jq -nc --arg dev "$dev" --arg file "$(basename "$f")" \
      --argjson events "${n:-0}" --arg last "${last:-}" \
      '{dev:$dev, file:$file, events:$events,
        last_ts:(if $last == "" then null else $last end)}'
  done
  printf ']\n'
}

# Conflict copies Syncthing left anywhere in the vault except device-local
# state. Prints "<conflict-path>\t<original-path>" per line; the original is
# derived by stripping the `.sync-conflict-<stamp>` infix.
_sync_conflict_pairs() {
  find "$DAVE_HOME" -name '*.sync-conflict-*' -not -path "$LOCAL/*" \
    -type f 2>/dev/null | while IFS= read -r f; do
      # Syncthing names copies <name>.sync-conflict-YYYYMMDD-HHMMSS[-<tag>].<ext>;
      # strip the whole infix, including the trailing device tag, to recover
      # the original's name.
      printf '%s\t%s\n' "$f" "$(printf '%s' "$f" \
        | sed 's/\.sync-conflict-[0-9]\{8\}-[0-9]\{6\}\(-[^.]*\)\?//')"
    done
}

_sync_status() {
  local as_json=0
  [ "${1:-}" = "--json" ] && as_json=1
  local journals conflicts fresh syncthing
  journals="$(_sync_journals)"
  conflicts="$(_sync_conflict_pairs | wc -l | tr -d ' ')"
  fresh="stale"
  local stored=""
  [ -f "$VIEWS/.fingerprint" ] && stored="$(cat "$VIEWS/.fingerprint")"
  [ "$(_journal_fingerprint)" = "$stored" ] && fresh="fresh"
  local state=0
  _sync_folder_state || state=$?
  case $state in
    0) syncthing="folder registered" ;;
    1) syncthing="reachable, folder not registered" ;;
    2) syncthing="not checked" ;;
  esac

  if [ "$as_json" -eq 1 ]; then
    jq -n --argjson j "$journals" --argjson c "${conflicts:-0}" \
      --arg fresh "$fresh" --arg st "$syncthing" \
      --argjson enabled "$(sync_ready && echo true || echo false)" \
      --arg home "$DAVE_HOME" \
      '{home:$home, enabled:$enabled, journals:$j,
        views:$fresh, conflicts:$c, syncthing:$st}'
    return 0
  fi

  printf 'device: %s\n' "$(device_id)"
  printf 'sync:   %s\n' "$(sync_ready && echo enabled || echo 'not enabled — run: sync setup')"
  printf 'views:  %s\n' "$fresh"
  printf '%s' "$journals" | jq -r '.[] | "journal: \(.dev)  \(.events) events, last \(.last_ts // "—")"'
  printf 'conflict copies: %s\n' "$conflicts"
  printf 'syncthing: %s\n' "$syncthing"
}

# ----------------------------------------------------------------- conflicts

# A conflict file must live under $DAVE_HOME (outside .local), match the
# *.sync-conflict-* shape, and shadow an existing original. Resolution is the
# only place a path arrives from outside (the dashboard), so it is checked
# here once.
_sync_conflict_orig() {
  local f="$1"
  case "$f" in /*) ;; *) f="$DAVE_HOME/$f" ;; esac
  case "$f" in
    "$LOCAL"/*) return 1 ;;             # device-local is never a conflict copy
    "$DAVE_HOME"/*) ;;                  # must live inside the vault
    *) return 1 ;;
  esac
  case "$(basename "$f")" in *.sync-conflict-*) ;; *) return 1 ;; esac
  local orig
  orig="$(printf '%s' "$f" \
    | sed 's/\.sync-conflict-[0-9]\{8\}-[0-9]\{6\}\(-[^.]*\)\?//')"
  [ "$orig" != "$f" ] || return 1
  printf '%s\t%s\n' "$f" "$orig"
}

_sync_conflicts() {
  case "${1:-}" in
    "") _sync_conflicts_list 0 ;;
    --json) _sync_conflicts_list 1 ;;
    resolve) shift; _sync_conflicts_resolve "$@" ;;
    *) die "usage: sync conflicts [--json] | sync conflicts resolve <file> keep-local|keep-remote|merge" ;;
  esac
}

_sync_conflicts_list() {
  local as_json="$1"
  if [ "$as_json" -eq 1 ]; then
    _sync_conflict_pairs | jq -R 'split("\t") | {conflict: .[0], original: .[1]}' \
      | jq -s .
    return 0
  fi
  local found=0
  while IFS=$'\t' read -r f orig; do
    [ -n "$f" ] || continue
    printf '%s\n  shadows %s\n' "$f" "$orig"
    found=1
  done < <(_sync_conflict_pairs)
  [ "$found" -eq 0 ] && echo "(no sync conflicts)"
  return 0
}

# keep-local deletes the copy; keep-remote replaces the original with it.
# merge cannot be automatic: Syncthing gives two divergent files with no
# common ancestor, so it prints the diff and leaves both files alone.
_sync_conflicts_resolve() {
  [ $# -ge 2 ] || die "usage: sync conflicts resolve <file> keep-local|keep-remote|merge"
  local file="$1" action="$2" pair f orig
  pair="$(_sync_conflict_orig "$file")" \
    || die "resolve: $file is not a sync-conflict copy under $DAVE_HOME"
  f="${pair%%$'\t'*}"; orig="${pair#*$'\t'}"
  [ -f "$f" ] || die "resolve: no such file: $f"
  case "$action" in
    keep-local)
      rm -f "$f"
      echo "kept local — removed $f"
      ;;
    keep-remote)
      [ -f "$orig" ] || die "resolve: original is gone: $orig"
      mv "$f" "$orig"
      echo "kept remote — $orig now holds the conflict copy's content"
      ;;
    merge)
      [ -f "$orig" ] || die "resolve: original is gone: $orig"
      echo "no common ancestor — diffing original (left) against the conflict copy (right):"
      diff -u "$orig" "$f" || true
      echo "edit $orig by hand, then: sync conflicts resolve $f keep-local"
      ;;
    *) die "resolve: action must be keep-local, keep-remote, or merge" ;;
  esac
}
