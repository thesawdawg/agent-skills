# Spec & Plan Playbook

> Referenced from [SKILL.md](../SKILL.md). Question wording lives in
> [question-bank.md](question-bank.md).

Two phases that turn an agreed design into a written specification and an ordered
plan of work.

**This is not a new-project playbook.** Intent and stack selection belong to the
[`ideator`](../../ideator/SKILL.md) → [`constructor`](../../constructor/SKILL.md) →
[`datasecurer`](../../datasecurer/SKILL.md) chain, which produces a project brief,
an architecture, dependency choices, and a security plan. This file picks up where
that chain stops, because it does not produce a spec or a milestone plan.

**Read the chain's artifacts before you start.** `ideator-output/project-brief.md`,
`constructor-output/architecture-doc.md` and `constructor-output/dependencies.md`
already contain most of what a spec needs. The user has answered these questions
once; do not interview them again. Ask only about what the artifacts genuinely do
not cover, and say which gap you are filling.

If those artifacts do not exist, stop and say so — a spec written without an agreed
brief and architecture is a guess, and the chain is cheap to run first.

## Phase 1 — Specify (write the spec)

1. Read [`../templates/specifications-template.md`](../templates/specifications-template.md),
   fill it in, and `write` it to `app-design-output/specifications.md`:
   - Problem statement & goals
   - Users / personas
   - Functional requirements (numbered, testable)
   - Non-functional requirements (performance, security, accessibility, availability)
   - Data model (entities, key fields, relationships)
   - Key user flows
   - Out of scope
   - Open questions / risks
2. Carry the security and redundancy constraints from
   `datasecurer-output/security-plan.md` into the non-functional requirements
   rather than re-deriving them.
3. Review with the user; revise until they approve. Resolve or explicitly defer
   every open question.

## Phase 2 — Plan (write the plan)

1. Read [`../templates/development-plan.md`](../templates/development-plan.md),
   fill it in, and `write` it to `app-design-output/development-plan.md`:
   - **Milestones** — coherent, demoable increments.
   - **First vertical slice** — the thinnest end-to-end path that proves the
     architecture (one real feature wired UI → API → DB → deploy).
   - **Ordered tasks** with dependencies, grouped by milestone.
   - **Testing strategy** — what gets unit/integration/e2e; where
     [`/skill:dogfood`](../../dogfood/SKILL.md) fits once a UI exists.
   - **Definition of done** per milestone.
2. Confirm the plan and the immediate next action with the user. Offer to start
   the first slice, or to stop here.
