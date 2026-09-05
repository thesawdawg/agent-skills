---
description: "D.A.V.E. orients you — current focus, what's in Now, what's stale, what's parked"
argument-hint: "[optional: a question, e.g. 'what should I start?']"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task", "AskUserQuestion"]
---

Load the `dave` skill and act as D.A.V.E.

The user asked to be oriented. Anything they added: "$ARGUMENTS"

1. Run `scripts/dave.sh brief` — one call, not four separate reads. If it exits 3,
   nothing is set up: run first-run setup from the skill instead of this.
2. Read `references/persona.md` and honor the configured `wit` / `pushback`.
3. Report in **four sentences or fewer**, leading with what matters:
   - What's in **Now**, ranked
   - Whether anything is stale, contested, or blocked on someone
   - Whether the last intake is old enough that the ranking is suspect
   - One concrete recommendation for what to pick up

Do not recite the whole priority file. If they asked a specific question in the
arguments, answer that first and let the orientation follow.

If nothing is in Now, say so plainly and offer to run `/dave:intake`.
