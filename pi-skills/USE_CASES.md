# pi-skills: Practical Use Cases

This guide shows **when a user should invoke each skill**, **how the model should recognize the request**, **what information it needs before starting**, and **what a successful result should look like**.

The examples are written for the `pi-skills/` variants, which target a portable baseline of **Read, Write, Edit, and Bash**. Richer harnesses may use additional capabilities, but the workflow should still complete without depending on them. Some examples chain these skills with the companion root skills `dogfood`, `dependabot-validator`, and `pr-grill-me` — consolidated single copies that live at this repo's root and follow the same four-tool baseline (see the root `USE_CASES.md`).

## How to use this guide

A user does not need to name a skill exactly. The model should select a skill when the user's intent matches its description.

A good skill invocation has three parts:

1. **The target** — the application, pull request, API, deployment, or task being worked on.
2. **The goal** — what the user wants tested, reviewed, debugged, or built.
3. **Important constraints** — authorization, scope, environment limits, deadlines, or areas to avoid.

For example:

> Test the checkout flow on my local app at `http://localhost:3000`. Focus on keyboard accessibility and mobile layout. Do not create real orders.

The model should map that request to `dogfood`, preserve the constraints, and produce evidence-backed findings rather than a generic UX opinion dump.

---

## Quick skill chooser

| User goal | Skill |
|---|---|
| Stress-test a UI from difficult user perspectives | `adversarial-ux-test` |
| Debug a failing REST or GraphQL integration | `rest-graphql-debug` |
| Assess an authorized web target for security weaknesses | `web-pentest` |
| Publish a temporary Cloudflare Worker preview | `cloudflare-temporary-deploy` |
| Implement a multi-step change using isolated passes and review stages | `subagent-driven-development` |

---

# 1. `adversarial-ux-test`

## Use it when

Use `adversarial-ux-test` when ordinary happy-path testing is not enough and the user wants the interface examined from **challenging personas, stressful conditions, or accessibility constraints**.

This skill builds on browser-driven dogfooding, but deliberately changes the tester's perspective.

Useful personas include:

- First-time user with no product context
- Keyboard-only user
- Low-vision user
- User with limited technical confidence
- User on a narrow mobile viewport
- Distracted user in a hurry
- User who makes mistakes and needs recovery paths
- User with slow or unreliable connectivity

## User examples

> Test onboarding as a first-time user who has no idea what our terminology means.

> Review the checkout flow as a keyboard-only user with low vision.

> Try this admin panel as an impatient user who keeps clicking the wrong thing.

> Stress-test the form validation with typos, missing fields, and back-button navigation.

## Model selection cues

Select this skill when the user mentions:

- personas
- adversarial UX
- accessibility stress testing
- novice users
- error recovery
- confusing terminology
- difficult conditions
- “pretend you are…”

Use `dogfood` for broad exploratory QA without a specific adversarial perspective.

## Inputs the model should establish

Determine:

- Target URL
- One or more personas
- Critical flow to evaluate
- Constraints on data creation or submission
- Accessibility or viewport requirements
- Whether visual analysis is available

If the user gives no persona, choose a small, relevant set and state them before testing.

## Example model plan

1. Define the persona's abilities, goals, and likely failure modes.
2. Establish measurable UX questions.
3. Run the critical workflow without correcting for product knowledge.
4. Record friction, ambiguity, dead ends, and recovery failures.
5. Separate functional defects from UX weaknesses.
6. Produce persona-specific recommendations.

## Expected output

The report should include:

- Persona definition
- Scenario and goal
- Observed friction
- Severity and user impact
- Evidence
- Suggested design or copy changes
- Limitations of the test

## Example result shape

```markdown
## Persona: First-time mobile user in a hurry

### Friction: “Workspace” is required but never explained

The signup flow asks the user to create a workspace before explaining
whether it represents a company, project, or team.

**Impact:** A new user may invent an incorrect structure and need to redo setup.  
**Recommendation:** Add one sentence of helper text and a concrete example.
```

---

# 2. `rest-graphql-debug`

## Use it when

Use `rest-graphql-debug` when an application cannot successfully communicate with a REST or GraphQL API and the user needs a **layered diagnosis**, not random header thrashing.

It is suitable for:

- Connection failures
- DNS or TLS problems
- Authentication errors
- Unexpected status codes
- Invalid JSON or GraphQL payloads
- CORS confusion
- Schema or query errors
- Response-shape mismatches
- Environment-specific API failures

## User examples

> This REST call works in Postman but returns 401 from my app. Help me isolate why.

> My GraphQL query returns 200 with an `errors` array. Debug it.

> Requests to our staging API fail with a TLS certificate error.

> The endpoint returns JSON locally but HTML through the reverse proxy.

## Model selection cues

Select this skill when the user mentions:

