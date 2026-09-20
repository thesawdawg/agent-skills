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
  need_jq
  local sub="${1:-status}"
  shift || true
  case "$sub" in
    status|conflicts|journal-conflicts)
      [ -f "$CONFIG" ] || exit 3
      # Diagnostics and recovery must survive a broken journal/reducer.
      _views_ensure || true ;;
    *) require_init ;;
  esac
  case "$sub" in
    setup)     _sync_setup "$@" ;;
    status)    _sync_status "$@" ;;
    conflicts) _sync_conflicts "$@" ;;
    journal-conflicts) _journal_recover "$@" ;;
    rebuild)   views_rebuild; echo "rebuilt: $VIEWS" ;;
    *) die "unknown sync subcommand: $sub (setup|status|conflicts|journal-conflicts|rebuild)" ;;
  esac
}

# --------------------------------------------------------------------- setup

# The managed rules must be first: Syncthing evaluates ignore patterns in
# order, so a user's later negation must not expose device-local state or a
# migration archive. Everything outside this block belongs to the user and is
# copied byte-for-byte into the replacement file.
_SYNC_IGNORE_BEGIN='// BEGIN DAVE MANAGED IGNORE RULES'
_SYNC_IGNORE_END='// END DAVE MANAGED IGNORE RULES'

_sync_prepare_ignores() {
  local file="$DAVE_HOME/.stignore" tmp mode custom_tmp temp_dir escape_line=""
  [ -d "$DAVE_HOME" ] || mkdir -p "$DAVE_HOME" || {
    echo "sync: cannot create vault directory for .stignore" >&2
    return 1
  }
  if [ -e "$file" ] && [ ! -f "$file" ]; then
    echo "sync: .stignore exists but is not a regular file" >&2
    return 1
  fi

  # Count exact marker lines before creating a replacement. Incomplete or
  # duplicated ownership markers are ambiguous; refusing here leaves the
  # user's file untouched instead of silently moving their rules.
  if [ -f "$file" ]; then
    if ! awk -v begin="$_SYNC_IGNORE_BEGIN" -v end="$_SYNC_IGNORE_END" '
      $0 == begin { begins++; invalid=(depth != 0); depth++; next }
      $0 == end { ends++; invalid=(depth != 1); depth--; next }
      END {
        if (invalid || begins > 1 || ends > 1 || depth != 0) exit 1
      }
    ' "$file" >/dev/null 2>&1; then
      echo "sync: refusing malformed managed markers in $file" >&2
      return 1
    fi
  fi

  # Syncthing treats #escape=... as a file directive only on line one. Keep
  # that optional header ahead of our managed block; moving it below a pattern
  # would change how every subsequent pattern is parsed.
  if [ -f "$file" ]; then
    escape_line="$(head -n 1 "$file")"
    case "$escape_line" in
      '#escape='*) ;;
      *) escape_line="" ;;
    esac
  fi

  # Extracting custom content into a sibling temporary file lets every read,
  # parse, and write complete before the final rename. The original remains in
  # place on any error, including a malformed source or a failed chmod.
  temp_dir="$LOCAL"
  [ -d "$temp_dir" ] || temp_dir="$DAVE_HOME"
  custom_tmp="$(mktemp "$temp_dir/.stignore.custom.XXXXXX")" || {
    echo "sync: cannot create .stignore temporary file" >&2
    return 1
  }
  if [ -f "$file" ]; then
    if ! awk -v begin="$_SYNC_IGNORE_BEGIN" -v end="$_SYNC_IGNORE_END" '
      NR == 1 && $0 ~ /^#escape=/ { next }
      $0 == begin { inside=1; next }
      $0 == end { inside=0; next }
      !inside { print }
    ' "$file" > "$custom_tmp"; then
      rm -f "$custom_tmp"
      echo "sync: cannot read $file" >&2
      return 1
    fi
  fi

  tmp="$(mktemp "$temp_dir/.stignore.XXXXXX")" || {
    rm -f "$custom_tmp"
    echo "sync: cannot create atomic .stignore temporary file" >&2
    return 1
  }
  if ! {
    [ -z "$escape_line" ] || printf '%s\n' "$escape_line"
    printf '%s\n' \
      "$_SYNC_IGNORE_BEGIN" \
      '/.local' \
      '/.migrated-*' \
      '/.obsidian/workspace*' \
      '*.tmp' \
      '*.swp' \
      '.DS_Store' \
      "$_SYNC_IGNORE_END"
    if [ -s "$custom_tmp" ]; then
      cat "$custom_tmp"
    fi
  } > "$tmp"; then
    rm -f "$custom_tmp" "$tmp"
    echo "sync: cannot compose $file" >&2
    return 1
  fi
  rm -f "$custom_tmp"

  # mktemp defaults to mode 0600. Existing ignore files may intentionally be
  # group/world readable, so carry their exact permission bits across the
  # atomic replacement.
  if [ -f "$file" ]; then
    mode="$(stat -c '%a' "$file" 2>/dev/null || true)"
    if [ -n "$mode" ] && ! chmod "$mode" "$tmp"; then
      rm -f "$tmp"
      echo "sync: cannot preserve .stignore permissions" >&2
      return 1
    fi
  fi
  if ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    echo "sync: cannot install $file" >&2
    return 1
  fi
}

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

