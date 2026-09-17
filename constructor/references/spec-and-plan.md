# Spec & Plan Playbook

> Referenced from [SKILL.md](../SKILL.md). Question wording lives in
> the supplied brief.

Use the agreed brief, architecture, and available security constraints. These may
be user-provided or produced by other skills; no mandatory chain or output file
is required. Ask only for missing decisions. Include spec and milestones in the
primary architecture document by default, or use the separate paths below when
requested. Historical `app-design-output` specs remain supported inputs.

## Phase 1 — Specify (write the spec)

1. Read [`../templates/specifications-template.md`](../templates/specifications-template.md),
   fill it in, and `write` it to `constructor-output/specifications.md`:
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
   fill it in, and `write` it to `constructor-output/development-plan.md`:
   - **Milestones** — coherent, demoable increments.
   - **First vertical slice** — the thinnest end-to-end path that proves the
     architecture (one real feature wired UI → API → DB → deploy).
   - **Ordered tasks** with dependencies, grouped by milestone.
   - **Testing strategy** — what gets unit/integration/e2e; where
     [`/skill:dogfood`](https://github.com/thesawdawg/agent-skills/blob/main/dogfood/SKILL.md) fits once a UI exists.
   - **Definition of done** per milestone.
2. Confirm the plan and the immediate next action with the user. Offer to start
   the first slice, or to stop here.
