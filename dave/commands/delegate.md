---
description: "Hand work to a roster agent — Quartermaster, Scout, Ideator, Constructor, Critic, or Scribe"
argument-hint: "[agent] <what you want done>"
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "Task", "AskUserQuestion"]
---

Load the `dave` skill and read `references/delegation-contract.md` first.

The charge: "$ARGUMENTS"

1. **Pick the agent.** If the user named one, use it. Otherwise match intent:
   boards or tickets to rank → `quartermaster`; unknowns to investigate →
   `scout`; approach undecided → `ideator`; plan agreed, build it →
   `constructor`; check it before it lands → `critic`; write it up →
   `scribe`. Honor `roster.*` in config — a disabled agent is unavailable, and you
   do the work yourself rather than routing around the setting.

2. **Brief it properly. Never forward the user's raw request.** The agent starts
   cold. Assemble all five: objective, definition of done, constraints, the context
   it cannot discover (filenames, prior decisions, what's already been tried), and
   the return format from its own definition. If you can't fill in the fourth,
   you're not ready to delegate — ask the user first.

3. **Open a mission file** (`scripts/dave.sh mission new "<name>"`) if this spans
   more than one agent or one sitting, and brief from it. Record the charge in the
   Assignments table.

4. **Grade the result** before relaying: does it meet the stated done conditions,
   did it answer the question asked, did it assert anything unverified, did it
   expand scope? Relay the verdict with the work — never launder a subagent's
   confidence into your own.

5. `scripts/dave.sh log` the outcome, and update the mission's Assignments row.

Never chain two agents without the user seeing what came back from the first.
