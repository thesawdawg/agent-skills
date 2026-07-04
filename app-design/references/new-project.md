# New Project Playbook (Mode B)

> Referenced from [SKILL.md](../SKILL.md).

Work the phases in order. Resist proposing solutions before you understand the
problem. STOP and wait wherever it says to ask the user. Ask 2–4 numbered
questions at a time as plain text (pi has no menu/question tool).

## Phase 1 — Intent (understand the problem)

Goal: fully understand the problem before any technology talk.

Ask questions (wording in [question-bank.md](question-bank.md)) until you can clearly state:

- **Problem** — what need does this solve? What do people do today instead?
- **Users** — who, how many, how technical, one persona or several?
- **Core jobs** — the 3–7 things a user must be able to do for v1 to be worth shipping.
- **Success** — how will the user know it works / is done?
- **Scope** — must-have vs nice-to-have vs out-of-scope.
- **Platform** — web, mobile, desktop, CLI, API, several?
- **Constraints** — timeline, budget, team size/skills, systems to integrate,
  compliance, hosting/ops, data residency.
- **Existing preferences** — any tech the user already wants or must use.

Ask in batches; **STOP and wait** after each. Do **not** propose a stack here.
When done, summarize the intent back to the user and get a yes before moving on.

## Phase 2 — Stack (choose together)

Goal: pick technology with explicit reasoning.

For each decision below that applies, present 2–3 real options with trade-offs
and a clear recommendation, then **decide with the user** (ask, STOP, wait):

- Language & runtime
- Frontend framework (if there's a UI)
- Backend framework / API style (REST / GraphQL / RPC)
- Datastore(s) — relational vs document vs KV; managed vs self-hosted
- Auth & authorization
- Hosting / deployment + CI/CD
- Key libraries for the core jobs (payments, realtime, search, …)
- Testing tooling

Weigh each on: fit for the requirements, team familiarity, ecosystem maturity,
operational cost, and room to scale. Honor the Phase 1 constraints — never
recommend something that breaks a stated limit.

Write every decision to `app-design-output/stack-decisions.md` (one row per
decision: choice, alternatives considered, why).

## Phase 3 — Specify (write the spec)

1. Read [`../templates/specifications-template.md`](../templates/specifications-template.md), fill it in, and `write` it to
   `app-design-output/specifications.md`:
   - Problem statement & goals
   - Users / personas
   - Functional requirements (numbered, testable)
   - Non-functional requirements (performance, security, accessibility, availability)
   - Data model (entities, key fields, relationships)
   - Key user flows
   - Out of scope
   - Open questions / risks
2. Review with the user; revise until they approve. Resolve or explicitly defer
   every open question.

## Phase 4 — Plan (write the plan)

1. Read [`../templates/development-plan.md`](../templates/development-plan.md), fill it in, and `write` it to
   `app-design-output/development-plan.md`:
   - **Milestones** — coherent, demoable increments.
   - **First vertical slice** — the thinnest end-to-end path that proves the
     architecture (one real feature wired UI → API → DB → deploy).
   - **Ordered tasks** with dependencies, grouped by milestone.
   - **Testing strategy** — what gets unit/integration/e2e; where
     [`/skill:dogfood`](../../dogfood/SKILL.md) fits once a UI exists.
   - **Definition of done** per milestone.
2. Confirm the plan and the immediate next action with the user. Offer to start
   the first slice, or to stop here.
