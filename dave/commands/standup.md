---
description: "Turn what you actually did into a standup, ticket comment, or time entry"
argument-hint: "[days back, default 1] [optional: 'ticket' or 'commit']"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task", "AskUserQuestion"]
---

Load the `dave` skill and read `references/redmine.md` first.

Request: "$ARGUMENTS"

1. `scripts/dave.sh standup <days>` (default 1) for the raw log, plus
   `scripts/dave.sh priorities` for what those refs mean.
2. **Delegate to the `scribe` agent** with the log, the refs, and which artifacts
   are wanted — standup notes, a Redmine comment, a time entry, a commit message,
   or a handoff.
3. Scribe drafts; it never sends. Show each draft in full alongside its **Basis**
   so the user can check it against what actually happened.
4. **Every outward write needs its own explicit yes.** Show the exact payload with
   before/after for each changing field, as in the approval-gate format in
   `references/redmine.md`. One approval, one write — approving a comment is not
   approval to also log time. Itemize batches.
5. Never invent hours. If the log is thin, present what it does show and ask,
   rather than estimating. A fabricated time entry is a false record in the team's
   system.
6. After sending, update `priorities.md` for anything that closed and promote from
   Next to fill Now.
