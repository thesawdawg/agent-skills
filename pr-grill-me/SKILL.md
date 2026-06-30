---
name: pr-grill-me
description: Interview the user about their PR's intent and expected behavior, then compare their answers against the actual diff to surface gaps, missing cases, and unintended changes. Use when the user wants a reality check on a pull request before merging or requesting review.
---

# PR Grill Me Skill

Interviews the author about what their PR is supposed to do, then holds the diff up to those answers to find discrepancies — things the code doesn't do that it should, things it does that it shouldn't, and edge cases that weren't considered.

## Workflow

### 1. Get the PR Number

If the user didn't provide one, ask:
> "What's the PR number? (I'll infer the repo from your git remote)"

Infer the repo from the current directory:
```bash
git remote get-url origin
# git@github.com:myorg/myrepo.git → owner=myorg repo=myrepo
```

### 2. Fetch the PR Diff

Fetch the PR branch over SSH and generate a full diff against the base branch:
```bash
git fetch origin pull/<PR_NUMBER>/head:pr-<PR_NUMBER>
git log pr-<PR_NUMBER> --not HEAD --pretty="%s%n%b"
git diff HEAD..pr-<PR_NUMBER>
```

Also read the PR commit messages for additional context on stated intent.

Do NOT show the diff to the user yet. Read and internalize it silently — you'll use it to evaluate their answers.

### 3. Grill the Author

Ask these questions **one at a time**, waiting for the user's answer before asking the next. Do not ask them all at once.

---

**Q1 — The elevator pitch:**
> "In one or two sentences, what does this PR do?"

**Q2 — The trigger:**
> "What problem or situation does this fix or enable? Walk me through the scenario that motivated it."

**Q3 — What changes:**
> "What parts of the codebase did you need to touch, and why each one?"

**Q4 — What stays the same:**
> "What existing behavior must not change as a result of this PR? How did you verify that?"

**Q5 — Edge cases:**
> "What edge cases or failure modes did you consider? Which ones does the PR handle, and which did you intentionally leave out?"

**Q6 — Testing:**
> "How would someone verify this works? Are there tests, and if not, how did you validate it?"

**Q7 — Anything sketchy:**
> "Is there anything in the diff you're unsure about, cut corners on, or want a second opinion on?"

---

Probe follow-up when an answer is vague or inconsistent with what you can already see in the diff. Keep it conversational — one or two follow-up questions max per topic, not an interrogation.

### 4. Analyze the Diff Against the Answers

Now cross-reference everything the user said against the actual diff. For each category, find gaps:

**Scope gaps** — files changed that the user didn't mention, or files the user mentioned that weren't changed

**Behavior gaps** — functionality the user described that the diff doesn't implement, or behavior the diff changes that the user didn't mention

**Edge case gaps** — edge cases the user said are handled but no code or test covers, or code paths that handle cases the user didn't mention

**Test gaps** — user claimed behavior is verified but no test exists or was changed

**Unintended changes** — whitespace-only diffs on logic files, commented-out code left in, debug statements, scope creep into unrelated areas

**Consistency gaps** — user's stated intent contradicts what the diff actually does (e.g. "I only changed the API layer" but a model file was modified)

### 5. Deliver the Report

Open with a one-sentence summary of what the PR actually does based on the diff (not the user's description — this contrast is intentional).

Then structure the findings:

---

## PR Grill Report: #<NUMBER>

**What you said it does:** <user's elevator pitch>
**What the diff actually does:** <your read of the diff>

### Gaps & Discrepancies

For each finding:

**[Category]** — <one-sentence description of the discrepancy>
> _You said:_ "<relevant quote from their answer>"
> _The diff:_ <what the code actually shows>
> _Risk:_ Low / Medium / High
> _Suggestion:_ <concrete action — add a test, revert a file, document a decision, handle a case>

### Unaddressed Edge Cases

List any edge cases you spotted in the diff that the user never mentioned and that aren't covered by tests or guards.

### What Looks Good

Call out one or two things where the diff lines up clearly with the stated intent — keep the author grounded.

### Verdict

**Ready for review** — Intent and implementation align. Minor gaps noted above.

— or —

**Needs a pass** — <N> meaningful discrepancies found. Address the High-risk items before requesting review.

— or —

**Significant gaps** — The diff diverges from the stated intent in ways that suggest the PR isn't finished or has unintended side effects. Recommend revisiting before review.

---

### 6. Clean Up

```bash
git branch -D pr-<PR_NUMBER>
```

## Tone Guidelines

- Be direct but not harsh. The goal is to help the author catch their own blind spots, not to embarrass them.
- Quote their own words back when calling out a gap — it's harder to dismiss.
- Prioritize findings by risk. Don't bury a High-risk gap under five Low-risk nits.
- If the PR is genuinely solid, say so clearly — a clean bill of health is as useful as a list of problems.
