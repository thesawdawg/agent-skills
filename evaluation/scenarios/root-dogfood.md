# Scenario: root-dogfood-local-webapp-qa

## Header

- `skill_id`: root-dogfood
- `skill_path`: dogfood/SKILL.md
- `scenario_id`: root-dogfood-local-webapp-qa
- `executor_floor`: tool-small
- `judge_model_policy`: highest-available
- `expected_duration`: 20-40 tool calls

## Capability Contract

Allowed tools:

- shell
- file read/write
- image viewing if available
- bundled browser driver

Disallowed tools:

- manual browser not captured in transcript
- claiming visual inspection without screenshots or accessibility snapshots

Environment assumptions:

- A local test web app is running at `http://localhost:5173`.
- `dogfood/scripts` dependencies are installed.
- The app has a contact form with a required email field, a broken footer link, and a console error after invalid submission.

## Setup

Fixture:

- Running local app with at least home, contact, and pricing pages.

Initial state:

- No `dogfood-output` directory exists.

User replies, if any:

- None.

## User Prompt

```text
Dogfood http://localhost:5173. Focus on navigation and the contact form.
```

## Required Behaviors

- Create the output directory structure.
- Define testing scope from the prompt.
- Launch the persistent browser session using the bundled driver.
- Navigate through the scoped pages.
- Capture accessibility snapshots and screenshots.
- Check console after navigation and interactions.
- Test the contact form with invalid and valid inputs.
- Record issues with reproduction steps, expected/actual behavior, severity, category, and screenshots.
- Generate `dogfood-output/report.md`.
- Close the browser session.
- Surface report path and key findings.

## Forbidden Behaviors

- Only summarizing without driving the browser.
- Missing console checks.
- Leaving the browser process running.
- Reporting issues without evidence.

## Expected Artifacts

- `dogfood-output/report.md`
- `dogfood-output/issues.json`
- screenshots under `dogfood-output/screenshots/`

## Metric Emphasis

- Tool and environment discipline
- Evidence and verification
- Task outcome quality

## Judge Notes

The judge should inspect whether the report is backed by screenshots and console output. Visual claims without screenshot evidence should lose evidence points.
