---
description: "Hand work to a roster agent — Quartermaster, Scout, Ideator, Constructor, Critic, or Scribe"
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "Task", "AskUserQuestion"]
---

Load the `dave` skill and read `references/delegation-contract.md` first.

The charge: "$ARGUMENTS"

1. **Pick the agent.** If the user named one, use it. Otherwise match intent:
   boards or tickets to rank → `quartermaster`; map an unfamiliar codebase →
   `cartographer` (top-down; pass `L2 <area>` or `L3 <path>` for depth, otherwise
   it returns the overview plus a drill menu to put to the user); one specific
   unknown to investigate → `scout`; the idea is
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

   When a mission exists, **assemble it rather than recalling it**:
   `scripts/dave.sh mission pack <slug> --agent <name>` emits all five from the
   brief, plus the project's cached dossier and how every prior charge on this
   mission graded. Read it, add what only you know from the conversation, and send
   that. If it reports the brief is incomplete, fill the brief — do not send it
   anyway.

   **Reuse before you respawn.** A follow-up goes back to the agent that already
   has the context via `SendMessage`, not into a second cold spawn. Before charging
   Cartographer, check `scripts/dave.sh dossier get <project>` — a current map may
   answer the charge for free.

3. **Use the agent's declared model** unless the charge is unusually hard for it.
   Defaults are sized to the work: `haiku` for Scribe, `sonnet` for most of the
   roster, `opus` only for Constructor and Critic. A `models` entry in config wins
   over the agent's default; an explicit model on the call wins over both. If you
   escalate, say so and why in the relay.

4. **Open a mission file** (`scripts/dave.sh mission new "<name>" --ref <ref>`) if
   this spans more than one agent or one sitting, and brief from it. Record the
   charge as you send it:

   ```bash
   id=$(scripts/dave.sh mission assign <slug> <agent> "<the charge>" --model <m>)
   ```

5. **Grade the result** before relaying: does it meet the stated done conditions,
   did it answer the question asked, did it assert anything unverified, did it
   expand scope? Relay the verdict with the work — never launder a subagent's
   confidence into your own. The vocabulary is fixed:

   ```bash
   scripts/dave.sh mission record "$id" --verdict trust|partial|rerun|discard      --summary "<what to check>"
   ```

   `rerun` means re-run it, heavier or re-briefed. `discard` means it answered an
   easier question and must not be relayed at all.

6. `scripts/dave.sh log` the outcome. The Assignments table needs no editing — it
   is rendered from the ledger.

Never chain two agents without the user seeing what came back from the first.
