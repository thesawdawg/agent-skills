# workflow-rules: Practical Use Cases

**This is a convention, not a task skill.** It carries the repo owner's standing preferences for how work gets done, and applies by default rather than on request. See [SKILL.md](SKILL.md) for the rules themselves and the [top-level skills index](../USE_CASES.md).

## When it applies

By default, on every coding and git task, and at the start of any non-trivial piece of work.

## The rules that most often get broken

| Rule | Why it exists |
|---|---|
| **Never run `git push`** | Pushing is the user's call, always. Stage, commit, report — then stop |
| **No `Co-Authored-By` unless asked** | Attribution is the user's to grant; a trailer added on assumption misattributes a permanent record |
| **Ask 1–5 clarifying questions first** | Ask before doing, not after. Wrong-but-confident work costs more than a question |
| **Conventional Commits, plainly worded** | Format from [`coding-style`](../coding-style/USE_CASES.md); tone is short and readable, not a changelog entry |
| **Branch by feature or fix** | `feat/add-login`, `fix/db-timeout` |
| **DRY — check before building** | Reuse what exists. This is what D.A.V.E.'s `module-finder` agent operationalises |

Plus the engineering defaults: object-oriented and modular, typehints everywhere, full docstrings, comments that explain *why*, and docs updated whenever an interface changes.

## How agents should use it

Read it at the start of substantive work. When it conflicts with your own defaults, it wins — these are the user's stated preferences in their own repo.

When it conflicts with a **direct instruction in the conversation**, the instruction wins for that instance only, and you should say so rather than silently crossing a stated rule. "Push it" is permission to push once; it is not a standing licence, and the next session should ask again.

Pairs with [`coding-style`](../coding-style/USE_CASES.md) for language-specific format, and [`memory`](../memory/USE_CASES.md) for what to remember between sessions.

## Worked example

A user asks for a refactor. Following this file, an agent:

1. Asks two or three questions first — scope, whether tests exist, what must not change.
2. Checks for an existing helper before writing a new one.
3. Writes the change with typehints and docstrings, comments explaining why.
4. Updates the README if an interface changed.
5. Commits as `refactor(scope): ...`, plainly worded, **without** a co-author trailer.
6. **Stops.** Reports status and leaves the push to the user.

Step 6 is the one that gets skipped. Don't skip it.
