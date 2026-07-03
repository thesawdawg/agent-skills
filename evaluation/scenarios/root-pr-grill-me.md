# Scenario: root-pr-grill-me-author-interview

## Header

- `skill_id`: root-pr-grill-me
- `skill_path`: pr-grill-me/SKILL.md
- `scenario_id`: root-pr-grill-me-author-interview
- `executor_floor`: reasoning-small
- `judge_model_policy`: highest-available
- `expected_duration`: 12-25 turns

## Capability Contract

Allowed tools:

- shell/git
- file read

Disallowed tools:

- revealing or summarizing the diff before the user answers the interview
- skipping the interview and doing a normal code review

Environment assumptions:

- The current repo has `origin` set.
- PR 17 changes an API retry policy and also changes an unrelated billing constant.
- The user answers scripted questions one at a time.

## Setup

Fixture:

- Fetchable PR ref at `pull/17/head`.

Initial state:

- Executor is on the base branch.

User replies, if any:

- Q1: "It just improves retry behavior for flaky API calls."
- Q2: "Webhook delivery sometimes fails on transient 502s."
- Q3: "Only the API client and tests."
- Q4: "Billing behavior must not change. Existing tests should cover it."
- Q5: "I handled max retries and timeout."
- Q6: "Unit tests cover it."
- Q7: "Nothing sketchy."

## User Prompt

```text
Run pr-grill-me on PR 17.
```

## Required Behaviors

- Ask for missing PR number only if not provided.
- Infer repo from git remote.
- Fetch PR branch and read commits/diff silently.
- Ask the seven required questions one at a time.
- Use the user's answers to compare intent against the actual diff.
- Identify the unrelated billing constant change as a scope/behavior discrepancy.
- Check whether tests actually cover retry behavior and billing behavior.
- Produce the PR Grill Report with gaps, unaddressed edge cases, what looks good, and verdict.
- Delete the temporary branch or explain cleanup failure.

## Forbidden Behaviors

- Showing the diff before the interview.
- Asking all questions in one message.
- Treating user claims as true without checking the diff.
- Omitting the intentional contrast between stated intent and actual diff.

## Expected Artifacts

- Final PR Grill Report in response.
- Git command evidence in transcript.

## Metric Emphasis

- Trigger and input handling
- Workflow adherence
- Task outcome quality

## Judge Notes

The strongest evidence is whether the executor preserves the interview sequence and catches the billing discrepancy without prematurely revealing the diff.
