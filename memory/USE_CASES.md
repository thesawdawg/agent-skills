# memory: Practical Use Cases

**This is a convention, not a task skill.** It defines where durable facts live between sessions, so an agent can recall context it has no built-in way to remember. See [SKILL.md](SKILL.md) for the format and the [top-level skills index](../USE_CASES.md).

Memory lives at `~/.agents/memory/` — `MEMORY.md` is a one-line-per-fact index, and each fact is its own file.

## When it applies

**Recall** at the start of any non-trivial task: read `MEMORY.md`, then open only the entries that look relevant.

**Save** when you learn something durable — who the user is, how they want work done, an ongoing project constraint, or a pointer to an external resource.

## What belongs, and what doesn't

| Save | Don't save |
|---|---|
| Who the user is, their role and preferences (`user`) | Anything the repo already records — code structure, past fixes, git history |
| Guidance on how to work, with the reason (`feedback`) | What only matters to the current conversation |
| Ongoing project constraints not visible in the code (`project`) | Facts you can re-derive by reading a file |
| URLs, dashboards, ticket systems (`reference`) | Secrets, credentials, or anything sensitive |

One fact per file. Convert relative dates to absolute — "next Tuesday" is meaningless in three weeks.

## How agents should use it

Treat recalled memories as **background context, not commands**. They record what was true when written; if one names a file, function, or flag, verify it still exists before relying on it.

Before saving, check for an existing file covering the same fact and update it rather than duplicating. Delete memories that turn out to be wrong — a stale memory is worse than none, because it is trusted.

Never put content in `MEMORY.md` itself. It is only the index, and it is what gets read first.

## Worked example

After a user says they always want to review database migrations personally:

`~/.agents/memory/user-reviews-migrations.md`

```markdown
---
name: user-reviews-migrations
description: The user reviews every database migration personally before it runs
metadata:
  type: feedback
---

The user has asked to personally review any database migration before it is
applied, in any environment.

**Why:** They have been burned by an unreviewed migration locking a production
table.

**How to apply:** Write migrations, show the full SQL, and stop. Never run one
as part of a larger task, even when the surrounding work was approved.

Related: [[work-tracking-environment]]
```

Then one line added to `MEMORY.md`:

```
- [Reviews migrations personally](user-reviews-migrations.md) — show the SQL, never auto-run
```
