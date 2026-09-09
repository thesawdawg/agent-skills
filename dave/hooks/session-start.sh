#!/usr/bin/env bash
# SessionStart hook for the D.A.V.E. plugin.
#
# Injects the current focus and the Now section of the priority list as session
# context. Stays completely silent unless D.A.V.E. is actually set up and the user
# has left the hook enabled — a productivity plugin that talks in every unrelated
# session is a productivity plugin that gets uninstalled.

set -uo pipefail

DAVE_HOME="${DAVE_HOME:-$HOME/.dave}"
CONFIG="$DAVE_HOME/config.json"
STATE="$DAVE_HOME/state.json"
PRIORITIES="$DAVE_HOME/priorities.md"

# Derived from this file rather than $CLAUDE_PLUGIN_ROOT, so the hook works the
# same whether the harness exports that variable or not.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAVE_SH="$HOOK_DIR/../skills/dave/scripts/dave.sh"
[ -x "$DAVE_SH" ] || DAVE_SH="${CLAUDE_PLUGIN_ROOT:-}/skills/dave/scripts/dave.sh"

# Not set up, or no jq to read the config with: say nothing at all.
[ -f "$CONFIG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Opt-out, defaulting to on.
# NB: `.x // true` is wrong here — jq's `//` yields the right side for `false`
# as well as null, so an explicit `false` would never disable anything.
enabled="$(jq -r 'if .hooks.session_start == null then true else .hooks.session_start end' \
  "$CONFIG" 2>/dev/null || echo true)"
[ "$enabled" = "false" ] && exit 0

# Which project this session is sitting in, if any. Exit 4 means the state tree
# predates this version — say so once, quietly, rather than degrading in silence
# for weeks.
project_block=""
schema_note=""
if [ -x "$DAVE_SH" ]; then
  rc=0
  slug="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && "$DAVE_SH" project resolve 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 4 ]; then
    schema_note="Note: the D.A.V.E. state tree is behind this version — run \`dave.sh migrate\`."
  elif [ -n "${slug:-}" ] && [ -f "$DAVE_HOME/projects/$slug/project.json" ]; then
    project_block="$(jq -r '
      "Project: \(.name)\(if .name == .slug then "" else " (\(.slug))" end) — \(.status), \(.cadence) cadence" +
      (if (.goal // "") == "" then "" else "\nGoal: \(.goal)" end) +
      (if (.refs | length) == 0 then "" else "\nIts refs: \(.refs | join(", "))" end)
    ' "$DAVE_HOME/projects/$slug/project.json" 2>/dev/null || true)"

    # Git state only if a scan already knows it. The hook reads what is known and
    # stays quiet when nothing is; it never probes a repository itself.
    cache="$DAVE_HOME/scan-cache.json"
    if [ -f "$cache" ]; then
      ttl="$(jq -r '.projects.scan_ttl_seconds // 300' "$CONFIG" 2>/dev/null || echo 300)"
      gen="$(jq -r '.generated // empty' "$cache" 2>/dev/null || true)"
      if [ -n "$gen" ]; then
        age=$(( $(date +%s) - $(date -d "$gen" +%s 2>/dev/null || echo 0) ))
        if [ "$age" -lt "$ttl" ]; then
          git_line="$(jq -r --arg s "$slug" '
            .entries[$s] // empty | select(.repo == true)
            | "Git: \(.branch)"
              + (if .dirty > 0 or .untracked > 0 then ", \(.dirty) dirty/\(.untracked) untracked" else ", clean" end)
              + (if .days_since_commit == null then ""
                 elif .days_since_commit == 0 then ", last commit today"
                 elif .days_since_commit == 1 then ", last commit yesterday"
                 else ", last commit \(.days_since_commit)d ago" end)' \
            "$cache" 2>/dev/null || true)"
          [ -n "${git_line:-}" ] && project_block="${project_block}"$'\n'"${git_line}"
        fi
      fi
    fi
  fi
fi

focus_line="(none set)"
if [ -f "$STATE" ]; then
  focus_line="$(jq -r '
    if .focus == null then "(none set)"
    else "\(.focus.ref) — \(.focus.label) (since \(.focus.started))"
    end' "$STATE" 2>/dev/null || echo "(unreadable)")"
fi

# Just the Now section — the whole file is too much for every session start.
now_section="(priority list not found)"
if [ -f "$PRIORITIES" ]; then
  # Keep only actual list items — the section's italic explainer and HTML
  # comments are template prose, not priorities.
  now_section="$(awk '/^## Now/{f=1;next} /^## /{f=0} f' "$PRIORITIES" \
    | grep -E '^[[:space:]]*([0-9]+\.|[-*])[[:space:]]' || true)"
  [ -n "$now_section" ] || now_section="(nothing in Now)"
fi

# Where the focused ref was left, and anything promised to a person that is
# about to come due. Both are silent when there is nothing to say.
next_line=""
if [ -f "$DAVE_HOME/notes.json" ] && [ -f "$STATE" ]; then
  fref="$(jq -r '.focus.ref // empty' "$STATE" 2>/dev/null || true)"
  if [ -n "${fref:-}" ]; then
    nt="$(jq -r --arg r "$fref" '.[$r].text // empty' "$DAVE_HOME/notes.json" 2>/dev/null || true)"
    [ -n "${nt:-}" ] && next_line="Left off at: ${nt}"
  fi
fi

promise_line=""
if [ -f "$DAVE_HOME/commitments.json" ]; then
  horizon="$(jq -r '.review.promise_horizon_days // 3' "$CONFIG" 2>/dev/null || echo 3)"
  promise_line="$(jq -r --arg today "$(date +%F)" --arg soon "$(date -d "+${horizon} day" +%F 2>/dev/null || date +%F)" '
    [ .[] | select(.status == "open" and .due <= $soon) ] as $due
    | if ($due | length) == 0 then empty
      else "Promised: " + ([$due[] | "\(.who) — \(.what) (\(if .due < $today then "OVERDUE" else .due end))"] | join("; "))
      end' "$DAVE_HOME/commitments.json" 2>/dev/null || true)"
fi

parked=0
if [ -f "$DAVE_HOME/parking-lot.md" ]; then
  parked="$(grep -c '^- \[ \]' "$DAVE_HOME/parking-lot.md" 2>/dev/null || true)"
  parked="${parked:-0}"
fi

last_intake="never"
if [ -f "$STATE" ]; then
  last_intake="$(jq -r '.last_intake // "never"' "$STATE" 2>/dev/null || echo "never")"
fi

# Only the parts that have something to say. An unregistered directory gets
# exactly the block it got before this existed.
extra=""
[ -n "$project_block" ] && extra="${project_block}"$'\n\n'
[ -n "$schema_note" ]   && extra="${extra}${schema_note}"$'\n\n'
[ -n "$promise_line" ]  && extra="${extra}${promise_line}"$'\n\n'

context="$(cat <<CTX
D.A.V.E. (dave plugin) is active. Priority state from ${DAVE_HOME}:

${extra}Current focus: ${focus_line}${next_line:+
${next_line}}

Now (the operative definition of on-track):
${now_section}

Open parked items: ${parked}
Last intake: ${last_intake}

You are not D.A.V.E. unless the user invokes the \`dave\` skill or a /dave:* command.
Do not adopt the persona, announce this block, or bring up priorities unprompted.

Use it only for this: if the work in this session drifts off the list above —
unlisted work running long, a third unrelated repository, or something previously
parked — mention it ONCE, in one sentence, offering park / promote / continue, then
take the answer and drop it. Never raise a settled objection twice.

/dave:brief to orient · /dave:check for a drift check · /dave:park to capture a detour
CTX
)"

jq -n --arg ctx "$context" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0
