# Skills Index: Practical Use Cases

This is the chooser for everything in this repo — 13 skills, one orchestrator plugin (`dave`), and three standing conventions. `dogfood`, `dependabot-validator` and `pr-grill-me` are written to the portable four-tool baseline (Read/Write/Edit/Bash) and run under any harness; the rest assume a richer toolset — a real headless browser, subagents, `WebSearch`. The separate [`pi-skills/`](pi-skills/USE_CASES.md) collection holds harness-portable skills adapted from hermes-agent.

Each skill has its own `USE_CASES.md` with full detail: trigger phrases, inputs to establish, an example model plan, and a sample output. **This file is a chooser and cross-reference, not a duplicate** — when a skill's own file changes, come back here only if the one-line summary or the table needs updating.

Repository layout rules live in [STRUCTURE.md](STRUCTURE.md).

## How to use this guide

A user doesn't need to name a skill exactly. Match intent using:

1. **The target** — a codebase, a PR, a running app, an idea for something unbuilt.
2. **The goal** — implement, audit, QA, validate a dependency bump, self-review, plan.
3. **Constraints** — authorization, scope, sandbox/write permissions, what must not happen.

For example:

> Delegate the CSV export endpoint to Codex, then dogfood it on localhost before I open the PR.

That maps to `codex-delegate` → `dogfood`, in that order — see "Combining skills" below.

## Quick chooser

| User goal | Skill |
|---|---|
| Sharpen a raw idea into a scoped project brief | [`ideator`](ideator/USE_CASES.md) |
| Turn a brief into architecture, folder structure, and dependencies | [`constructor`](constructor/USE_CASES.md) |
| Threat-model a design and plan backups and redundancy | [`datasecurer`](datasecurer/USE_CASES.md) |
| Understand, audit, and improve a codebase that already exists | [`app-design`](app-design/USE_CASES.md) |
| Explore a running web app and report real bugs with evidence | [`dogfood`](dogfood/USE_CASES.md) |
| Run a WCAG conformance audit of a live web app | [`accessibility-audit`](accessibility-audit/USE_CASES.md) |
| Delegate substantial implementation to Codex as an external subagent | [`codex-delegate`](codex-delegate/USE_CASES.md) |
| Offload bulk text tasks to a local or remote Ollama model, in parallel | [`ollama-delegate`](ollama-delegate/USE_CASES.md) |
| Check whether a Dependabot PR is safe to merge | [`dependabot-validator`](dependabot-validator/USE_CASES.md) |
| Get a self-review reality check on your own PR | [`pr-grill-me`](pr-grill-me/USE_CASES.md) |
| Sync recent commits to a docs repo or an in-repo docs tree | [`commit-documentor`](commit-documentor/USE_CASES.md) |
| Write or run tests in the established Flask pytest framework | [`flask-tests`](flask-tests/USE_CASES.md) |
| Decide what to work on, stay on it, and orchestrate the other agents | [`dave`](dave/USE_CASES.md) *(plugin)* |