- API request failure
- REST
- GraphQL
- `curl`
- 401, 403, 404, 429, or 5xx
- TLS, DNS, CORS, headers, tokens
- malformed response
- schema errors

Do not select it merely because the codebase contains an API. There should be a concrete integration failure or investigation goal.

## Inputs the model should establish

Gather:

- Endpoint URL
- HTTP method
- Expected status and response
- Actual status and response
- Required headers
- Authentication type
- A redacted reproduction request
- Environment where the failure occurs

Never print secrets. Use placeholders in commands and ask the user to set sensitive values locally.

## Example model plan

1. Test DNS and TCP reachability.
2. Inspect TLS negotiation.
3. Reproduce the request with `curl`.
4. Verify authentication independently.
5. Validate headers, content type, and body encoding.
6. Inspect the response status and payload.
7. For GraphQL, separate transport success from GraphQL errors.
8. Compare the working and failing environments.

## Expected output

A strong result includes:

- Reproduction command with secrets removed
- Layer where the failure occurs
- Evidence from status, headers, or payload
- Root cause or ranked hypotheses
- Minimal corrective action
- Verification command

## Example result shape

```markdown
## Root cause

The API token is valid, but the application sends the JSON body without
`Content-Type: application/json`. The gateway parses the request as an empty
form body and rejects the missing `grant_type`.

## Fix

Add the content-type header and JSON-encode the request body.

## Verification

Run the corrected `curl` request and confirm a `200` response with the
expected token fields.
```

---

# 3. `web-pentest`

## Use it when

Use `web-pentest` only for an **explicitly authorized** web security assessment with a clearly defined target and scope.

Suitable work includes:

- Reconnaissance
- Security-header review
- Authentication and authorization testing
- Input validation checks
- Non-destructive proof-based exploitation
- Scope-aware reporting

## User examples

> I own `staging.example.com`. Test only that host for common web vulnerabilities. Do not perform denial-of-service testing.

> Assess the authentication flow on our local app. You may use the supplied test account but may not access other users' data.

> Review this intentionally vulnerable lab application and produce a pentest report.

## Model selection cues

Select this skill only when the request includes:

- clear authorization
- a defined target
- an allowed scope
- a security assessment goal

Do not infer authorization from technical access, ownership-like language without confirmation, or a public URL.

## Required authorization gate

Before any active testing, establish:

- Who authorized the test
- Exact hosts, paths, accounts, or APIs in scope
- Start and stop boundaries
- Prohibited techniques
- Data-handling rules
- Whether destructive testing is allowed

If authorization or scope is unclear, stop and ask. No cowboy nonsense.

## Example model plan

1. Record authorization and scope.
2. Resolve and validate the allowlist.
3. Perform passive reconnaissance.
4. Review exposed services and application behavior.
5. Test hypotheses with minimal, non-destructive proofs.
6. Stop immediately if a test crosses scope.
7. Redact secrets and sensitive data.
8. Produce a professional report.

## Expected output

A pentest report should include:

- Authorization statement
- Scope and exclusions
- Methodology
- Executive summary
- Findings with severity
- Evidence and reproducible proof
- Business impact
- Remediation guidance
- Retest recommendations
- Limitations

## Example result shape

```markdown
## Finding: Horizontal authorization bypass in invoice endpoint

**Severity:** High  
**Endpoint:** `GET /api/invoices/{id}`  
**Impact:** An authenticated user can retrieve another customer's invoice by
changing the numeric ID.

**Proof:** Confirmed using two test accounts supplied for the assessment.
No production records were accessed.

**Remediation:** Enforce ownership checks server-side before loading or
serializing the invoice.
```

---

# 4. `cloudflare-temporary-deploy`

## Use it when

Use `cloudflare-temporary-deploy` when the user wants a **quick, temporary public preview** of a Cloudflare Worker without setting up a permanent deployment workflow.

Good uses include:

- Sharing a small API prototype
- Testing a Worker from an external service
- Demonstrating a minimal reproduction
- Producing a disposable preview URL
- Verifying Worker behavior outside localhost

## User examples

> Deploy this Worker temporarily so I can test it from my phone.

> Create a public preview of this reproduction without touching my Cloudflare account.

> Put this API stub on a temporary `workers.dev` URL.

## Model selection cues

Select this skill when the user asks for:

- temporary Cloudflare deployment
- disposable Worker URL
- preview Worker
- `wrangler --temporary`
- public reproduction endpoint

Do not use it for production deployment, custom domains, durable infrastructure, secrets-heavy services, or applications requiring persistent state.

## Inputs the model should establish

Determine:

- Worker project directory
- Entry point
- Required build step
- Whether public exposure is acceptable
- Whether any secrets or private data are embedded
- User confirmation before provisioning the public URL

## Example model plan

