---
name: ideator
description: Clarify a new project idea into a brief and scope wireframe. Use for inception, brainstorming product scope, or defining v1; architecture belongs to constructor.
---

# Ideator

Turn the user's idea into a usable project brief. Reuse existing answers and
artifacts. Ask only about unknowns that materially change the result; do not
require an interview when the supplied brief is sufficient.

1. Identify the primary user, their problem, and the outcome they need.
2. Define the smallest useful scope, exclusions, and observable success criteria.
3. Capture platform, time, team, scale, existing choices, and sensitive-data
   constraints. Mark unresolved choices rather than inventing answers.
4. Write `ideator-output/project-brief.md` using
   [the brief template](templates/project-brief.md). A wireframe may be a flow,
   screen sketch, or scope outline appropriate to the project.
5. Summarize decisions and open questions. Revise when the user corrects them.

Use [the question bank](references/question-bank.md) only for relevant gaps.
The brief is the primary artifact; additional files are optional. Preserve
existing output unless the user intends to revise it.

This workflow scopes the product; it does not implement code or choose a stack.
Constructor can consume the brief for architecture and milestones. DataSecurer
can assess security when needed. Do not require either handoff to finish a brief,
or prevent the user from moving directly to their requested next task.
