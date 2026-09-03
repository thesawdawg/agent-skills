# Scenario: pi-rest-graphql-debug-graphql-200-errors

## Header

- `skill_id`: pi-rest-graphql-debug
- `skill_path`: pi-skills/rest-graphql-debug/SKILL.md
- `scenario_id`: pi-rest-graphql-debug-graphql-200-errors
- `executor_floor`: core-small
- `judge_model_policy`: highest-available
- `expected_duration`: 8-18 tool calls

## Capability Contract

Allowed tools:

- Read
- Write
- Edit
- Bash
- curl
- Python requests via Bash

Disallowed tools:

- Postman or external GUI clients
- guessing at code fixes before isolating the failing layer

Environment assumptions:

- A mock GraphQL endpoint is available at `http://localhost:8080/graphql`.
- It returns HTTP 200 with an `errors` array when the query requests `user.email`.
- The token is valid.

## Setup

Fixture:

- Mock API server and small client script that fails because it checks only HTTP status.

Initial state:

- Executor has the failing endpoint and client path.

User replies, if any:

- None.

## User Prompt

```text
Use rest-graphql-debug to figure out why our GraphQL user query fails even though the HTTP status is 200.
```

## Required Behaviors

- Follow the layered debug flow instead of jumping to a fix.
- Check connectivity, TLS if applicable, auth, request format, response parse, and semantics as needed.
- Use curl or Python via Bash.
- Inspect the GraphQL `errors` field despite HTTP 200.
- Identify that the client only checks status and misses GraphQL errors.
- Recommend or apply a targeted fix if the scenario allows edits.
- Include request/response evidence without leaking secrets.

## Forbidden Behaviors

- Declaring success because HTTP status is 200.
- Skipping directly to speculative code changes.
- Ignoring the `errors` field.

## Expected Artifacts

- Diagnostic summary.
- Optional patch or suggested client change.

## Metric Emphasis

- Workflow adherence
- Task outcome quality
- Evidence and verification

## Judge Notes

This scenario checks whether the executor obeys the skill's core principle: isolate the layer before guessing.
