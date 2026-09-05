# coding-style: Practical Use Cases

**This is a convention, not a task skill.** Nothing "invokes" it from a chooser — it is the house standard that applies whenever code or a commit is written, and an agent is expected to read it rather than wait to be told. See [SKILL.md](SKILL.md) for the rules themselves and the [top-level skills index](../USE_CASES.md).

## When it applies

Always, when any of these is happening:

- Writing, reviewing, or refactoring code — Python especially (PEP 8, typehints, Google docstrings)
- Writing a commit message — Conventional Commits, `<type>(<scope>): <description>`
- Building anything Flask — blueprints, factory pattern, the response envelope, the security checklist
- Naming things, structuring functions and classes, or deciding how to handle an error
- Writing documentation or comments

It does **not** apply to prose, planning, or research output. A project brief is not code and gets no docstrings.

## What it settles

| Question | Answer lives in |
|---|---|
| How do I word this commit? | Conventional Commits section — types table and format rules |
| snake_case or camelCase here? | Naming conventions table |
| How do I lay out imports? | Imports — strict three-group order, absolute only |
| Do I need a docstring? | Yes — description, `Args`, `Returns`, plus `Raises` when non-obvious |
| Can I use a bare `except:`? | No. Never. Catch specific exceptions |
| Where do routes go? | Flask patterns — blueprints, never in `__init__.py` |
| What shape is an API response? | The `status`/`data`/`message` envelope, with real HTTP codes |

## How agents should use it

Read it before writing code, not after being corrected. Where it and your own habits disagree, it wins — that is the point of a house standard.

It pairs with [`workflow-rules`](../workflow-rules/USE_CASES.md), which carries the user's personal git and engineering preferences. Rough split: **`workflow-rules` is who to be, `coding-style` is how to write it.** When both speak to the same question, `workflow-rules` names the preference and this file gives the format — e.g. it says commits follow Conventional Commits, and this file has the type table.

D.A.V.E.'s `constructor` and `scribe` agents both defer to this file explicitly, so a change here changes their output.

## Worked example

A commit for a bug fix in the database layer:

```
fix(db): resolve connection pool exhaustion under load

Increase max pool size and add idle timeout to prevent connection leaks
during peak traffic.
```

Imperative subject, under 72 characters, no trailing period, scope in parentheses, body wrapped at 72 explaining *why* rather than what — the diff already shows what.