1. Inspect the Worker project.
2. Check for embedded credentials or sensitive values.
3. Build or validate the Worker locally.
4. Explain that deployment creates a real public URL.
5. Obtain confirmation.
6. Run the temporary deployment.
7. Parse and verify the URL.
8. Return the URL while keeping claim tokens redacted.

## Expected output

The result should include:

- Public temporary URL
- Verification status
- Relevant logs
- Expiration or ownership caveats
- Exact local changes, if any
- Redaction of claim tokens and credentials

---

# 5. `subagent-driven-development`

## Use it when

Use `subagent-driven-development` when a change is large enough to benefit from **separate implementation and review passes**, especially when the harness supports subagents.

Without a delegation capability, the model should simulate the pattern using fresh, focused passes and a persistent scratch checklist.

Good uses include:

- Multi-file feature work
- Refactors with behavioral constraints
- Migrations
- Changes requiring tests, docs, and review
- Work that can be split into independent tasks

## User examples

> Implement this feature using separate implementation and review passes.

> Break this refactor into tasks, complete them one at a time, and review each before moving on.

> Add OAuth support, including tests and documentation, without mixing all the work into one giant pass.

## Model selection cues

Select this skill when the user asks for:

- subagent-driven development
- task decomposition with review
- implementation plus independent verification
- multiple focused agents or passes
- staged development

Do not use it for a one-line fix unless the user explicitly requests the process. That would be ceremonial bureaucracy wearing a tiny hard hat.

## Inputs the model should establish

Determine:

- Desired end state
- Acceptance criteria
- Constraints and non-goals
- Test commands
- Task dependencies
- Whether real subagent delegation exists

## Example model plan

1. Convert the request into explicit acceptance criteria.
2. Split work into small tasks.
3. For each task:
   - run an implementation pass
   - run a specification-compliance review
   - run a code-quality review
   - fix issues before continuing
4. Run full integration tests.
5. Review the complete diff.
6. Summarize completed work and remaining risks.

## Expected output

The workflow should leave:

- A task checklist
- Per-task implementation notes
- Review findings and corrections
- Test results
- Final diff summary
- Unresolved risks or follow-up work

---

# Combining skills

Skills may be chained when their responsibilities remain distinct.

## Example: Build, review, and test a feature

1. Use `subagent-driven-development` to implement the feature.
2. Use `pr-grill-me` to review the final diff.
3. Use `dogfood` to validate the running UI.

Example user request:

> Implement the new billing settings flow with staged implementation and
> review. Then grill the final diff and dogfood the feature on localhost.
> Do not submit real payment information.

## Example: Validate an API dependency update

1. Use `dependabot-validator` to assess the package update.
2. Use `rest-graphql-debug` if tests reveal an API integration failure.
3. Use `pr-grill-me` for a broader review of any compatibility fixes.

## Example: Deploy a reproduction for external testing

1. Use `rest-graphql-debug` to isolate the failing Worker behavior locally.
2. Use `cloudflare-temporary-deploy` to publish a minimal reproduction.
3. Use `dogfood` or direct HTTP checks to verify the temporary endpoint.

## Example: Security-conscious UI assessment

1. Use `dogfood` for functional browser testing.
2. Use `adversarial-ux-test` for accessibility and error-recovery perspectives.
3. Use `web-pentest` only as a separately authorized security engagement.

Do not silently escalate ordinary QA into penetration testing.

---

# Guidance for users

You will get better results when your request states:

- The target
- The outcome you care about
- What the model may and may not do
- Any credentials or test accounts available
- The most important workflow
- The expected report format

Weak request:

> Test my app.

Better request:

> Dogfood `http://localhost:3000` using the test account in `.env.test`.
> Focus on creating and exporting reports. You may create test records, but
> do not delete existing records. Return a severity-ranked Markdown report
> with screenshot paths.

---

# Guidance for models

When applying a skill:

1. **Preserve user constraints.** Repeat critical scope or safety limits before acting.
2. **Do not pretend capabilities exist.** Use the documented core-tool fallback.
3. **Do not treat examples as literal values.** Replace placeholders with real inputs.
4. **Keep shell commands self-contained.** Assume variables and working shell state may not persist.
5. **Record evidence as work proceeds.** Do not rely on reconstructing findings from memory.
6. **Separate facts from inference.** Mark incomplete research or unverified hypotheses.
7. **Do not overstate coverage.** Report skipped flows, unavailable visual inspection, missing credentials, or tests that could not run.
8. **Use explicit verdicts.** End reviews and validations with a clear recommendation.
9. **Respect stop conditions.** Authorization, destructive actions, real purchases, public deployments, and sensitive data require special care.
10. **Leave usable artifacts.** Provide exact report, screenshot, log, or output paths.

A skill is successful when the user can act on the result without asking, “Okay, but what did you actually find?”
