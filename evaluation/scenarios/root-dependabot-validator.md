# Scenario: root-dependabot-validator-basic-pr-risk

## Header

- `skill_id`: root-dependabot-validator
- `skill_path`: dependabot-validator/SKILL.md
- `scenario_id`: root-dependabot-validator-basic-pr-risk
- `executor_floor`: reasoning-small
- `judge_model_policy`: highest-available
- `expected_duration`: 10-20 tool calls

## Capability Contract

Allowed tools:

- shell/git
- file read
- web search or official package/release lookup

Disallowed tools:

- GitHub API shortcuts that bypass the skill's git-based PR fetch unless the fetch fails and the executor explains the fallback
- fabricating changelog or test results

Environment assumptions:

- The fixture repo has `origin` pointing to a GitHub repo.
- PR 42 is a Dependabot branch that bumps `lodash` from `4.17.20` to `4.17.21`.
- The project imports `debounce` from `lodash` in `src/search.js`.
- `npm test` is available and passes.

## Setup

Fixture:

- A small Node repo with `package.json`, `package-lock.json`, `src/search.js`, and one test.
- A fetchable PR ref at `pull/42/head`.

Initial state:

- The executor starts on the base branch.

User replies, if any:

- None.

## User Prompt

```text
Use the dependabot-validator skill to check PR 42 and tell me whether it is safe to merge.
```

## Required Behaviors

- Fetch `pull/42/head:pr-42` or clearly explain an equivalent fallback.
- Read commit messages and manifest/lockfile diff.
- Identify `lodash` and the exact from/to versions.
- Scan project usage and name `src/search.js`.
- Research release notes or changelog for `4.17.21`.
- Run the relevant test command.
- Check dependency conflicts.
- Delete the temporary branch or explain why cleanup was not possible.
- Produce the report format with package analysis, findings, test results, conflicts, and recommendation.

## Forbidden Behaviors

- Reporting `MERGE SAFE` without checking usage and tests.
- Claiming tests passed without command evidence.
- Leaving uncertainty about which package changed.

## Expected Artifacts

- Final Dependabot PR Validation Report in the response.
- Command evidence in transcript.

## Metric Emphasis

- Workflow adherence
- Evidence and verification
- Task outcome quality

## Judge Notes

Full credit requires a recommendation supported by usage, changelog/release evidence, tests, and conflict checks. If web research is unavailable, the executor must state that limitation and avoid overstating safety.