Conventions are **not** in this table — they are read automatically, never chosen. See [Conventions](#conventions) below.

---

# Starting something new

Three stages, chained by artifacts. Run them in order; each reads what the last one wrote.

## `ideator`

Asks questions until the problem, the users, and the scope are clear, then writes a project brief. No code, no stack, no architecture — just the idea, sharpened.

> I have an idea for a habit tracker for teams — help me scope it.

Produces `ideator-output/project-brief.md`. Not for a project that already exists (`app-design`), and not for a hunch too vague to state in a sentence — D.A.V.E.'s `brainstormer` widens that first. See [`ideator/USE_CASES.md`](ideator/USE_CASES.md).

## `constructor`

Reads the brief and designs the build: architecture, folder structure, dependency choices with trade-offs. Flags security-relevant decisions for the next stage rather than resolving them.

> Design the architecture for the brief I just wrote.

Distinct from D.A.V.E.'s `constructor` **agent**, which implements an agreed plan inside existing code. See [`constructor/USE_CASES.md`](constructor/USE_CASES.md).

## `datasecurer`

Reads the brief and the architecture, then produces the threat model, security plan, and redundancy plan — and names where the architecture and the security requirements genuinely conflict.

> Threat model this before we build it, and tell me what happens when the database host dies.

Not a penetration test of a running system — that's [`web-pentest`](web-pentest/SKILL.md). See [`datasecurer/USE_CASES.md`](datasecurer/USE_CASES.md).

---

# Working an existing codebase

## `app-design`

Question-driven lifecycle for an app that already exists: discover → verify with the user → test → triage → propose improvements. Calls `dogfood` internally for runtime QA on web apps.

> Understand this codebase and help me improve it.

Not for a single well-understood bug fix, not a substitute for `dogfood` alone, and no longer a new-project skill — that work moved to the chain above. For a structural map without the whole lifecycle, D.A.V.E.'s `cartographer` agent is lighter and produces a diagram. See [`app-design/USE_CASES.md`](app-design/USE_CASES.md).

## `dogfood`

Drives a real headless browser against a live app: navigates, clicks, fills forms, captures console errors and screenshots, produces a severity-ranked bug report.

> Dogfood my app at `http://localhost:5173`. Try creating, editing, and deleting a project.

Not for a static diff with nothing running — see `pr-grill-me`. Not for a WCAG-specific check — see `accessibility-audit`, which shares this driver. See [`dogfood/USE_CASES.md`](dogfood/USE_CASES.md).

## `accessibility-audit`

WCAG 2.2 (AA and above) conformance testing of a live web app: automated `axe-core` scanning cross-referenced against a WCAG success-criteria table, plus manual checks for what automated tools structurally can't verify — keyboard operability, focus order, alt-text quality. Shares `dogfood`'s browser driver rather than duplicating it.

> Run a WCAG AA audit on our checkout flow before we ship.

Not for general bug-hunting with no accessibility framing — use `dogfood`. See [`accessibility-audit/USE_CASES.md`](accessibility-audit/USE_CASES.md).

---

# Delegating work

## `codex-delegate`

Runs the Codex CLI as a single, sequential external subagent — one continuous thread resumed across steps, so Claude's own context only ever holds Codex's final replies. For medium-to-high importance work worth a second model's dedicated attention on the real files.

> Delegate the rate-limiter refactor to Codex — split the middleware into its own module and add tests.

Not for a one-line fix, and not for running things concurrently; it's deliberately sequential. See [`codex-delegate/USE_CASES.md`](codex-delegate/USE_CASES.md).

## `ollama-delegate`

Offloads text tasks to a local or remote Ollama model over its HTTP API — one-shot (`run`) or multi-turn (`start`/`send`). Unlike `codex-delegate`, independent calls can run in parallel.

> Use Ollama to summarize each of these 12 changelog files — run them in parallel.

Not for tasks needing deep reasoning, tool use, or file edits — the model only ever sees prompt text. See [`ollama-delegate/USE_CASES.md`](ollama-delegate/USE_CASES.md).

---

# Shipping

## `dependabot-validator`

Fetches a Dependabot PR, diffs the actual dependency change, scans the codebase for real usage of the updated package, researches breaking changes, runs tests against the PR state, and returns a merge verdict.

> Validate Dependabot PR 42 before I merge it.

Not for a general PR review or a hand-written dependency bump. See [`dependabot-validator/USE_CASES.md`](dependabot-validator/USE_CASES.md).

## `pr-grill-me`

Interviews the *author* about their own PR's intent one question at a time, then holds those answers against the actual diff to surface gaps. Requires the author present to answer.

> Grill me on PR 73 before I ask for review.

Not for reviewing someone else's PR. See [`pr-grill-me/USE_CASES.md`](pr-grill-me/USE_CASES.md).

## `commit-documentor`

Runs after committing: reviews unpushed commits, classifies each against user-defined rules, finds affected pages via a committed doc index, drafts edits for approval, and publishes on approval. Two modes — `repo` (separate docs repository, opens a PR) and `local` (in-repo `docs/` tree, committed but never pushed).

> I just committed the new export endpoint — check whether the docs repo needs updating.

Not for a one-off README edit, and not for reviewing the commits for bugs. See [`commit-documentor/USE_CASES.md`](commit-documentor/USE_CASES.md).

---

# Project-specific

## `flask-tests`

Documents one Flask project's established two-tier pytest framework — fast SQLite unit tests plus MySQL integration tests, `importlib` import mode, path-based auto-marking. A house-rules reference, not general Flask advice.

> Add tests for the SOAP classification worker.

Only useful inside a repo that already has that framework. See [`flask-tests/USE_CASES.md`](flask-tests/USE_CASES.md).

---

# Orchestration

## `dave` *(plugin)*

D.A.V.E. — Digital Assistant for Various Endeavors. An orchestrator, not a doer: he keeps one ranked priority list in `~/.dave/priorities.md` spanning Redmine tickets and hand-pasted kanban boards, notices when the session drifts off it, and delegates to a nine-agent roster (Quartermaster, Cartographer, Scout, Brainstormer, Ideator, ModuleFinder, Constructor, Critic, Scribe).

> What should I actually be working on? — and tell me if I wander off it.

Unlike everything else here, this is a **plugin**: it ships agents, `/dave:*` commands, and a SessionStart hook alongside its skill. It also runs under the [pi](https://pi.dev) harness with those pieces remapped — see [`dave/INSTALL-PI.md`](dave/INSTALL-PI.md). Reach for it when the question is *which work and in what order*; reach for the other skills when the question is the work itself. See [`dave/USE_CASES.md`](dave/USE_CASES.md).

---

# Conventions

These three are **not skills a user picks**. They are standing standards an agent reads at the start of work and applies by default. They never appear in the chooser table, and selecting one as if it were a task is a mis-read.

| Convention | Applies when | Settles |
|---|---|---|
| [`coding-style`](coding-style/USE_CASES.md) | Writing, reviewing, or refactoring code; writing a commit | PEP 8, typehints, Google docstrings, Conventional Commits format, Flask patterns |
| [`workflow-rules`](workflow-rules/USE_CASES.md) | Every coding and git task | Never push; no `Co-Authored-By` unless asked; ask 1–5 questions first; DRY |
| [`memory`](memory/USE_CASES.md) | Start of any non-trivial task, and whenever a durable fact is learned | Where memory lives (`~/.agents/memory/`), what's worth saving, and in what format |

Rough split between the first two: **`workflow-rules` is who to be, `coding-style` is how to write it.** Where both speak to one question, `workflow-rules` names the preference and `coding-style` gives the format.

---

## Combining skills

These skills are deliberately narrow — real workflows often chain them.

**Idea → design → build → verify:**
1. `ideator` sharpens the idea into `ideator-output/project-brief.md`.
2. `constructor` turns the brief into an architecture and dependency set.
3. `datasecurer` threat-models it and plans redundancy.
4. `codex-delegate` implements the first vertical slice.
5. `dogfood` QAs it once there's a UI.

> Scope this idea with me, design it, threat model it, then build the first slice.

**Existing-codebase audit end to end:**
1. `app-design` discovers, verifies, and tests the app (calling `dogfood` internally), then triages and proposes fixes.
2. `codex-delegate` implements the approved fixes.
3. `dogfood` re-runs to confirm, if the change is UI-facing.

**Dependency bump with a real fix needed:**
1. `dependabot-validator` finds a breaking change and the specific call sites affected.
2. `codex-delegate` implements the required fix.
3. `pr-grill-me` for a final self-review before merging.

**Implement → document:**
1. `codex-delegate` (or ordinary editing) implements the change and it gets committed.
2. `commit-documentor` reads those commits and opens a docs PR for the ones that changed user-visible behavior.
3. `pr-grill-me` on the code PR, with the docs PR already linked.

**Accessibility fix cycle:**
1. `accessibility-audit` finds WCAG violations with specific success criteria and affected elements.
2. `codex-delegate` implements the fixes.
3. `accessibility-audit` re-runs against the same pages to confirm.

**Priority-driven day (D.A.V.E. above the rest):**
1. `dave` reconciles Redmine and your board into one ranked list, and you set focus on the top item.
2. D.A.V.E.'s `cartographer` maps the repo if it's unfamiliar; `scout` briefs the specific unknowns.
3. `codex-delegate` (or D.A.V.E.'s `constructor` agent) implements the agreed approach.
4. `dogfood` or `accessibility-audit` verifies it live, if it's UI-facing.
5. D.A.V.E.'s `scribe` drafts the ticket comment and time entry — you approve each write before it goes out.

> Reconcile my board with Redmine, put me on the top item, and at the end of the day write up what I actually did for the ticket.

Don't chain skills just because they exist — each step should still pass the "is this substantial enough to warrant it" bar from that skill's own `USE_CASES.md`.

---

## Guidance for users

Better results come from stating, up front:

- The target (URL, PR number, repo, or idea)
- The outcome you actually care about
- What the model may and may not do (real purchases, destructive actions, sandbox/write permissions)
- Any test accounts, credentials, or constraints already known

Weak request:

> Fix up this PR.

Better request:

> Grill me on PR 73 — focus on the retry logic, not formatting. If you find something concrete to change, delegate the fix to Codex and re-check the diff before telling me it's done.

## Guidance for models

1. **Read the conventions first.** `workflow-rules`, `coding-style` and `memory` apply by default and are not things the user has to ask for.
2. Match the skill to the request's actual mechanic, not just its topic — `pr-grill-me` needs the author present; `dependabot-validator` needs a Dependabot commit message; `codex-delegate` needs the user to actually want a second model involved.
3. Watch the two name collisions: `ideator` and `constructor` exist both as top-level skills (new-project chain) and as D.A.V.E. agents (work inside existing code). They are different jobs.
4. Don't chain skills reflexively — each one has its own bar for "is this worth it."
5. Preserve user-stated constraints and scope across every step of a chain.
6. Read each skill's own `SKILL.md` for operational detail — this file and each `USE_CASES.md` are for selection and calibration, not step-by-step execution.
