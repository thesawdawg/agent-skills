# app-design: Practical Use Cases

This guide shows **when to invoke `app-design`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full workflow, [references/existing-project.md](references/existing-project.md) for the detailed per-phase playbook, [references/spec-and-plan.md](references/spec-and-plan.md) for the optional post-chain spec step, and [references/question-bank.md](references/question-bank.md) for question wording. This file is examples only. See also the [top-level skills index](../USE_CASES.md).

**This skill is for applications that already exist.** Analyze → verify with the user → test → triage → propose improvements. For a project that doesn't exist yet, the chain is [`ideator`](../ideator/USE_CASES.md) → [`constructor`](../constructor/USE_CASES.md) → [`datasecurer`](../datasecurer/USE_CASES.md); this skill used to carry that as a second mode and no longer does.

## Use it when

Use `app-design` when the user wants an **end-to-end pass** on an application that exists — understanding it, testing it, and deciding what to change. It's a heavier, multi-phase, question-driven engagement, not a quick fix.

Good uses:

- "Understand this codebase and tell me what's wrong with it"
- Auditing an inherited or unfamiliar project before making changes
- A full bug-finding-and-triage pass before a release
- Deciding what to fix first when there's more wrong than time

Do not use it for a single targeted bug fix or a small, well-understood change — that's just normal editing. Do not use it as a substitute for `dogfood` alone (the Test phase calls `dogfood` internally, but this skill's scope is broader: discovery, verification, triage, and recommendations *around* that QA pass). Do not use it to start a new project — redirect to `/ideator`.

For a structural map of an unfamiliar codebase without the whole lifecycle, D.A.V.E.'s `cartographer` agent is lighter and produces a diagram.

## User examples

> Understand this codebase and help me improve it.

> Audit this app, find the bugs, and tell me what to fix first.

> I inherited this project — analyze it and plan next steps with me.

> We're a week from release. Do a full pass and tell me what's actually blocking.

## Model selection cues

Select this skill when the user asks to:

- "understand this codebase and improve it"
- "analyze this app and find bugs"
- "audit and plan next steps"
- "what should I fix first"

Do not select it for a one-off bug fix with a clear, already-understood cause — just fix it. Do not select it if the user wants only a QA pass — use `dogfood` directly. Do not select it for a project with no code yet — use `ideator`.

## Inputs the model should establish

- **That code actually exists.** If the user points at existing source, or you're already inside a repo with code, confirm: "this looks like an existing app — I'll analyze it first, correct?" If they're describing something unbuilt, stop and hand off to `/ideator` rather than improvising a new-project flow.
- **What the app is supposed to do** — gathered in Discover, then *confirmed* with the user in Verify. Write it down and ask; never guess and proceed.
- **How to build, run, and test it** — without this the Test phase is theatre.

## Example model plan

1. **Discover** — map stack, entry points, structure, dependencies, data model, build/run/test commands.
2. **Verify** — write down the assumed purpose and behavior, ask the user numbered questions to confirm or correct it, save to `app-design-output/app-model.md`. Do not proceed to testing until confirmed — testing an assumed intent manufactures fake bugs.
3. **Test** — run the test battery ([references/test-battery.md](references/test-battery.md)): install, build, lint, typecheck, existing tests, then [`/skill:dogfood`](../dogfood/SKILL.md) against the running app for web apps.
4. **Triage** — present findings grouped by severity, ask which are real bugs vs. intended behavior, fix only what's approved.
5. **Enhance** — propose features and refactors with value, effort, and risk; save to `app-design-output/recommendations.md`; let the user pick.

Throughout: ask 2–4 numbered questions at a time, wait for answers, never guess past a "STOP and wait" point, and confirm before changing any code.

## Expected output

Leaves `app-design-output/app-model.md` (verified purpose and structure), a `dogfood-output/report.md` if a web app was tested, and `app-design-output/recommendations.md` (approved fixes and features with effort and risk), plus a running checklist of phases in the reply text.

If the user asks for a specification or milestone plan *after* the new-project chain has run, [references/spec-and-plan.md](references/spec-and-plan.md) adds `app-design-output/specifications.md` and `app-design-output/development-plan.md`, filled from that chain's artifacts rather than a fresh interview.

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
