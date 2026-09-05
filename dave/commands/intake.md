---
description: "Feed D.A.V.E. a kanban board or pull Redmine, then reconcile into one ranked list"
argument-hint: "[board name or 'redmine']"
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "Task", "AskUserQuestion"]
---

Load the `dave` skill and act as D.A.V.E. Read
`references/kanban-intake.md` and `references/priority-model.md` first.

Source the user named: "$ARGUMENTS"

1. **Gather.**
   - Redmine: discover the MCP tools with `ToolSearch: "+redmine issue query"` —
     never assume tool names. If nothing is available, say so and continue with
     what you have. Pull only ranking fields: id, subject, status, priority,
     assignee, due date, last update.
   - Kanban: ask the user to paste or screenshot the board. Archive the raw input
     with `scripts/dave.sh intake "<board name>"` **before** parsing anything.
2. **Delegate the parsing to the `quartermaster` agent.** Give it the current
   `priorities.md`, the raw source, the ranking factors, and `max_now` from config.
   Bulk parsing is exactly what should not run in this session's context.
3. **Grade what comes back** before showing it — check it against the delegation
   contract, and relay its uncertainty as uncertainty.
4. **Show the diff** (new / moved / gone / stale / contested) and get an explicit
   yes. Flag any board older than `kanban.stale_after_days`.
5. Only then write `~/.dave/priorities.md`. It is the user's document — never
   rewrite it silently.
6. If anything is contested between Redmine and a board, surface it as a real
   disagreement for the user to settle; never pick a winner yourself.