# Every REST call goes through here: api-key header, bounded, silent.
_sync_st_get() { # <key> <base-url> <path>
  curl -sf --max-time 5 -H "X-API-Key: $1" "$2$3" 2>/dev/null
}

# The daemon's own device id — the value a peer needs to pair with us.
_sync_st_myid() { # <key> <base-url> → device id, or empty when unreachable
  local body
  body="$(_sync_st_get "$1" "$2" /rest/system/status)" || return 0
  printf '%s' "$body" | jq -r '.myID // empty' 2>/dev/null
}

# 0 = Syncthing answered and a folder whose path is $DAVE_HOME exists;
# 1 = answered but no such folder; 2 = unreachable / not configured.
# Credentials may be passed in (guided setup just discovered them) or fall back
# to the configured pair.
_sync_folder_state() {
  local key="${1:-$(_sync_api_key)}" url="${2:-$(_sync_api_url)}"
  [ -n "$key" ] || return 2
  local body
  body="$(_sync_st_get "$key" "$url" /rest/config/folders)" || return 2
  printf '%s' "$body" | jq -e --arg p "$DAVE_HOME" \
    'any(.[]; .path == $p)' >/dev/null 2>&1 \
    && return 0 || return 1
}

# The folder object covering $DAVE_HOME, empty when absent — lets setup inspect
# an already-registered folder (e.g. whether versioning is on).
_sync_folder_entry() { # <key> <base-url>
  local body
  body="$(_sync_st_get "$1" "$2" /rest/config/folders)" || return 0
  printf '%s' "$body" | jq -c --arg p "$DAVE_HOME" \
    'first(.[] | select(.path == $p)) // empty' 2>/dev/null
}

# The folder id is fixed on purpose: "same Folder ID on both devices" is what
# makes two Syncthing folders one folder, and a constant means the guided
# registration produces it identically on every device — no string to copy.
SYNC_FOLDER_ID="dave-vault"

_sync_setup() {
  local vault="" auto=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --vault) vault="${2:-}"; shift 2 ;;
      --auto)  auto=1; shift ;;
      *) die "usage: sync setup [--vault PATH] [--auto]" ;;
    esac
  done
  if [ -n "$vault" ]; then
    local canon
    canon="$(cd "$vault" 2>/dev/null && pwd -P || printf '%s' "$vault")"
    if [ "$canon" != "$DAVE_HOME" ]; then
      die "sync setup --vault: $canon is not this DAVE_HOME ($DAVE_HOME) — point DAVE_HOME at the vault instead: export DAVE_HOME=$canon (nothing was moved)"
    fi
  fi

  # Prepare local protection before touching config or asking Syncthing to
  # register/share this vault. A malformed managed block must stop setup.
  _sync_prepare_ignores || die "sync setup: could not prepare .stignore"

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
syncthing checklist (same on both devices — guided steps below can do it):
  1. add $DAVE_HOME as a Syncthing folder
  2. use the same Folder ID on both devices ('$SYNC_FOLDER_ID' when setup
     registers it for you)
  3. enable Staggered File Versioning (conflict copies land as
     *.sync-conflict-* and 'sync conflicts' resolves them)
  4. ignore patterns are already in $DAVE_HOME/.stignore
EOF

  _sync_guided "$auto"
  echo "sync: enabled in .local/config.json"
}

# ------------------------------------------------------------ guided setup
#
# The guided half of `sync setup`: find the daemon, borrow its api key from
# config.xml, and offer to register the vault folder over the REST API. Every
# step degrades to printed instructions — nothing here is required for sync to
# work, it just saves the user a trip to the GUI.

_sync_install_hint() {
  cat <<'EOF'
syncthing is not installed (or not on PATH). on linux:
  debian/ubuntu:  sudo apt install syncthing     # newer builds: apt.syncthing.net
  fedora:         sudo dnf install syncthing
  arch:           sudo pacman -S syncthing
then keep it running as a user service:
  systemctl --user enable --now syncthing
wsl2 without systemd: `nohup syncthing &` or any supervisor — the gui lands on
http://127.0.0.1:8384 either way. re-run `dave.sh sync setup` once it is up.
EOF
}

