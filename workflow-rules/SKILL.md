---
name: workflow-rules
description: Sawyer's personal workflow, git, and engineering rules. Apply whenever writing, reviewing, or refactoring code; running git commands or generating commits; or starting any non-trivial task. Advises never git push, co-author-only-on-approval, proportionate clarification, DRY/modular OOP design, full typehints and docstrings, and clean-over-verbose code. Includes on-demand language and commit conventions.
---

# Workflow & Engineering Rules

These are the user's (Sawyer / "Sawdawg") standing preferences. Apply them by
default on every coding and git task. For language-specific style (PEP 8,
Conventional Commits format, Flask patterns), defer to the [style reference](references/coding-style.md).

## Git — Hard Rules

- **Never run `git push`.** Pushing is the user's job, always. Stage, commit,
  and report status — but stop before pushing, no exceptions.
- **Commits follow Conventional Commits.** See the [style reference](references/coding-style.md) for the
  full type/scope/format spec.
- **Commit message tone:** simple and to the point. Avoid verbose language;
  optimize for readability.
- **Co-authoring requires explicit approval.** Do **not** add a `Co-Authored-By`
  trailer automatically. Only the committer set in `git config user.*` appears
  unless the user explicitly asks for a co-author.
- Branch by feature or fix (`feat/add-login`, `fix/db-timeout`); keep commits
  small and focused.

## Engineering Philosophy

Keep things simple. Favor clean, maintainable code over clever or verbose code.

- **DRY** — reuse existing functionality; never re-implement what already exists.
  Check for an existing helper/class/module before writing a new one.
- **Object-oriented & modular** — implement features as classes designed for
  object usage. Structure for modularity, and lift shared behavior into a common
  parent class where it fits (e.g. an authenticated-client base, a db-connection
  base).
- **Maintainability first** — code must be understandable in 6 months by any
  other developer. Prefer clarity over brevity.
- **Typehints everywhere** — every function signature and class attribute.
- **Full docstrings** for every function: description, `Args`, and `Returns`
  (and `Raises` when non-obvious).
- **Comments explain why, not what.** Keep them current.
- **Docs** — update the relevant `README` / docs whenever behavior or interfaces
  change.

## Working Style

- Ask only for missing information that changes the result. Reuse earlier
  answers and approved artifacts; do not repeat interviews or permission gates.
- When relevant, consult and update persistent memory — see the `memory` skill.

These are advisory skill instructions. Installation does not register always-on
rules. For enforcement, explicitly configure the relevant project `AGENTS.md`
or host rules; never rewrite personal rules as a side effect of using this skill.
