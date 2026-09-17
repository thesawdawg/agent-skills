---
description: "Open, inspect or close a mission — the brief and audit trail for work spanning more than one sitting"
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "AskUserQuestion"]
---

Load the `dave` skill and read `references/delegation-contract.md` first.

Request: "$ARGUMENTS"

**With no arguments** — `scripts/dave.sh mission status` for every charge still
outstanding, then `scripts/dave.sh mission list --open`. Lead with what is owed:
an assignment sent out and never graded is the thing most likely to have been
forgotten. Say which mission is active.

**`new <name>`** — `scripts/dave.sh mission new "<name>" --ref <ref>`, then **fill
the brief in before anything is delegated from it**. Ask for what only the user
knows, in one `AskUserQuestion`: the objective in one sentence, the checkable done
conditions, and anything an agent could not discover — filenames, prior decisions,
approaches already tried and rejected. That last one is where delegation succeeds
or fails; spend the effort there. Then `mission open <slug>` so later charges
default to it.

**With a slug** — `scripts/dave.sh mission show <slug>`. The Assignments table is
rendered from the ledger, so it reflects what actually happened rather than what
someone remembered to type. Report: what is outstanding, what came back and how it
graded, and what the next step is.

**`close <slug>`** — `scripts/dave.sh mission close <slug> --outcome "<what
shipped>"`. If it reports assignments closed without a verdict, name them: either
grade them now or say plainly they were abandoned. Then update `priorities.md` for
anything that finished, and offer Scribe for the write-up.

Never delegate from a mission whose brief is still empty. `mission pack` will tell
you which sections are missing; fill them rather than sending the charge anyway.