# Where the daemon's config.xml lives. SYNCTHING_CONFIG may point at the file
# for non-standard homes (and tests); otherwise probe the platform defaults —
# XDG first, then the newer ~/.local/state home.
_sync_st_config_xml() {
  local c="${SYNCTHING_CONFIG:-}"
  if [ -n "$c" ]; then
    [ -f "$c" ] && printf '%s\n' "$c"
    return 0
  fi
  for c in "${XDG_CONFIG_HOME:-$HOME/.config}/syncthing/config.xml" \
           "$HOME/.local/state/syncthing/config.xml"; do
    [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
}

# Prints "<apikey>\t<gui-url>" scraped from config.xml. <address> also appears
# inside <device> blocks, so only the <gui>…</gui> range is read. A wildcard
# listen address is folded back to loopback — the api is only probed locally.
_sync_st_credentials() {
  local gui key addr scheme
  gui="$(sed -n '/<gui[ >]/,/<\/gui>/p' "$1")"
  key="$(printf '%s\n' "$gui" | sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' | head -1)"
  addr="$(printf '%s\n' "$gui" | sed -n 's:.*<address>\(.*\)</address>.*:\1:p' | head -1)"
  [ -n "$key" ] && [ -n "$addr" ] || return 1
  case "$addr" in 0.0.0.0:*|"[::]:"*) addr="127.0.0.1:${addr##*:}" ;; esac
  scheme="http"
  case "$gui" in *tls=\"true\"*) scheme="https" ;; esac
  printf '%s\t%s://%s\n' "$key" "$scheme" "$addr"
}

# Staggered versioning keeps N days of replaced copies — the safety net for
# hand-edited prose when two devices touch the same file offline.
_sync_st_versioning_json() {
  jq -nc '{versioning:{type:"staggered",
    params:{maxAge:"31536000",cleanInterval:"3600",versionsPath:""}}}'
}

# Register the vault as a send/receive folder. fsWatcher makes writes propagate
# the moment they land instead of waiting for the rescan interval — that is the
# "sync after every write" requirement, delivered by the daemon.
_sync_st_register() { # <key> <base-url> <myid>
  local body
  body="$(jq -n --arg id "$SYNC_FOLDER_ID" --arg path "$DAVE_HOME" --arg dev "$3" '{
    id:$id, label:"dave", path:$path, type:"sendreceive",
    devices:[{deviceID:$dev}],
    rescanIntervalS:3600,
    fsWatcherEnabled:true, fsWatcherDelayS:5,
    versioning:{type:"staggered",
      params:{maxAge:"31536000",cleanInterval:"3600",versionsPath:""}}}')"
  curl -sf --max-time 5 -X POST \
    -H "X-API-Key: $1" -H 'Content-Type: application/json' \
    -d "$body" "$2/rest/config/folders" >/dev/null 2>&1
}

_sync_st_patch_versioning() { # <key> <base-url> <folder-id>
  curl -sf --max-time 5 -X PATCH \
    -H "X-API-Key: $1" -H 'Content-Type: application/json' \
    -d "$(_sync_st_versioning_json)" \
    "$2/rest/config/folders/$3" >/dev/null 2>&1
}

