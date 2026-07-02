---
name: subagent-driven-development
description: Execute an implementation plan by dispatching a fresh subagent per task with two-stage review (spec compliance, then code quality). Written to be harness-agnostic — usable in Claude Code (via the Agent tool) or in agent harnesses with different delegation primitives, or none at all. Use when there's an implementation plan with mostly-independent tasks and consistent, automated review matters more than raw speed.
---

# Subagent-Driven Development

## Overview

Execute implementation plans by dispatching fresh subagents per task with systematic two-stage review.

**Core principle:** Fresh subagent per task + two-stage review (spec then quality) = high quality, fast iteration.

**A note on portability:** this skill describes a *pattern*, not a specific API. It was adapted from a harness that has a `delegate_task` primitive and a `todo` tool built in. This version keeps the pattern generic and calls out the Claude Code mapping inline (the `Agent` tool for delegation, `TaskCreate`/`TaskUpdate`/`TaskList` for the todo list) so the skill still works if you're running under a harness with different tools, or no built-in delegation primitive at all — in that case, "dispatch a subagent" means starting a fresh sub-session (a new CLI invocation, a separate context) rather than calling a specific tool.

## When to Use

Use this skill when:
- You have an implementation plan (from a planning skill/step, or user requirements)
- Tasks are mostly independent
- Quality and spec compliance are important
- You want automated review between tasks

**vs. manual execution:**
- Fresh context per task (no confusion from accumulated state)
- Automated review process catches issues early
- Consistent quality checks across all tasks
- Subagents can ask questions before starting work

**In Claude Code specifically:** delegation = the `Agent` tool (`subagent_type: general-purpose` for implementers, `code-reviewer` if available for the quality-review stage); the todo list = `TaskCreate`/`TaskUpdate`/`TaskList`. Everywhere below that says "dispatch a subagent" or "update the todo list," substitute those tools.

## The Process

### 1. Read and Parse Plan

Read the plan file. Extract ALL tasks with their full text and context upfront. Create a todo list with one entry per task (in Claude Code: one `TaskCreate` call per task).

**Key:** Read the plan ONCE. Extract everything. Don't make subagents read the plan file — provide the full task text directly in the delegation prompt/context.

### 2. Per-Task Workflow

For EACH task in the plan:

#### Step 1: Dispatch Implementer Subagent

Delegate with complete, self-contained context — the subagent has no memory of this conversation, so it needs everything it needs to act:

- The exact task spec (what to create/change, and why)
- Instructions to follow TDD: write a failing test first, verify it fails, implement minimally, verify it passes, run the full suite for regressions
- Project context the subagent can't infer on its own (language/framework, where existing code lives, test runner, conventions)
- Whether to commit — see "Committing" below. **Do not have the implementer commit unless you've deliberately chosen the per-task-commit strategy for this run.** Defaulting to "always commit" produces noisy history, partially-reviewed commits, and merge conflicts between parallel subagents touching different tasks.

In Claude Code, this is an `Agent` call with a self-contained prompt covering exactly those points — don't tell it to "read the plan," paste the relevant slice of the plan directly into the prompt.

#### Step 2: Dispatch Spec Compliance Reviewer

After the implementer completes, verify against the original spec — as a fresh subagent, not the implementer grading its own work:

Check:
- All requirements from the spec implemented?
- File paths match spec?
- Function signatures match spec?
- Behavior matches expected?
- Nothing extra added (no scope creep)?

Output: PASS or a list of specific spec gaps to fix.

**If spec issues found:** fix gaps, then re-run spec review. Continue only when spec-compliant.

#### Step 3: Dispatch Code Quality Reviewer

After spec compliance passes, review quality — again as a fresh subagent (in Claude Code, this is a good fit for the `code-reviewer` subagent type if available, otherwise `general-purpose`):

Check:
- Follows project conventions and style?
- Proper error handling?
- Clear variable/function names?
- Adequate test coverage?
- No obvious bugs or missed edge cases?
- No security issues?

Output format:
- Critical Issues: [must fix before proceeding]
- Important Issues: [should fix]
- Minor Issues: [optional]
- Verdict: APPROVED or REQUEST_CHANGES

**If quality issues found:** fix issues, re-review. Continue only when approved.

#### Step 4: Mark Complete

Update the todo list (in Claude Code: `TaskUpdate` with `status: completed`).

### Committing

Pick one strategy up front, before dispatching the first implementer, and tell every implementer subagent which one is in effect:

- **Per-task commits** — each implementer commits once both reviews pass for its task. Gives you a clean bisectable history and lets you stop midway with real, working checkpoints. Riskier if two tasks touch overlapping files, since later commits can conflict with earlier ones.
- **Final squashed commit** — no implementer commits anything; you commit once at the end (see "Verify and Commit" below), after the integration review passes. Simpler, avoids inter-task conflicts entirely, but you lose per-task checkpoints if the run gets interrupted.

Prefer final-squashed by default for tasks with any file overlap, or in any environment where committing mid-run isn't permitted. Use per-task commits only when tasks are genuinely independent (different files) and you specifically want the checkpoint granularity.

