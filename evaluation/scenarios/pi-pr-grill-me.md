# Scenario: pi-pr-grill-me-git-only-diff-grill

## Header

- `skill_id`: pi-pr-grill-me
- `skill_path`: pi-skills/pr-grill-me/SKILL.md
- `scenario_id`: pi-pr-grill-me-git-only-diff-grill
- `executor_floor`: reasoning-small
- `judge_model_policy`: highest-available
- `expected_duration`: 12-25 turns

## Capability Contract

Allowed tools:

- Read
- Write
- Edit
- Bash/git

Disallowed tools:

- GitHub API
- web search
- showing the diff before the interview

Environment assumptions:

- The repo remote may be SSH or HTTPS.
- PR 23 changes a feature flag and unrelated logging behavior.

## Setup

Fixture:

- Fetchable PR ref at `pull/23/head`.

Initial state:

- Executor starts on base branch.

User replies, if any:

- Q1: "It enables the new dashboard behind a flag."
- Q2: "We need QA to try it in staging."
- Q3: "The flag config and dashboard route."
- Q4: "Logging and existing dashboard behavior must not change."
- Q5: "Flag missing, flag off, and flag on."
- Q6: "Manual staging check plus a unit test."
- Q7: "Not really."

## User Prompt

```text
Run the pi pr-grill-me workflow on PR 23.
```

## Required Behaviors

- Use only git/Bash to infer remote and fetch the PR.
- Read commits and diff silently.
- Ask the seven questions one at a time.
- Compare the user's claims against the diff.
- Identify the unrelated logging behavior change.
- Check whether tests or changed files support the claimed flag cases.
- Produce the specified report and verdict.
- Clean up the temporary branch.

## Forbidden Behaviors

- Using GitHub-specific APIs.
- Asking all interview questions at once.
- Starting with a diff summary.

## Expected Artifacts

- Final PR Grill Report.
- Git command evidence in transcript.

## Metric Emphasis

- Trigger and input handling
- Workflow adherence
- Task outcome quality

## Judge Notes

The pi version is graded on portability as well as the interview discipline.
