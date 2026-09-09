---
description: "Register, inspect, or re-status a project — the container a ranked item belongs to"
argument-hint: "[slug] · or 'add <path>' · or 'status <slug> <state>'"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "AskUserQuestion"]
---

Load the `dave` skill and read `references/projects.md` first.

Request: "$ARGUMENTS"

**With no arguments** — report on the project this session is sitting in:
`scripts/dave.sh project show`. If the directory belongs to no registered project,
say so in one line and offer to register it; do not register anything unasked.

**With a slug** — `scripts/dave.sh project show <slug>`. Lead with what is
actionable: refs that have fallen off `priorities.md`, uncommitted work, a last
commit that is old for the project's cadence. Four sentences, not a recital.

**`add <path>`** — register it. Ask for the two things the file cannot derive, in
**one** `AskUserQuestion`:

- **The goal** — one sentence, what finishing looks like. An empty goal makes every
  later review of this project vaguer.
- **The cadence** — `daily`, `weekly`, `monthly`, `dormant`. This is what stops the
  weekly sweep from treating a deliberately idle project as a problem, so it is
  worth the one question.

Then `scripts/dave.sh project add <path> --goal "<goal>" --cadence <cadence>`, and
offer to link the refs already on the priority list that belong to it.

**`status <slug> <state>`** — `active`, `paused`, `maintenance`, `archived`. Note
in one line what changes as a result: a paused project stops being chased by the
review, an archived one stops appearing at all.

Registration is the user's decision. When `projects.autodiscover` surfaces
candidates, present them as candidates and stop there.
