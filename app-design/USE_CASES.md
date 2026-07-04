# app-design: Practical Use Cases

This guide shows **when to invoke `app-design`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full two-mode workflow, [references/existing-project.md](references/existing-project.md) / [references/new-project.md](references/new-project.md) for the detailed per-phase playbooks, and [references/question-bank.md](references/question-bank.md) for question wording. This file is examples only. See also the [top-level skills index](../USE_CASES.md).

This skill has **two modes** — always confirm which one applies before starting anything:

- **Mode A — Existing project**: analyze → verify with user → test → triage bugs → propose enhancements
- **Mode B — New project**: intent → stack → specs → plan

## Use it when

Use `app-design` when the user wants an **end-to-end pass** on an application — either understanding and improving one that already exists, or going from an idea to a concrete spec and plan for one that doesn't exist yet. It's a heavier, multi-phase, question-driven engagement, not a quick fix.

Good uses (Mode A):

- "Understand this codebase and tell me what's wrong with it"
- Auditing an inherited/unfamiliar project before making changes
- A full bug-finding-and-triage pass before a release

Good uses (Mode B):

- Going from a rough idea to a written spec and development plan
- Choosing a stack for a new project with trade-offs laid out
- Planning out a project before writing any code

Do not use it for a single targeted bug fix or a small, well-understood change — that's just normal editing. Do not use it as a substitute for `dogfood` alone (Mode A calls `dogfood` internally for the Test phase, but app-design's scope is broader: discovery, verification, triage, and recommendations around that QA pass, not just the QA pass itself).

## User examples

**Mode A:**

> Understand this codebase and help me improve it.

> Audit this app, find the bugs, and tell me what to fix first.

> I inherited this project — analyze it and plan next steps with me.

**Mode B:**

> Help me start a new project — I have an idea but nothing built yet.

> Design a new app with me: a habit tracker for teams.

> Plan out development of a small internal admin tool.

## Model selection cues

Select this skill when the user asks to:

- "understand this codebase and improve it"
- "analyze this app and find bugs"
- "audit and plan next steps"
- "help me start a new project" / "design a new app with me"
- "plan out development of X"

Do not select it for a one-off bug fix with a clear, already-understood cause — just fix it. Do not select it if the user wants only a QA pass and nothing else — use `dogfood` directly instead.

## Inputs the model should establish

Before starting either mode:

- **Which mode applies** — if the user points at existing source, or you're already inside a repo with code, confirm "this looks like an existing app — I'll analyze it first, correct?" If they're describing something unbuilt, confirm new-project mode. If genuinely unclear, ask directly and wait.

Mode A specifics, gathered through the Discover phase and confirmed with the user in Verify (not assumed):

- What the app is actually supposed to do (write it down, then ask — don't guess and proceed)
- How to build/run/test it

Mode B specifics, gathered through the Intent phase before any stack talk:

- The problem, target users, scope, and constraints

## Example model plan

**Mode A — Existing project:**

1. **Discover** — map stack, entry points, structure, dependencies, data model, build/run/test commands.
2. **Verify** — write down the assumed purpose/behavior, ask the user numbered questions to confirm or correct it, save to `app-design-output/app-model.md`. Do not proceed to testing until confirmed.
3. **Test** — run the test battery ([references/test-battery.md](references/test-battery.md)): install, build, lint, typecheck, existing tests, then [`/skill:dogfood`](../dogfood/SKILL.md) against the running app for web apps.
4. **Triage** — present findings grouped by severity, ask which are real bugs vs. intended behavior, fix only what's approved.
5. **Enhance** — propose features/refactors with value, effort, and risk; save to `app-design-output/recommendations.md`; let the user pick.

**Mode B — New project:**

1. **Intent** — ask until problem, users, scope, and constraints are clear. No stack talk yet. Confirm the summary back.
2. **Stack** — offer 2-3 options with trade-offs and a recommendation for each major decision (language, framework, datastore, hosting, auth, key libraries); decide together; save to `app-design-output/stack-decisions.md`.
3. **Specify** — fill `templates/specifications-template.md` into `app-design-output/specifications.md`; review and revise with the user.
4. **Plan** — fill `templates/development-plan.md` into `app-design-output/development-plan.md`; confirm the next action.

Throughout both modes: ask 2-4 numbered questions at a time, wait for answers, never guess past a "STOP and wait" point, and confirm before changing any code.

## Expected output

**Mode A** leaves: `app-design-output/app-model.md` (verified purpose/structure), a `dogfood-output/report.md` if a web app was tested, `app-design-output/recommendations.md` (approved fixes/features with effort and risk).

**Mode B** leaves: `app-design-output/stack-decisions.md`, `app-design-output/specifications.md`, `app-design-output/development-plan.md`.

Both modes leave a running checklist of phases in the reply text as they're completed.

## Example result shape

```markdown
## Verified App Model (app-design-output/app-model.md)

**Purpose:** Internal invoicing tool for the finance team — confirmed with user.
**Key flows:** Create invoice → send for approval → mark paid.
**Build/run/test:** `npm install && npm run dev`; tests via `npm test` (Jest).

## Triage (from dogfood-output/report.md)

| Severity | Issue | User verdict |
|---|---|---|
| High | Save button disabled after edit | Real bug — fix now |
| Low | Footer link 404s | Known, deprioritized |

**Recommendations (app-design-output/recommendations.md):**
1. Fix save-button validation bug — Effort: S, Risk: Low, Value: High
2. Add bulk invoice export — Effort: M, Risk: Low, Value: Medium
```
