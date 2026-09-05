---
description: "Hand work to a roster agent — Quartermaster, Scout, Ideator, Constructor, Critic, or Scribe"
argument-hint: "[agent] <what you want done>"
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "Task", "AskUserQuestion"]
---

Load the `dave` skill and read `references/delegation-contract.md` first.

The charge: "$ARGUMENTS"

1. **Pick the agent.** If the user named one, use it. Otherwise match intent:
   boards or tickets to rank → `quartermaster`; map an unfamiliar codebase →
   `cartographer`; one specific unknown to investigate → `scout`; the idea is
   still a hunch → `brainstormer`; approach undecided → `ideator`; about to build
   something that may already exist → `module-finder`; plan agreed, build it →
   `constructor`; check it before it lands → `critic`; write it up → `scribe`.
   Honor `roster.*` in config — a disabled agent is unavailable, and you do the
   work yourself rather than routing around the setting.

   Two pairs get mis-picked: `scout` answers one question while `cartographer`
   maps the whole repo, and `brainstormer` works on a hunch while `ideator` works
   on a problem you can already state in a sentence.

   `ideator` and `constructor` are also top-level *skills* in this repo, with
   different jobs — they scope a new project and design its architecture. Inside
   D.A.V.E. these names mean the agents. If the work is genuinely project
   inception rather than mid-ticket, say so and use the skill instead, and record
   which one you used.

2. **Brief it properly. Never forward the user's raw request.** The agent starts
   cold. Assemble all five: objective, definition of done, constraints, the context
   it cannot discover (filenames, prior decisions, what's already been tried), and
   the return format from its own definition. If you can't fill in the fourth,
   you're not ready to delegate — ask the user first.

3. **Use the agent's declared model** unless the charge is unusually hard for it.
   Defaults are sized to the work: `haiku` for Scribe, `sonnet` for most of the
   roster, `opus` only for Constructor and Critic. A `models` entry in config wins
   over the agent's default; an explicit model on the call wins over both. If you
   escalate, say so and why in the relay.

4. **Open a mission file** (`scripts/dave.sh mission new "<name>"`) if this spans
   more than one agent or one sitting, and brief from it. Record the charge in the
   Assignments table.

5. **Grade the result** before relaying: does it meet the stated done conditions,
   did it answer the question asked, did it assert anything unverified, did it
   expand scope? Relay the verdict with the work — never launder a subagent's
   confidence into your own.

6. `scripts/dave.sh log` the outcome, and update the mission's Assignments row.

Never chain two agents without the user seeing what came back from the first.
