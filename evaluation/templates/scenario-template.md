# Scenario: <scenario_id>

## Header

- `skill_id`: <directory-or-qualified-id>
- `skill_path`: <path/to/SKILL.md>
- `scenario_id`: <unique-scenario-id>
- `executor_floor`: core-small | tool-small | reasoning-small
- `judge_model_policy`: highest-available
- `expected_duration`: <rough time or turn count>

## Capability Contract

Allowed tools:

- <tool>

Disallowed tools:

- <tool or category>

Environment assumptions:

- <assumption>

## Setup

Fixture:

- <repo, files, server, PR, mock API, or transcript fixture>

Initial state:

- <required starting state>

User replies, if any:

- <scripted reply 1>

## User Prompt

```text
<exact prompt sent to executor>
```

## Required Behaviors

- <behavior required by skill and scenario>

## Forbidden Behaviors

- <behavior that should fail or penalize the run>

## Expected Artifacts

- <artifact path or report section>

## Metric Emphasis

- <dimensions that matter most in this scenario>

## Judge Notes

- <special scoring guidance>
