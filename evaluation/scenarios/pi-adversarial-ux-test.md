# Scenario: pi-adversarial-ux-test-persona-filter

## Header

- `skill_id`: pi-adversarial-ux-test
- `skill_path`: pi-skills/adversarial-ux-test/SKILL.md
- `scenario_id`: pi-adversarial-ux-test-persona-filter
- `executor_floor`: tool-small
- `judge_model_policy`: highest-available
- `expected_duration`: 20-35 tool calls

## Capability Contract

Allowed tools:

- Read
- Write
- Edit
- Bash
- bundled sibling dogfood browser driver

Disallowed tools:

- non-core browser tools
- persistent shell assumptions
- unfiltered persona rants as final findings

Environment assumptions:

- `pi-skills/dogfood/scripts/browser-driver.mjs` exists and works.
- A staging app is available at `https://example-staging.local`.
- The app has an onboarding modal, small text in a settings page, and one confusing "workspace" label.

## Setup

Fixture:

- Local or mocked staging app with stable pages and browser-driver support.

Initial state:

- No `adversarial-ux-output` directory exists.

User replies, if any:

- None.

## User Prompt

```text
Run an adversarial UX test on https://example-staging.local for a nontechnical office manager who needs to invite a coworker.
```

## Required Behaviors

- Resolve the sibling dogfood driver and paste its literal path into each Bash block that needs it.
- Create `./adversarial-ux-output` paths.
- Define a specific persona based on the prompt.
- Browse as that persona using the dogfood driver.
- Capture screenshots and accessibility snapshots.
- Apply the pragmatism filter so only genuine issues become tickets.
- Separate persona complaints from actionable findings.
- Produce the final UX report and artifact paths.

## Forbidden Behaviors

- Using shell variables across Bash calls without resetting literal paths.
- Treating every complaint as a product defect.
- Running without the sibling dogfood driver or without documenting that blocker.

## Expected Artifacts

- `adversarial-ux-output/report.md` or equivalent final report.
- Screenshots under `adversarial-ux-output/screenshots/`.

## Metric Emphasis

- Tool and environment discipline
- Task outcome quality
- Communication and final report

## Judge Notes

The judge should penalize persona theatrics that are not filtered into concrete, pragmatic product issues.
