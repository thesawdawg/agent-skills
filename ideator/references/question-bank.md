# Question Bank

Wording to draw from when interviewing the user. Pick the ones that
resolve a real unknown — don't ask them all. Ask **2–4 at a time,
numbered, as plain text**, then STOP and wait for answers.

Example of how to ask:

> Three things I need before I can shape this:
> 1. Who is the single most important user, and what are they doing the
>    moment before they open your app?
> 2. What does "done" look like for v1 — what can someone actually do?
> 3. What's explicitly NOT in this version?

## Phase 1 — The Problem

**Surface the problem**
- In one sentence, what does this do and for whom?
- What are people doing today instead of this? Why isn't that good enough?
- Is this a problem you have personally, or one you've observed in others?
- Who feels this problem most acutely? Who feels it but doesn't care?

**Test the problem is real**
- How often does this problem come up — daily, weekly, once?
- What happens if nobody builds this? Does the world get worse, or just
  stay the same?
- Is there an existing tool that almost solves this? What's it missing?

**Nail the "why"**
- Why you? Why are you the person/team to build this?
- What would make you shut this down — what's the "this isn't working"
  signal?

## Phase 2 — The Scope

**Core capabilities**
- What are the 3–7 things a user must be able to do for v1 to be worth
  shipping? Name them as actions, not features.
- Walk me through the first 60 seconds of a user using this for the first
  time. What do they do?
- Is there one capability that, if missing, makes the whole thing
  pointless? What is it?

**Boundaries**
- What's explicitly out of scope for v1? Name 2–3 things you're NOT
  building.
- What's the "nice to have" that you keep being tempted to add but
  shouldn't?
- Is this a tool, a platform, or a product? (Tools do one thing;
  platforms host things; products serve users.)

**Success criteria**
- How will you know v1 is working? What's the measurable signal?
- What does "done" look like for you personally — shipped, used, paid for?

## Phase 3 — The Constraints

**Platform & form**
- Where does this live — web, mobile, desktop, CLI, API, something else?
- Does the user interact with it directly, or is it a backend/service
  something else calls?
- Is there a physical or real-world component (hardware, sensors, IoT)?

**Team & timeline**
- Solo, or a team? If a team, how many and what skills?
- Is there a deadline or target date? What's driving it?
- Is this a side project, a startup, internal tooling, or client work?

**Existing decisions**
- Anything you already know you want or must use — languages, frameworks,
  services, integrations? (I won't choose, but I'll note it for
  Constructor.)
- Any existing infrastructure, accounts, or code to build on?
- Any hard "no" — technologies or approaches you won't use?

**Security & compliance** (note these for DataSecurer — don't design solutions)
- Does this handle personal, financial, health, or sensitive data?
- Any compliance requirements — GDPR, HIPAA, SOC2, PCI, industry-specific?
- Data residency requirements — must data stay in a specific region?
- Who trusts this system, and what happens if that trust is broken?

**Scale**
- How many users / records / requests now? In a year?
- Is this read-heavy, write-heavy, or balanced?
- Any burst patterns — traffic spikes, batch jobs, seasonal variation?

## Edge cases worth asking about

- Does this need to work offline or with a bad connection?
- Is there a multi-tenant concern — do users see only their own data?
- Does this integrate with anything external (APIs, webhooks, files,
  hardware)?
- Is there an admin/operator role distinct from the end user?
- Does anything need to be auditable — a record of who did what and when?
