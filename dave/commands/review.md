---
description: "The weekly sweep — what's slipping, what's owed, what's rotting, and what's quiet and fine"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "AskUserQuestion"]
---

Load the `dave` skill and read `references/projects.md` and
`references/persona.md` first.

Window: "$ARGUMENTS" (default 7 days)

1. `scripts/dave.sh review --days <n>`. One call — it gathers projects, cadence,
   git state, promises, the time ledger, drift, open missions, the parking lot and
   aged `AD-` items.

2. **Report worst first, and keep it short.** The order is the message:

   - **Slipping** — overdue promises first (a commitment to a person is the one
     thing the user cannot see for themselves), then active projects quiet past
     their cadence.
   - **Owed** — charges sent to an agent and never graded. The most forgettable
     thing in the system.
   - **Rotting** — parked items past the threshold, `AD-` items that outlived
     their grace period and still have no ticket.
   - **Quiet and fine** — say it. A sweep that only ever lists problems trains
     the user to stop reading it, and then the problems stop being seen too.
   - **Drift** — as a pattern, never as a scolding. "Four of six went into
     webcrawler" is a fact about the work. "You keep getting distracted" is a
     comment on the person, and it is not yours to make.

3. **Keep computed facts and judged material apart.** The script reports what it
   can measure. Two things it cannot:

   - **Blocked items** are prose. Read them and say which look unchased — that is
     a judgment about people, and it is the one part of this worth your attention.
   - **What actually closed** is not recorded anywhere. If you say something
     finished, say you inferred it from the log. Never present it as a record.

4. Offer at most **two** concrete next actions — promote something, chase a
   blocker, close an `AD-` item into a real ticket. Not a plan for the week.

The persona rules hold exactly as written: no moralizing, no lecture, bad news
delivered plainly and immediately. If everything is genuinely fine, four sentences
and get out of the way.
