# Question Bank

> Referenced from [SKILL.md](../SKILL.md), [existing-project.md](existing-project.md), and [new-project.md](new-project.md).

Wording to draw from when interviewing the user. Pick the ones that resolve a
real decision — don't ask them all. Ask **2–4 at a time, numbered, as plain
text**, then STOP and wait for answers (pi has no menu/question popup).

Example of how to ask:

> A couple of questions before I continue:
> 1. Who is the main user of this app, and what do they use it for?
> 2. Is this in production, or still in development?
> 3. Are we mainly hunting bugs, or planning new features?

## Mode A — Verifying an existing app (Phase 2)

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

## Mode A — Triage (Phase 4)

- Is `<finding>` a real bug or intended behavior?
- How severe is this to you, and how often does it happen?
- Do you want a fix now, a ticket for later, or to leave it?
- For the fix, do you prefer the minimal patch or fixing the root cause?

## Mode B — Intent (Phase 1)

**Problem & users**
- In one sentence, what does this app do and for whom?
- What do people do today instead, and why isn't that good enough?
- How many users, how technical, one persona or several?

**Scope**
- What are the 3–7 things a user must do for a first version to be worth shipping?
- What's explicitly out of scope for v1?
- How will you know it's working / successful?

**Constraints**
- Platform(s): web, mobile, desktop, CLI, API?
- Timeline and team — solo, small team, skills available?
- Any languages/frameworks/services you already want or must use?
- Hosting/ops preferences or limits (cloud, on-prem, serverless, budget)?
- Compliance, privacy, or data-residency requirements?
- Expected scale now and in a year?

## Mode B — Stack (Phase 2)

- For `<decision>`, options A/B/C have these trade-offs — which fits your
  priorities (speed to ship vs familiarity vs scale vs cost)?
- How important is `<concern>` (realtime, offline, SEO, low latency)?
- Do you have existing infrastructure or accounts (cloud, auth, DB) to reuse?
- Who maintains this after v1 — does that constrain the choice?
