# Top-Level Skills: Practical Use Cases

This is the index for the top-level skills in this repo. `dogfood`, `dependabot-validator`, and `pr-grill-me` are written to the portable four-tool baseline (Read/Write/Edit/Bash) and run under any harness; the rest assume a richer toolset — a real headless browser, `Agent` subagents, `WebSearch`, etc. The separate `pi-skills/` collection holds harness-portable skills adapted from hermes-agent (see `pi-skills/USE_CASES.md` for those).

Each skill below has its own `USE_CASES.md` with full detail: trigger phrases, inputs to establish, an example model plan, and a sample output. **This file is a chooser and cross-reference, not a duplicate** — when a skill's own file changes, come back here only if the one-line summary or chooser table needs updating.

## How to use this guide

A user doesn't need to name a skill exactly. Match intent to a skill using:

1. **The target** — a codebase, a PR, a running app, an idea for something unbuilt.
2. **The goal** — implement, audit, QA, validate a dependency bump, self-review, plan.
3. **Constraints** — authorization, scope, sandbox/write permissions, what must not happen.

For example:

> Delegate the CSV export endpoint to Codex, then dogfood it on localhost before I open the PR.

That maps to `codex-delegate` → `dogfood`, in that order — see "Combining skills" below.

## Quick skill chooser

| User goal | Skill |
|---|---|
| Delegate a substantial implementation, refactor, or investigation to Codex as a single external subagent | [`codex-delegate`](codex-delegate/USE_CASES.md) |
| Offload tasks to a local or remote Ollama model, including running several in parallel | [`ollama-delegate`](ollama-delegate/USE_CASES.md) |
| Explore a running web app and report real bugs backed by screenshots and console evidence | [`dogfood`](dogfood/USE_CASES.md) |
| Check whether a Dependabot PR is safe to merge given this project's actual usage of the package | [`dependabot-validator`](dependabot-validator/USE_CASES.md) |
| Get a self-review reality check on your own PR before requesting real review | [`pr-grill-me`](pr-grill-me/USE_CASES.md) |
| Design, audit, or plan an application end-to-end — existing codebase or new idea | [`app-design`](app-design/USE_CASES.md) |
| Run a WCAG conformance audit of a live web app, citing specific success criteria | [`accessibility-audit`](accessibility-audit/USE_CASES.md) |
| Check whether commits you just made need documentation updates, and publish them to a docs repo (or an in-repo docs tree) | [`commit-documentor`](commit-documentor/USE_CASES.md) |

---

## 1. `codex-delegate`

Runs the Codex CLI as a single, sequential external subagent — one continuous Codex thread resumed across steps, so Claude's own context only ever holds Codex's final replies. For medium-to-high importance work worth a second model's dedicated attention on the real files.

> Delegate the rate-limiter refactor to Codex — have it split the middleware into its own module and add tests.

Not for a one-line fix, and not for running things concurrently — it's deliberately sequential. See [`codex-delegate/USE_CASES.md`](codex-delegate/USE_CASES.md).

## 2. `ollama-delegate`

Offloads text tasks to a local or remote Ollama model over its HTTP API — one-shot (`run`) or multi-turn (`start`/`send`). Unlike `codex-delegate`, independent one-shot calls can run in parallel, since Ollama's daemon serves concurrent requests.

> Use Ollama to summarize each of these 12 changelog files — run them in parallel.

Not for tasks needing deep reasoning, tool use, or file edits — the model only ever sees prompt text, no filesystem or shell access. See [`ollama-delegate/USE_CASES.md`](ollama-delegate/USE_CASES.md).

## 3. `dogfood`

Drives a real headless browser against a live app: navigates, clicks, fills forms, captures console errors and screenshots, produces a severity-ranked bug report.

> Dogfood my app at `http://localhost:5173`. Try creating, editing, and deleting a project.

Not for a static diff with nothing running — see `pr-grill-me` instead. Not for a WCAG-specific conformance check — see `accessibility-audit`, which shares this driver but scans against WCAG success criteria. See [`dogfood/USE_CASES.md`](dogfood/USE_CASES.md).

## 4. `dependabot-validator`

Fetches a Dependabot PR over SSH, diffs the actual dependency change, scans the codebase for real usage of the updated package, researches breaking changes, runs tests against the PR state, and returns a merge verdict.

> Validate Dependabot PR 42 before I merge it.

Not for a general PR review, or a hand-written (non-Dependabot) dependency bump — see [`dependabot-validator/USE_CASES.md`](dependabot-validator/USE_CASES.md).