### 3. Final Review

After ALL tasks are complete, dispatch a final integration reviewer:

- Do all components work together?
- Any inconsistencies between tasks?
- All tests passing?
- Ready for merge?

### 4. Verify and Commit

```bash
# Run full test suite
pytest tests/ -q   # or the project's actual test command

# Review all changes
git diff --stat

# Final commit if needed
git add -A && git commit -m "feat: complete [feature name] implementation"
```

## Task Granularity

**Each task should be small enough for one focused implementation pass and one meaningful review cycle** — a single clear outcome, minimal file overlap with other tasks, and acceptance criteria a reviewer can check independently. "2-5 minutes of focused work" is a useful gut-check for a small repo with a fast test suite, not a universal timer — scale it to your language, test suite speed, and codebase size, but keep the same shape: one outcome per task, not a bundle of them.

**Too big:**
- "Implement user authentication system"

**Right size:**
- "Create User model with email and password fields"
- "Add password hashing function"
- "Create login endpoint"
- "Add JWT token generation"
- "Create registration endpoint"

## Red Flags — Never Do These

- Start implementation without a plan
- Skip reviews (spec compliance OR code quality)
- Proceed with unfixed critical/important issues
- Dispatch multiple implementation subagents for tasks that touch the same files
- Make a subagent read the plan file (provide full text in its prompt instead)
- Skip scene-setting context (subagent needs to understand where the task fits)
- Ignore subagent questions (answer before letting them proceed)
- Accept "close enough" on spec compliance
- Skip review loops (reviewer found issues → implementer fixes → review again)
- Let implementer self-review replace actual review (both are needed)
- **Start code quality review before spec compliance is PASS** (wrong order)
- Move to next task while either review has open issues

## Handling Issues

### If a Subagent Asks Questions

- Answer clearly and completely
- Provide additional context if needed
- Don't rush them into implementation

### If a Reviewer Finds Issues

- Implementer subagent (or a new one) fixes them
- Reviewer reviews again
- Repeat until approved
- Don't skip the re-review

### If a Subagent Fails a Task

- Dispatch a new fix subagent with specific instructions about what went wrong
- Don't try to fix manually in the controller session (context pollution)

## Efficiency Notes

**Why fresh subagent per task:**
- Prevents context pollution from accumulated state
- Each subagent gets clean, focused context
- No confusion from prior tasks' code or reasoning

**Why two-stage review:**
- Spec review catches under/over-building early
- Quality review ensures the implementation is well-built
- Catches issues before they compound across tasks

**Cost trade-off:**
- More subagent invocations (implementer + 2 reviewers per task)
- But catches issues early (cheaper than debugging compounded problems later)

## Example Workflow

This example uses the per-task-commit strategy (see "Committing" above) — with final-squashed instead, drop the "committed" lines and commit once at the end.

```
[Read plan: docs/plans/auth-feature.md]
[Create todo list with 5 tasks]

--- Task 1: Create User model ---
[Dispatch implementer subagent]
  Implementer: "Should email be unique?"
  You: "Yes, email must be unique"
  Implementer: Implemented, 3/3 tests passing, committed.

[Dispatch spec reviewer]
  Spec reviewer: PASS — all requirements met

[Dispatch quality reviewer]
  Quality reviewer: APPROVED — clean code, good tests

[Mark Task 1 complete]

--- Task 2: Password hashing ---
[Dispatch implementer subagent]
  Implementer: No questions, implemented, 5/5 tests passing.

[Dispatch spec reviewer]
  Spec reviewer: Missing: password strength validation (spec says "min 8 chars")

[Implementer fixes]
  Implementer: Added validation, 7/7 tests passing.

[Dispatch spec reviewer again]
  Spec reviewer: PASS

[Dispatch quality reviewer]
  Quality reviewer: Important: Magic number 8, extract to constant
  Implementer: Extracted MIN_PASSWORD_LENGTH constant
  Quality reviewer: APPROVED

[Mark Task 2 complete]

... (continue for all tasks)

[After all tasks: dispatch final integration reviewer]
[Run full test suite: all passing]
[Done!]
```

## Remember

```
Fresh subagent per task
Two-stage review every time
Spec compliance FIRST
Code quality SECOND
Never skip reviews
Catch issues early
```

**Quality is not an accident. It's the result of systematic process.**

## Further reading (load when relevant)

When the orchestration involves significant context usage, long review loops, or complex validation checkpoints, load these references for the specific discipline:

- **`references/context-budget-discipline.md`** — Four-tier context degradation model (PEAK / GOOD / DEGRADING / POOR), read-depth rules that scale with context window size, and early warning signs of silent degradation. Load when a run will clearly consume significant context (multi-phase plans, many subagents, large artifacts).
- **`references/gates-taxonomy.md`** — The four canonical gate types (Pre-flight, Revision, Escalation, Abort) with behavior, recovery, and examples. Load when designing or reviewing any workflow that has validation checkpoints — use the vocabulary explicitly so each gate has defined entry, failure behavior, and resumption rules.

Both references adapted from gsd-build/get-shit-done (MIT © 2025 Lex Christopherson).
