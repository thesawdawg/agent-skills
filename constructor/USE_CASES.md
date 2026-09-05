# constructor: Practical Use Cases

This guide shows **when to invoke `constructor`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full workflow and the `templates/` directory for the artifacts it produces. See also the [top-level skills index](../USE_CASES.md).

**`constructor` is stage two of the new-project chain:** [`ideator`](../ideator/USE_CASES.md) (sharpen the idea) → `constructor` (design the build) → [`datasecurer`](../datasecurer/USE_CASES.md) (secure it). It reads `ideator-output/project-brief.md` and writes the architecture the next stage reviews.

> Not to be confused with D.A.V.E.'s `constructor` **agent**, which implements an already-agreed plan inside an existing codebase. Same name, different job — this one designs a structure before any code exists.

## Use it when

Use `constructor` when the idea is settled and the question is how to build it: architecture, folder structure, and which dependencies to take.

Good uses:

- Turning an agreed brief into a concrete architecture and folder layout
- Choosing a backend shape — monolith, services, queues, what talks to what
- Deciding which dependencies to adopt, with the trade-offs stated
- Getting a structure agreed before anyone writes code that assumes one

Do not use it before the idea is scoped — run `/ideator` first, or you're designing for a moving target. Do not use it to write the application itself. Do not use it to design security controls; it flags security-relevant decisions for `datasecurer` rather than resolving them.

For finding a specific package rather than designing the whole dependency set, D.A.V.E.'s `module-finder` agent searches registries directly and checks advisories.

## User examples

> Design the architecture for the project brief I just wrote.

> Structure my backend — I've got the brief, now how should this be organized?

> What dependencies do I need for this, and what are the trade-offs?

> How should I organize this project so it doesn't rot in six months?

## Model selection cues

Select this skill when the user says "design the architecture", "structure my backend", "what dependencies do I need", or "how should I organize this project" — and a brief or equivalent scope already exists.

Do not select it when the idea is still unscoped (`ideator`), when the work is implementing an agreed design (D.A.V.E.'s `constructor` agent, or `codex-delegate`), or when the question is specifically about security or redundancy (`datasecurer`).

## Inputs the model should establish

| Input | Where it comes from |
|---|---|
| The project brief | `ideator-output/project-brief.md` — read it before asking anything |
| Scale and load expectations | Ask; a design for ten users differs from one for ten thousand |
| Team and maintenance reality | Who runs this after v1 constrains every choice |
| Existing infrastructure | Accounts, clouds, databases already in use are usually the right answer |
| Hard constraints | Compliance, hosting limits, language the team actually knows |

If the brief is missing, say so and offer to run `/ideator` first rather than interviewing the user twice.

## Example model plan

1. **Read the brief.** Everything you need about problem, users, and scope is there. Do not re-ask it.
2. **Ask only the gaps** — scale, team, existing infrastructure, constraints the brief flagged as UNKNOWN.
3. **Offer real options** for each major decision, two or three with honest trade-offs and a recommendation. Never present one option as the only option.
4. **Write the architecture** to `constructor-output/architecture-doc.md`, with the folder structure and dependency choices as their own artifacts.
5. **Flag security-relevant decisions** to `constructor-output/security-flags.md` rather than resolving them — that hand-off is what makes `datasecurer` useful instead of redundant.
6. **Confirm with the user**, then point at `/datasecurer`.

## Expected output

- `constructor-output/architecture-doc.md` — components, responsibilities, how they communicate
- `constructor-output/folder-structure.md` — the concrete layout
- `constructor-output/dependencies.md` — chosen packages with reasoning and rejected alternatives
- `constructor-output/security-flags.md` — decisions with security implications, handed to `datasecurer`
- `constructor-output/architecture-needs.md` — anything the brief left open that the design depends on

## Example result shape

```markdown
## Architecture — Team Habit Tracker

**Shape:** Single Flask app, server-rendered, SQLite → Postgres when it needs to be.
**Why:** Six-week deadline, one maintainer, and a read-heavy workload with
fewer than 100 users. Services would cost more than they'd buy.

| Component | Responsibility | Talks to |
|---|---|---|
| `web/` | Routes, templates, session | `core/`, `db/` |
| `core/` | Habits, streak calculation | `db/` |
| `db/` | Schema, migrations | Postgres |

**Rejected:** a JS SPA with a separate API — doubles the surface for no gain
at this scale, and the maintainer doesn't write JS.

**Flagged for DataSecurer:** session storage choice; whether habit logs count
as personal data under the team's policy.
```