## 5. `pr-grill-me`

Interviews the *author* about their own PR's intent one question at a time, then holds those answers up against the actual diff to surface gaps. Requires the author present to answer — it's not a third-party review.

> Grill me on PR 73 before I ask for review.

Not for reviewing someone else's PR, and not for a Dependabot bump specifically. See [`pr-grill-me/USE_CASES.md`](pr-grill-me/USE_CASES.md).

## 6. `app-design`

Question-driven, end-to-end design/audit lifecycle with two modes: **existing project** (discover → verify → test → triage → enhance) or **new project** (intent → stack → specs → plan). Calls `dogfood` internally for runtime QA on web apps in Mode A.

> Understand this codebase and help me improve it.
> Help me start a new project — I have an idea but nothing built yet.

Not for a single well-understood bug fix, and not a substitute for `dogfood` alone if all the user wants is a QA pass. See [`app-design/USE_CASES.md`](app-design/USE_CASES.md).

## 7. `accessibility-audit`

WCAG 2.2 (AA and above) conformance testing of a live web app: automated `axe-core` scanning — the same actively-maintained rule engine behind Lighthouse/Deque — cross-referenced against a WCAG success-criteria table, plus manual checks for what automated tools structurally can't verify (keyboard operability, focus order, alt-text quality). Shares `dogfood`'s browser driver rather than duplicating it.

> Run a WCAG AA audit on our checkout flow before we ship.

Not for general bug-hunting QA with no accessibility framing — use `dogfood` for that. See [`accessibility-audit/USE_CASES.md`](accessibility-audit/USE_CASES.md).

## 8. `commit-documentor`

Runs after committing: reviews the unpushed commits, classifies each against user-defined rules (chore commits and dependency bumps typically excluded), finds the affected pages via a committed local doc index, drafts the edits for approval, and on approval publishes them. Two modes — `repo` (docs in a separate repository; opens a PR there) and `local` (no separate docs repo; creates and maintains a `docs/` tree in this repo, committed but never pushed).

> I just committed the new export endpoint — check whether the docs repo needs updating.

Not for a one-off README edit with no commit-driven review, and not for reviewing the commits themselves for bugs. See [`commit-documentor/USE_CASES.md`](commit-documentor/USE_CASES.md).

---

## Combining skills

These skills are deliberately narrow — real workflows often chain them.

**Design → implement → verify → self-review:**
1. `app-design` (Mode B) to turn an idea into a spec and plan, or (Mode A) to produce approved recommendations.
2. `codex-delegate` to implement an approved recommendation or plan item.
3. `dogfood` to QA the resulting feature live.
4. `pr-grill-me` for a self-review reality check before requesting real review.

> Plan out the billing settings feature with me, then delegate the implementation to Codex, dogfood it on localhost, and grill me on the diff before I open the PR.

**Dependency bump with a real fix needed:**
1. `dependabot-validator` finds a breaking change and specific call sites affected.
2. `codex-delegate` implements the required fix.
3. `pr-grill-me` for a final self-review before merging.

**Existing-codebase audit end to end:**
1. `app-design` (Mode A) discovers, verifies, and tests the app (calling `dogfood` internally), then triages and proposes fixes.
2. `codex-delegate` implements the approved fixes.
3. `dogfood` re-runs to confirm the fix, if the change is UI-facing.

**Implement → document:**
1. `codex-delegate` (or ordinary editing) implements the change and it gets committed.
2. `commit-documentor` reads those commits and opens a docs-repo PR for the ones that changed user-visible behavior.
3. `pr-grill-me` on the code PR, with the docs PR already linked.

> Delegate the exports endpoint to Codex, then once I've committed, run commit-documentor so the docs repo PR is open before I ask for review.

**Accessibility fix cycle:**
1. `accessibility-audit` finds WCAG violations with specific success criteria and affected elements.
2. `codex-delegate` implements the fixes.
3. `accessibility-audit` re-runs against the same pages to confirm the violations are resolved.

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

1. Match the skill to the request's actual mechanic, not just its topic — `pr-grill-me` needs the author present; `dependabot-validator` needs a Dependabot commit message; `codex-delegate` needs the user to actually want a second model involved.
2. Don't chain skills reflexively — each one has its own bar for "is this worth it."
3. Preserve user-stated constraints and scope across every step of a chain.
4. Read each skill's own `SKILL.md` for the operational detail — this file and each skill's `USE_CASES.md` are for selection and calibration, not step-by-step execution.
