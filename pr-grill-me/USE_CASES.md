# pr-grill-me: Practical Use Cases

This guide shows **when to invoke `pr-grill-me`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full workflow. The defining mechanic of this skill (unlike a normal PR review) is that it **interviews the author first, then holds their answers up against the actual diff** — the report is built from the gap between what they said and what the code does, not from the diff alone. See also the [top-level skills index](../USE_CASES.md).

## Use it when

Use `pr-grill-me` when the author wants a reality check on their *own* PR before requesting review or merging — specifically, when they want their stated intent tested against what the diff actually does.

Good uses include:

- A self-review pass before opening a PR for real reviewers
- Sanity-checking a PR the author suspects has gaps but can't pinpoint
- Catching scope creep, forgotten edge cases, or untested claims before merge

Do not use it for reviewing someone *else's* PR with no author present to interview — the whole mechanic depends on grilling the person who wrote it. Don't use it for a dependency-bump PR specifically — that's `dependabot-validator`.

## User examples

> Grill me on PR 73 before I ask for review.

> I think this PR is done but I want you to poke holes in it — here's #58.

> Interview me about this branch and tell me what I'm missing.

> Give my checkout refactor a reality check before I merge it.

## Model selection cues

Select this skill when the user:

- Is the author of the PR/branch in question (not a third-party reviewer)
- Wants their own stated intent checked against the actual diff
- Asks to be "grilled," "interviewed," or given "a reality check" on their own work

Do not select it when:

- The user wants a generic code-quality review with no interview component — that's a normal review pass
- The user is reviewing someone else's PR and can't answer the interview questions as the author
- The PR is a Dependabot dependency bump — use [`dependabot-validator`](../dependabot-validator/USE_CASES.md) instead

## Inputs the model should establish

- PR number (repo inferred from `git remote get-url origin`)
- Nothing else up front — the interview itself is how the model gathers the rest. Don't ask the user to summarize the PR before starting; read the diff silently first, then interview.

## Example model plan

1. Fetch the PR branch and diff via SSH; read commit messages. Do **not** show the diff to the user yet.
2. Ask the 7 grill questions **one at a time**, waiting for each answer: elevator pitch, trigger/motivation, what changed, what must stay the same, edge cases considered, how it was tested, anything sketchy or unsure about.
3. Probe follow-ups only where an answer is vague or contradicts what the diff already shows — keep it conversational, not an interrogation.
4. Cross-reference every answer against the diff: scope gaps, behavior gaps, edge-case gaps, test gaps, unintended changes, consistency gaps.
5. Deliver the PR Grill Report: what they said vs. what the diff does, gaps ranked by risk, unaddressed edge cases, what looks good, and a verdict.
6. Delete the temporary local branch used to hold the PR ref.

## Expected output

A useful report:

- Opens with the contrast between the user's elevator pitch and the model's actual read of the diff
- Quotes the user's own answers back when calling out a gap
- Ranks findings by risk (High and worth fixing first, not buried under nitpicks)
- Calls out real strengths too, not just problems
- Ends with an explicit verdict: **Ready for review** / **Needs a pass** / **Significant gaps**

## Example result shape

```markdown
## PR Grill Report: #73

**What you said it does:** "Adds retry logic to the payment webhook handler."
**What the diff actually does:** Adds retry logic, but also silently changes
the webhook's response status code from 200 to 202 on retry — undiscussed.

### Gaps & Discrepancies

**[Consistency gap]** — Response status code changed without being mentioned.
> _You said:_ "Just retry logic, nothing else changed."
> _The diff:_ `webhook_handler.py:58` now returns 202 instead of 200 on retry.
> _Risk:_ Medium
> _Suggestion:_ Confirm this is intentional — some webhook senders treat
> non-200 as a failure and will re-deliver, defeating the retry logic.

### Verdict
**Needs a pass** — 1 medium-risk discrepancy found. Resolve before requesting review.
```