# y only on a tty; everything else — including a piped or closed stdin — is a
# no. --auto is the non-interactive way to say yes.
_sync_confirm() { # <prompt>
  [ -t 0 ] || return 1
  local ans
  read -r -p "$1 [y/N] " ans || return 1
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Offer to turn on versioning when the registered folder predates it.
_sync_guided_versioning() { # <key> <base-url> <auto>
  local entry fid
  entry="$(_sync_folder_entry "$1" "$2")"
  [ -n "$entry" ] || return 0
  [ "$(printf '%s' "$entry" | jq -r '.versioning.type // ""')" = "staggered" ] \
    && return 0
  fid="$(printf '%s' "$entry" | jq -r .id)"
  if [ "$3" -eq 1 ] || _sync_confirm \
       "folder has no staggered versioning — enable it (protects hand-edited markdown)?"; then
    if _sync_st_patch_versioning "$1" "$2" "$fid"; then
      echo "syncthing: staggered versioning enabled on '$fid'"
    else
      echo "syncthing: could not enable versioning — set it in the gui"
    fi
  fi
}

_sync_guided() {
  local auto="$1" bin="${SYNCTHING_BIN:-syncthing}"
  if ! command -v "$bin" >/dev/null 2>&1; then
    _sync_install_hint
    return 0
  fi
  "$bin" --version 2>/dev/null | head -1 || true

  # Credentials come from env/local config first; if none were saved yet,
  # scrape the daemon's own config.xml — it always knows its api key.
  local key url
  key="$(_sync_api_key)"; url="$(_sync_api_url)"
  if [ -z "$key" ]; then
    local xml creds
    xml="$(_sync_st_config_xml)"
    creds=""
    [ -n "$xml" ] && creds="$(_sync_st_credentials "$xml")"
    if [ -n "$creds" ]; then
      key="${creds%%$'\t'*}"; url="${creds#*$'\t'}"
    fi
  fi
  if [ -z "$key" ]; then
    cat <<'EOF'
syncthing: no api key found — register the folder by hand in the gui
  (http://127.0.0.1:8384 -> add folder), or export SYNCTHING_API_KEY and re-run.
EOF
    return 0
  fi

  local myid
  myid="$(_sync_st_myid "$key" "$url")"
  if [ -z "$myid" ]; then
    cat <<EOF
syncthing: not reachable at $url — is the daemon running?
  start it (systemctl --user start syncthing) and re-run: dave.sh sync setup
EOF
    return 0
  fi
  printf 'syncthing: api reachable at %s\n' "$url"
  printf 'syncthing device id: %s\n' "$myid"

  # Persist the key we just proved works so `sync status` can check the daemon
  # without scraping config.xml again. Device-local file — never synced.
  if [ "$(config_get '.sync.syncthing_api_key')" != "$key" ] || \
     [ "$(config_get '.sync.syncthing_url')" != "$url" ]; then
    json_edit "$LOCAL_CONFIG" --arg k "$key" --arg u "$url" \
      '.sync.syncthing_api_key = $k | .sync.syncthing_url = $u'
    echo "saved api credentials to .local/config.json"
  fi

  local state=0
  _sync_folder_state "$key" "$url" || state=$?
  case "$state" in
    0)
      echo "syncthing: folder already registered for $DAVE_HOME"
      _sync_guided_versioning "$key" "$url" "$auto"
      ;;
    1)
      if [ "$auto" -eq 1 ] || _sync_confirm \
           "register $DAVE_HOME as syncthing folder '$SYNC_FOLDER_ID' (fs watch + staggered versioning)?"; then
        if _sync_st_register "$key" "$url" "$myid"; then
          echo "syncthing: registered '$SYNC_FOLDER_ID' -> $DAVE_HOME"
        else
          echo "syncthing: registration failed — add the folder in the gui instead"
        fi
      else
        echo "syncthing: no folder covers $DAVE_HOME yet — skipped"
        echo "  (re-run in a terminal to be asked, or: sync setup --auto)"
      fi
      ;;
  esac

  cat <<EOF

pairing — once, on the other device:
  1. install syncthing and run this same 'dave.sh sync setup'
  2. add this device's id in its gui, or accept the introduction prompt:
     $myid
  3. share folder '$SYNC_FOLDER_ID' with that device and accept the share
     prompt there — the identical folder id is what makes them one folder
EOF
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
  # The daemon's device id is what a peer needs to pair — worth one extra
  # bounded call, but only when the api answered at all.
  local stid=""
  if [ "$state" -ne 2 ]; then
    stid="$(_sync_st_myid "$(_sync_api_key)" "$(_sync_api_url)")"
  fi

  local integrity='{}' identity='{}'
  [ ! -f "$LOCAL/integrity.json" ] || integrity="$(cat "$LOCAL/integrity.json")"
  [ ! -f "$VIEWS/identity-diagnostics.json" ] || identity="$(cat "$VIEWS/identity-diagnostics.json")"
  if [ "$as_json" -eq 1 ]; then
    jq -n --argjson integrity "$integrity" --argjson identity "$identity" --argjson j "$journals" --argjson c "${conflicts:-0}" \
      --arg fresh "$fresh" --arg st "$syncthing" --arg stid "$stid" \
      --argjson enabled "$(sync_ready && echo true || echo false)" \
      --arg home "$DAVE_HOME" \
      '{home:$home, enabled:$enabled, journals:$j, integrity:$integrity, identity_diagnostics:$identity,
        views:$fresh, conflicts:$c, syncthing:$st,
        syncthing_id:(if $stid == "" then null else $stid end)}'
    return 0
  fi

  printf 'device: %s\n' "$(device_id)"
  printf 'sync:   %s\n' "$(sync_ready && echo enabled || echo 'not enabled — run: sync setup')"
  printf 'views:  %s\n' "$fresh"
  printf '%s' "$journals" | jq -r '.[] | "journal: \(.dev)  \(.events) events, last \(.last_ts // "—")"'
  printf '%s' "$integrity" | jq -r '"journal integrity: \(.diagnostics // [] | length) diagnostic(s)"'
  printf 'conflict copies: %s\n' "$conflicts"
  printf 'syncthing: %s\n' "$syncthing"
  [ -n "$stid" ] && printf 'syncthing device: %s\n' "$stid"
  return 0
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
