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

# Not set up, or no jq to read the config with: say nothing at all.
[ -f "$CONFIG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Opt-out, defaulting to on.
# NB: `.x // true` is wrong here — jq's `//` yields the right side for `false`
# as well as null, so an explicit `false` would never disable anything.
enabled="$(jq -r 'if .hooks.session_start == null then true else .hooks.session_start end' \
  "$CONFIG" 2>/dev/null || echo true)"
[ "$enabled" = "false" ] && exit 0

emit() { printf '%s\n' "$1"; }

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

context="$(cat <<CTX
D.A.V.E. (dave plugin) is active. Priority state from ${DAVE_HOME}:

Current focus: ${focus_line}

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
