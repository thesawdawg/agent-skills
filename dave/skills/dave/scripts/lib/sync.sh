# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# sync.sh — cross-device persistence: ~/.dave as a git repo on a private remote.
# Sourced by dave.sh.
#
# config.json is gitignored, so device-local settings (and any future secrets)
# never leave the machine. Everything else — priorities, log, missions, projects,
# ledgers — is shared state. Pull runs at the top of `brief`; push is
# `dave.sh sync push` only when run by the user. Every network op goes through gnet(), which
# bounds connect and transfer time: an offline machine degrades to "use local
# state" instead of hanging the session start.
#
# Sequential use is the contract: pull-before-write covers one human moving
# between machines. Two devices writing at once can still diverge, and the
# failure mode is a reported pull failure, never silent loss.

gd()   { git -C "$DAVE_HOME" "$@"; }
gnet() { timeout 15 env GIT_SSH_COMMAND='ssh -o ConnectTimeout=5 -o BatchMode=yes' git -C "$DAVE_HOME" "$@"; }

sync_branch() { config_get '.sync.branch' 'main'; }

sync_ready() {
  [ "$(config_bool '.sync.enabled' false)" = "true" ] && [ -d "$DAVE_HOME/.git" ]
}

cmd_sync() {
  require_init
  need_jq
  local sub="${1:-status}"
  case "$sub" in
    setup)
      local url="${2:-$(config_get '.sync.remote')}"
      [ -n "$url" ] || die "usage: sync setup <git-remote-url>"
      if [ ! -d "$DAVE_HOME/.git" ]; then
        gd init -q
        gd symbolic-ref HEAD "refs/heads/$(sync_branch)"
      fi
      # config.json is per-device; everything else in $DAVE_HOME is shared state.
      printf 'config.json\n*.swp\n.DS_Store\n' > "$DAVE_HOME/.gitignore"
      # Repo-local identity: a state tree's commits belong to the user's name
      # from config, and gh's noreply address keeps real email out of history.
      local uemail
      uemail="$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"' 2>/dev/null || echo 'dave@localhost')"
      gd config user.name "$(config_get '.user.name' 'dave')"
      gd config user.email "$uemail"
      gd remote remove origin 2>/dev/null || true
      gd remote add origin "$url"
      json_edit "$CONFIG" --arg url "$url" --arg br "$(sync_branch)" \
        '.sync.enabled = true | .sync.remote = $url | .sync.branch = $br'
      # Any advertised ref means the remote has state — a fresh repo advertises
      # nothing, and HEAD alone is not safe to ask about when it is a dangling
      # symref (a bare repo whose default branch was never pushed).
      if gnet ls-remote --exit-code origin >/dev/null 2>&1; then
        # Remote already has state (this is a second device): take it wholesale.
        # config.json is untracked and survives the reset untouched.
        gnet fetch -q origin || die "fetch failed — check remote URL and network"
        gd rev-parse --verify -q "origin/$(sync_branch)" >/dev/null \
          || die "remote has no branch '$(sync_branch)' — check .sync.branch in config.json"
        gd reset -q --hard "origin/$(sync_branch)"
        gd branch --set-upstream-to="origin/$(sync_branch)" "$(sync_branch)" 2>/dev/null || true
        echo "sync: adopted remote state from $url (local files replaced; config.json kept)"
      else
        gd add -A
        if ! gd diff --cached --quiet 2>/dev/null; then
          gd commit -q -m "dave state: initial commit ($(hostname -s))"
        fi
        gnet push -q -u origin "$(sync_branch)" || die "push failed — is the remote empty and reachable?"
        echo "sync: initialized $DAVE_HOME -> $url"
      fi
      ;;
    pull)
      sync_ready || die "sync not configured — run: dave.sh sync setup <git-remote-url>"
      local br; br="$(sync_branch)"
      local behind
      behind="$(gnet rev-list --count "HEAD..origin/$br" 2>/dev/null || echo '?')"
      # --autostash because a skipped closeout push is exactly when pull finds
      # both sides changed. A conflict aborts back to a clean tree and reports
      # rather than leaving the state repo mid-rebase.
      if ! gnet pull -q --rebase --autostash origin "$br"; then
        gd rebase --abort >/dev/null 2>&1 || true
        echo "sync: pull FAILED — local and remote diverged; resolve in $DAVE_HOME" >&2
        return 1
      fi
      if [ "$behind" = "0" ]; then echo "sync: up to date"
      elif [ "$behind" = "?" ]; then echo "sync: up to date (remote unreadable before pull)"
      else echo "sync: pulled $behind commit(s)"; fi
      ;;
    push)
      sync_ready || die "sync not configured — run: dave.sh sync setup <git-remote-url>"
      local br; br="$(sync_branch)"
      gd add -A
      local ahead
      ahead="$(gd rev-list --count "origin/$br..HEAD" 2>/dev/null || echo 0)"
      if gd diff --cached --quiet && [ "$ahead" = "0" ]; then
        echo "sync: nothing to push"
        return 0
      fi
      gd diff --cached --quiet || gd commit -q -m "sync: $(hostname -s) $(date '+%F %H:%M')"
      if ! gnet push -q origin "$br"; then
        echo "sync: push FAILED — remote may be ahead; run: dave.sh sync pull" >&2
        return 1
      fi
      echo "sync: pushed"
      ;;
    status)
      if ! sync_ready; then
        echo "sync: not configured (enabled in config.json + .git repo both required)"
        return 0
      fi
      local br; br="$(sync_branch)"
      gnet fetch -q origin 2>/dev/null || echo "sync: remote unreachable — showing local state"
      local ahead behind dirty
      ahead="$(gd --no-optional-locks rev-list --count "origin/$br..HEAD" 2>/dev/null || echo '?')"
      behind="$(gd --no-optional-locks rev-list --count "HEAD..origin/$br" 2>/dev/null || echo '?')"
      dirty="$(gd --no-optional-locks status --porcelain | wc -l | tr -d ' ')"
      echo "remote:  $(config_get '.sync.remote' '-') (branch $br)"
      echo "ahead:   $ahead   behind: $behind   dirty files: $dirty"
      gd --no-optional-locks log -1 --format='last commit: %h %s (%cr)' 2>/dev/null || true
      ;;
    *) die "unknown sync subcommand: $sub (setup|pull|push|status)" ;;
  esac
}
