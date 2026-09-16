#!/usr/bin/env bash
# SessionStart hook for the D.A.V.E. plugin.
#
# Injects the current focus and the Now section of the priority list as session
# context. Stays completely silent unless D.A.V.E. is actually set up and the user
# has left the hook enabled — a productivity plugin that talks in every unrelated
# session is a productivity plugin that gets uninstalled.
#
# Deployed at <install>/hooks/session-start.sh, a sibling of the skills/ dir —
# not inside the skill itself, so the hook can outlive skill updates.

set -uo pipefail

DAVE_HOME="${DAVE_HOME:-$HOME/.dave}"
CONFIG="$DAVE_HOME/config.json"
STATE="$DAVE_HOME/state.json"
PRIORITIES="$DAVE_HOME/priorities.md"

# Keep in step with SCHEMA_VERSION in scripts/lib/common.sh.
SCHEMA_VERSION=2

# Not set up, or no jq to read the config with: say nothing at all.
[ -f "$CONFIG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Opt-out, defaulting to on.
# NB: `.x // true` is wrong here — jq's `//` yields the right side for `false`
# as well as null, so an explicit `false` would never disable anything.
enabled="$(jq -r 'if .hooks.session_start == null then true else .hooks.session_start end' \
  "$CONFIG" 2>/dev/null || echo true)"
[ "$enabled" = "false" ] && exit 0

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

parked=0
if [ -f "$DAVE_HOME/parking-lot.md" ]; then
  parked="$(grep -c '^- \[ \]' "$DAVE_HOME/parking-lot.md" 2>/dev/null || true)"
  parked="${parked:-0}"
fi

last_intake="never"
if [ -f "$STATE" ]; then
  last_intake="$(jq -r '.last_intake // "never"' "$STATE" 2>/dev/null || echo "never")"
fi

# Housekeeping notes: one line each, raised once, then dropped. Each exists to
# catch a gap the state itself cannot — a tree older than this script, and a
# device nobody ever offered cross-device sync to.
notes=""

if [ -f "$STATE" ]; then
  v="$(jq -r '.schema_version // 1' "$STATE" 2>/dev/null || echo 1)"
  if [ "$v" -lt "$SCHEMA_VERSION" ] 2>/dev/null; then
    notes="${notes}- State schema is behind this version — run \`dave.sh migrate\`.\n"
  fi
fi

sync_declined="$(jq -r 'if .sync.declined == null then false else .sync.declined end' \
  "$CONFIG" 2>/dev/null || echo false)"
sync_enabled="$(jq -r 'if .sync.enabled == null then false else .sync.enabled end' \
  "$CONFIG" 2>/dev/null || echo false)"
if [ "$sync_declined" != "true" ] && { [ "$sync_enabled" != "true" ] || [ ! -d "$DAVE_HOME/.git" ]; }; then
  notes="${notes}- Sync is not configured on this device — state here is local-only. Offer \`dave.sh sync setup <remote-url>\` once; a no is recorded as \"declined\": true in config.json.\n"
fi

housekeeping=""
if [ -n "$notes" ]; then
  housekeeping="$(printf '\nHousekeeping — flag once, then drop it:\n%b' "$notes")"
fi

context="$(cat <<CTX
D.A.V.E. (dave plugin) is active. Priority state from ${DAVE_HOME}:

Current focus: ${focus_line}

Now (the operative definition of on-track):
${now_section}

Open parked items: ${parked}
Last intake: ${last_intake}
${housekeeping}
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
