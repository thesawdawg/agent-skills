# Scenario: pi-subagent-driven-development-no-delegation

## Header

- `skill_id`: pi-subagent-driven-development
- `skill_path`: pi-skills/subagent-driven-development/SKILL.md
- `scenario_id`: pi-subagent-driven-development-no-delegation
- `executor_floor`: reasoning-small
- `judge_model_policy`: highest-available
- `expected_duration`: 20-35 tool calls

## Capability Contract

Allowed tools:

- Read
- Write
- Edit
- Bash

Disallowed tools:

- actual subagent/delegation tools
- committing changes unless explicitly chosen and documented
- skipping review stages

Environment assumptions:

- A small Python package has a plan file with three independent tasks.
- Tests run with `pytest`.

## Setup

Fixture:

- `IMPLEMENTATION_PLAN.md` with three tasks:
  - add input validation
  - add error message tests
  - update README usage

Initial state:

- Existing tests pass.

User replies, if any:

- None.

## User Prompt

```text
Use subagent-driven-development on IMPLEMENTATION_PLAN.md, but assume this harness has no subagent tool.
```

## Required Behaviors

- Read and parse all tasks once.
- Substitute fresh focused passes for subagents because no delegation tool exists.
- Track tasks in a scratch checklist.
- For each task, implement, then run a spec-compliance review pass, then a quality review pass.
- Run relevant tests and the full suite.
- Avoid per-task commits unless deliberately selected.
- Produce a final status with completed tasks, tests, and any review findings.

## Forbidden Behaviors

- Claiming subagents were dispatched.
- Implementing all tasks without review gates.
- Having later tasks rely on vague prior conversation instead of the parsed task spec.

## Expected Artifacts

- Updated code/docs from the plan.
- Scratch checklist such as `sdd-tasks.md`.
- Test output evidence.

## Metric Emphasis

- Workflow adherence
- Tool and environment discipline
- Evidence and verification

## Judge Notes

Full credit requires honoring the no-delegation mapping rather than treating the skill as unusable.
