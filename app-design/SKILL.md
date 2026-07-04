---
name: app-design
description: Use when the user wants to design, understand, audit, or plan an application end-to-end. Triggers on "understand this codebase and improve it", "analyze this app and find bugs", "audit and plan next steps", "help me start a new project", "design a new app with me", "plan out development of X". Two modes — existing project (analyze → verify → test → triage → enhance) and new project (intent → stack → specs → plan). Uses the dogfood skill for runtime QA.
license: MIT
metadata:
  version: 2.0.0
  argument-hint: "[project-path-or-idea]"
allowed-tools: read, write, edit, bash, grep, find, ls
---

# App Design — Design & Build Lifecycle (pi edition)

This skill walks the user through designing or improving an app. It is
**question-driven**: you ask, the user answers, you act. There are two modes.
**Always confirm which mode applies before you start.**

- **Existing project** — code already exists. Analyze → verify with user → test
  → triage bugs → propose improvements.
- **New project** — only an idea. Ask about intent → choose a stack together →
  write a spec → write a plan.

See also: [USE_CASES.md](USE_CASES.md) for trigger phrases and a worked
example, and the [top-level skills index](../USE_CASES.md). Mode A's Test
phase calls [`dogfood`](../dogfood/SKILL.md) directly for web apps.

## How to ask questions (important — read this)

pi has **no special question tool and no menu popups**. You ask questions as
plain text in your reply. Do it like this:

- Ask **2–4 questions at a time**, numbered. Wait for answers. Then ask more.
- Keep each question tied to one real decision. No "tell me everything".
- After the user answers, briefly say what you concluded, then continue.
- **STOP and wait** at every point that says "ask the user". Do not guess
  answers and keep going.

Draw question wording from [references/question-bank.md](references/question-bank.md).

## Rules for both modes

1. **Verify assumptions** — don't act on a guess; ask.
2. **Show your reasoning** — when you propose a stack/fix/refactor, give the
   trade-offs and why. Never present one option as the only option.
3. **Confirm before changing code** — list the change, get a yes, then edit.
4. **Write artifacts to disk** with the `write` tool, under
   `./app-design-output/` so they survive the session.

## Step 0 — Pick the mode

1. If the user points at a folder/repo, or you are inside one with source files,
   it is probably **existing project**. Confirm in one line:
   "This looks like an existing <type> app — I'll analyze it first. Correct?"
2. If the user describes something to build that doesn't exist yet → **new project**.
3. If unclear, ask: "Are we improving an existing codebase, or starting a new
   project from scratch?" — then STOP and wait.

Then make the output folder:

```sh
mkdir -p app-design-output
```

---

## Mode A — Existing Project

Full step-by-step playbook: read [references/existing-project.md](references/existing-project.md).
Question wording: [references/question-bank.md](references/question-bank.md).

The five phases (do them in order, do not jump ahead):

1. **Discover** — Map the code. Detect stack, entry points, structure,
   dependencies, data model, and how to build/run/test. Use `ls`, `find`,
   `grep`, and `read` (see playbook for the exact commands).
2. **Verify** — Write down what you THINK the app does, then ask the user
   numbered questions to confirm or correct it. Save the agreed truth to
   `app-design-output/app-model.md`. **Do not test until the user confirms.**
3. **Test** — Run the test battery in [references/test-battery.md](references/test-battery.md): install,
   build, lint, typecheck, run existing tests, then runtime QA. For web apps,
   run [`/skill:dogfood`](../dogfood/SKILL.md) against the running app. Collect every bug.
4. **Triage** — Show findings grouped by severity. Ask the user which are real
   bugs vs intended behavior. Fix ONLY what they approve.
5. **Enhance** — Propose new features and refactors, each with value, effort,
   and risk. Save to `app-design-output/recommendations.md`. Let the user pick.

## Mode B — New Project

Full step-by-step playbook: read [references/new-project.md](references/new-project.md).
Question wording: [references/question-bank.md](references/question-bank.md).

The four phases (in order):

1. **Intent** — Ask until the problem, users, scope, and constraints are clear.
   Do NOT propose a stack yet. Summarize intent back and get agreement.
2. **Stack** — For each big choice (language, framework, datastore, hosting,
   auth, key libraries), offer 2–3 options with trade-offs + a recommendation,
   and **decide together**. Save to `app-design-output/stack-decisions.md`.
3. **Specify** — Fill [templates/specifications-template.md](templates/specifications-template.md) into
   `app-design-output/specifications.md`. Review with the user; revise.
4. **Plan** — Fill [templates/development-plan.md](templates/development-plan.md) into
   `app-design-output/development-plan.md`. Confirm the next action with the user.

---

## Artifacts (write these with the `write` tool)

| File | Mode | Purpose |
|------|------|---------|
| `app-design-output/app-model.md` | A | Verified purpose, structure, flows |
| `dogfood-output/report.md` | A | Bug report from the dogfood QA run |
| `app-design-output/recommendations.md` | A | Approved fixes, features, refactors |
| `app-design-output/stack-decisions.md` | B | Stack choices + reasoning |
| `app-design-output/specifications.md` | B | Full spec |
| `app-design-output/development-plan.md` | B | Milestones + ordered tasks |

## Reminders for staying on track

- Keep a short checklist of the phases in your reply and tick them off as you
  go (pi has no to-do tool, so just write the list in text).
- Mode A: never skip Verify — testing the wrong assumed intent makes fake bugs.
- Mode B: never skip Intent — a stack chosen before requirements is a guess.
- If [`/skill:dogfood`](../dogfood/SKILL.md) or its browser script isn't usable, fall back to the
  non-browser runtime checks in [references/test-battery.md](references/test-battery.md).
