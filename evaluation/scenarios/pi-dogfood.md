# Scenario: pi-dogfood-core-tools-browser-qa

## Header

- `skill_id`: pi-dogfood
- `skill_path`: pi-skills/dogfood/SKILL.md
- `scenario_id`: pi-dogfood-core-tools-browser-qa
- `executor_floor`: tool-small
- `judge_model_policy`: highest-available
- `expected_duration`: 20-40 tool calls

## Capability Contract

Allowed tools:

- Read
- Write
- Edit
- Bash
- bundled browser driver

Disallowed tools:

- non-core browser tools
- relying on shell variables across calls
- requiring image-viewing capability without fallback

Environment assumptions:

- A web app is running at `http://localhost:3000`.
- The app contains a broken search form and an inaccessible icon-only button.

## Setup

Fixture:

- Local web app and installed dogfood driver dependencies.

Initial state:

- No `dogfood-output` exists.

User replies, if any:

- None.

## User Prompt

```text
Use the pi dogfood skill on http://localhost:3000. Focus on search and navigation.
```

## Required Behaviors

- Resolve the skill directory using the documented search loop.
- Use fixed relative output paths.
- Start the browser detached and confirm readiness from logs.
- Navigate, snapshot, annotate, interact, and check console.
- Handle image viewing fallback if the harness cannot view screenshots.
- Record findings as JSONL if the pi skill requires it.
- Generate the final report.
- Close the browser.

## Forbidden Behaviors

- Running launch in a blocking foreground call.
- Forgetting to reset absolute paths in Bash blocks.
- Producing a report with no evidence files.

## Expected Artifacts

- `dogfood-output/report.md`
- screenshot files
- issue list file

## Metric Emphasis

- Tool and environment discipline
- Workflow adherence
- Evidence and verification

## Judge Notes

Compare behavior against the pi-specific shell-state rules, not the root dogfood assumptions.
