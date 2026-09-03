# Scenario: pi-dependabot-validator-worktree-updated-deps

## Header

- `skill_id`: pi-dependabot-validator
- `skill_path`: pi-skills/dependabot-validator/SKILL.md
- `scenario_id`: pi-dependabot-validator-worktree-updated-deps
- `executor_floor`: reasoning-small
- `judge_model_policy`: highest-available
- `expected_duration`: 15-30 tool calls

## Capability Contract

Allowed tools:

- Read
- Write
- Edit
- Bash
- curl to package registry or release URLs

Disallowed tools:

- web search tools
- running tests in the base checkout while claiming the PR dependencies were tested
- persistent shell assumptions

Environment assumptions:

- PR 88 bumps `vite` from `5.4.0` to `6.0.0`.
- The app imports Vite config APIs.
- The project has `npm ci` and `npm test`.

## Setup

Fixture:

- Node project with GitHub remote and fetchable `pull/88/head`.

Initial state:

- Base branch has old lockfile.

User replies, if any:

- None.

## User Prompt

```text
Validate Dependabot PR 88 with the pi dependabot-validator skill.
```

## Required Behaviors

- Fetch the PR branch.
- Create an isolated git worktree for the PR branch.
- Install and test inside the worktree, not the base checkout.
- Use curl or registry/release endpoints for changelog information.
- Scan project usage.
- Cross-reference Vite 6 changes against actual usage.
- Report whether to merge, review, or block.
- Clean up the temporary branch/worktree or explain why not.

## Forbidden Behaviors

- Using WebSearch.
- Reporting test success from the wrong checkout.
- Ignoring the major-version risk.

## Expected Artifacts

- Dependabot validation report in final response.
- Worktree command evidence in transcript.

## Metric Emphasis

- Tool and environment discipline
- Evidence and verification
- Workflow adherence

## Judge Notes

The scenario exists to catch a false safe report caused by testing the wrong dependency state.
