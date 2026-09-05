# Question Bank

> Referenced from [SKILL.md](../SKILL.md), [existing-project.md](existing-project.md), and [spec-and-plan.md](spec-and-plan.md).

Wording to draw from when interviewing the user. Pick the ones that resolve a
real decision — don't ask them all. Ask **2–4 at a time, numbered, as plain
text**, then STOP and wait for answers (pi has no menu/question popup).

Example of how to ask:

> A couple of questions before I continue:
> 1. Who is the main user of this app, and what do they use it for?
> 2. Is this in production, or still in development?
> 3. Are we mainly hunting bugs, or planning new features?

## Verify — confirming an existing app (Phase 2)

**Purpose & users**
- Who is the intended user, and what problem does this solve for them?
- Is this in production, in development, a prototype, or abandoned?
- Which features are actively used vs legacy/experimental?

**Behavior & correctness**
- For the main flow `<X>`, what is the correct behavior end to end?
- This behavior `<Y>` looks unusual — intentional or a bug?
- What known issues or rough edges do you already live with?
- Are there features in the code that aren't finished or wired up?

**Boundaries & constraints**
- What's the auth/permission model — who can do what?
- What scale does it run at (users, data volume, traffic)?
- Are there environments (dev/staging/prod) or config that change behavior?
- Is there test/seed data or a safe environment I can exercise?

**Goals for this session**
- Are we mainly hunting bugs, planning features, reducing tech debt, or all three?
- Anything off-limits to change?

## Triage (Phase 4)

- Is `<finding>` a real bug or intended behavior?
- How severe is this to you, and how often does it happen?
- Do you want a fix now, a ticket for later, or to leave it?
- For the fix, do you prefer the minimal patch or fixing the root cause?

## Spec & plan (post-chain)

Only for the [spec-and-plan](spec-and-plan.md) step, and only for gaps the
`ideator` → `constructor` → `datasecurer` artifacts genuinely leave open. Read
those first; re-asking what the brief already answers wastes the user's patience.

- The brief lists `<capability>` — what does "done" look like for it, concretely?
- Which of these are v1 and which are explicitly later?
- What has to be true before you'd call the first milestone demoable?
- Is there a deadline or event this has to land before?

**Intent and stack questions are not here.** Those belong to
[`ideator`](../../ideator/SKILL.md) and [`constructor`](../../constructor/SKILL.md),
which own that conversation and write the artifacts this skill reads.
