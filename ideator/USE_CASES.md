# ideator: Practical Use Cases

This guide shows **when to invoke `ideator`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full workflow and [templates/project-brief.md](templates/project-brief.md) for the artifact it produces. See also the [top-level skills index](../USE_CASES.md).

**`ideator` is stage one of the new-project chain:** `ideator` (sharpen the idea) → [`constructor`](../constructor/USE_CASES.md) (design the build) → [`datasecurer`](../datasecurer/USE_CASES.md) (secure it). Each stage writes an artifact the next one reads, so running them out of order costs you the handoff.

## Use it when

Use `ideator` when someone has an idea and needs it sharp enough to build from. It asks questions until the problem, the users, and the scope are clear, then writes a project brief.

Good uses:

- Turning "I want something for tracking invoices" into a scoped v1
- Deciding what a first version does and, more importantly, does not do
- Getting a written brief before anyone argues about frameworks
- Rescuing a project whose scope has quietly become everything

Do not use it for a project that already exists — that's [`app-design`](../app-design/USE_CASES.md). Do not use it when the idea is still a hunch you can't state in a sentence; D.A.V.E.'s `brainstormer` agent widens a vague notion first, then hands here. Do not expect code, a stack recommendation, or a security design — those are deliberately out of scope and belong to later stages.

## User examples

> Help me plan a new project.

> I have an idea for a habit tracker for teams — help me scope it.

> Wireframe my project before I start building.

> Clarify what I'm actually building here, because I keep adding things.

## Model selection cues

Select this skill when the user says "help me plan", "I have an idea for", "wireframe my project", "clarify what I'm building", or "scope a new project" — and there is no code yet.

Do not select it when the user wants architecture or dependencies (that's `constructor`), when they want the idea widened rather than narrowed (that's `brainstormer`), or when a codebase already exists.

## Inputs the model should establish

Gathered *through the questions*, not assumed up front:

| Input | Why it matters |
|---|---|
| The problem, in one sentence | Everything downstream is scoped against it |
| Who the users are | "Everyone" is not an answer and produces mush |
| What they do today instead | If there's no workaround, the need may be assumed rather than observed |
| Hard constraints | Platform, deadline, compliance, budget — constraints sharpen ideas |
| What v1 explicitly excludes | The boundary is what stops scope creep before there is scope |

## Example model plan

1. **Ask, in small batches.** Two to four numbered questions at a time; wait for answers. Never dump a questionnaire.
2. **Play back what you heard** before moving on. A misread caught here costs a sentence; caught later it costs the brief.
3. **Push on the vague parts.** "Users can manage their data" is not a capability. Ask what the user actually does and what happens.
4. **Name the v1 boundary** — the 3–7 core capabilities, and an explicit out-of-scope list.
5. **Write the brief** to `ideator-output/project-brief.md` from the template. Fill every section; write `UNKNOWN — flagged for <stage>` rather than guessing.
6. **Read it back in summary**, get agreement, then point at `/constructor`.

Never propose a stack, write code, or design security — say which stage owns each and keep going.

## Expected output

`ideator-output/project-brief.md`: problem statement, target users, 3–7 core v1 capabilities as actions, explicit out-of-scope list, constraints table, and any open questions flagged for a later stage.

## Example result shape

```markdown
# Project Brief — Team Habit Tracker

## Problem statement
Small teams lose shared habits because nobody sees whether anyone else is keeping them.

## Core capabilities (v1)
1. **Join a team habit** — pick from the team's list, commit to a cadence
2. **Log a day** — one tap, from the phone, in under five seconds
3. **See the team's streak** — not individual shaming, the collective run

## Explicitly out of scope
- Individual analytics and charts
- Any notion of "winning" or leaderboards
- Integrations with fitness trackers

## Constraints
| Category | Constraint |
|----------|-----------|
| Platform | Mobile web first; native later, if ever |
| Deadline | Usable at the team offsite in six weeks |
```
