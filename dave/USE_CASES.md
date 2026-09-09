# D.A.V.E.: Practical Use Cases

This guide shows **when D.A.V.E. is the right thing to reach for**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [README.md](README.md) for installation and architecture, [INSTALL-PI.md](INSTALL-PI.md) for running him under the [pi](https://pi.dev) harness, [skills/dave/SKILL.md](skills/dave/SKILL.md) for the full operating loop, and the [top-level skills index](../USE_CASES.md).

The defining mechanic: **one ranked list, in one file, spanning every source**. Redmine tickets and kanban cards are *inputs* to `~/.dave/priorities.md` — never the list itself, because neither system knows about the other and neither knows what you promised someone in a hallway. Everything else D.A.V.E. does (focus, drift, delegation, standups) measures against that one file.

## Use it when

Use D.A.V.E. when the problem is **which work, in what order, and did you stay on it** — not when the problem is the work itself.

Good uses include:

- Starting a session and needing to know what you were doing and what's next
- A pile of Redmine tickets and a kanban board that need to become one ordered list
- Catching yourself three repositories deep with the actual ticket untouched
- Handing a well-briefed task to a specialist agent instead of doing it in your main context
- Reconstructing an honest standup or ticket comment from what actually happened
- Capturing a good idea at 4pm without letting it eat the rest of the afternoon

Do not use D.A.V.E. to write the code (that's `constructor`, or `codex-delegate` for heavier work), to review a diff for bugs (`/code-review`), or as a general chat wrapper. If you know exactly what you're doing and you're doing it, he has nothing to add — and he should say so in four words rather than manufacture a concern.

## User examples

> /dave:brief

> What should I be working on?

> Here's my board — reconcile it with my Redmine tickets and tell me what's actually top.

> Am I still on track?

> I keep getting pulled into the cache thing. Park it.

> Have the Scout figure out why the retry middleware double-fires before I touch it.

> Map this repo before I touch it — I've never seen it.

> Before we build a CSV parser, check whether something already does this.

> I've got a vague idea about tracking invoices. Help me work out what it even is.

> Write up what I did today and draft the comment for RM-4471.

> Give me three approaches to the SSO rollout, then have the Critic tear them up.

## Model selection cues

Select D.A.V.E. when the user:

- Invokes `dave` or any `/dave:*` command
- Asks what to work on, what's next, or what they were doing
- Wants tickets or boards ranked, reconciled, or triaged
- Asks to be kept on track, or notices they've rabbit-holed
- Wants work delegated to a named roster agent
- Needs an unfamiliar codebase mapped, or a dependency found instead of written
- Has a hunch that isn't yet an idea worth planning
- Wants a standup, time log, or ticket comment drafted from real activity

Do not select it when the user is mid-task and asking a direct technical question. Answer the question. D.A.V.E.'s value is entirely in the moments *between* tasks, plus one well-timed interruption during them.

## Inputs to establish before starting

| Input | Why it matters |
|---|---|
| Is `~/.dave/config.json` present? | `dave.sh config` exits **3** if not — run first-run setup before anything else |
| Is the Redmine MCP actually available? | Discover with `ToolSearch: "+redmine issue query"`. Never assume tool names; never fabricate ticket data if it's absent |
| How old is the last intake? | Boards arrive by hand and go stale. A confident ranking on week-old data is worse than an admitted gap |
| What's in **Now**, and what's the cap? | Now *is* the definition of on-track. An empty list means drift detection is meaningless — say so |
| `personality.wit` / `personality.pushback` | Governs tone and how hard he presses. Read it, honor it |

## Example: a reconcile and a drift call

> **User:** Here's the platform board *(pastes it)*. What should I actually be on today?

A good run:

1. **Archive first.** `dave.sh intake "platform board"` — the raw paste is saved before anything parses it, so a later disagreement about what a card said is resolvable.
2. **Discover Redmine**, pull open assigned issues — id, subject, status, due date, last update only. Not full descriptions; forty full tickets to rank them is exactly the context burn that makes him forget what you were doing.
3. **Delegate to `quartermaster`** with the current list, the raw board, the ranking factors, and `max_now`. Bulk parsing does not belong in the main context.
4. **Grade the return**, then show the **diff** — new / moved / gone / stale / contested — never a silent rewrite.
5. **Get a yes**, write `priorities.md`, set focus.

Then, ninety minutes later, in the same session, the third unrelated repository:

> Fifty minutes on the CSV exporter now, and RM-4471 hasn't moved since this morning — it's the one due Thursday. Happy to keep going; shall I park this, promote it, or is it just displacing the ticket for today?

The user says "park it" — so `dave.sh park`, one line of confirmation, back to RM-4471, and **it is never raised again**. That last part is the whole design. A settled objection re-raised is how this plugin becomes something you turn off.

## Sample output

```
Morning. RM-4471 is still the only thing in Now — due Thursday, and you left it
mid-way through the retry middleware yesterday at 16:40.

Two things worth knowing: the platform board is from the 28th, so anything I say
about its ranking is nine days stale. And KB-platform-sso-rollout is marked
blocking two people, which under your own ranking beats the exporter work you
parked on Tuesday.

Suggest RM-4471 to done, then a fresh board before we re-rank. Shall I set focus?
```

## Example: coming back to a project after a week

> **User:** *(opens a session in `~/Projects/webcrawler`)* where was I?

The hook has already put the answer in context, so this costs no tool calls at all:

```
Project: webcrawler — active, daily cadence
Goal: crawl politely without getting the IP banned
Its refs: RM-4471
Git: retry-fix, 3 dirty/1 untracked, last commit 6d ago

Promised: Maya — SSO demo build (OVERDUE)

Current focus: RM-4471 — retry double-fire (since last Tuesday)
Left off at: instrument the retry middleware ~line 88
```

A good run leads with the overdue promise, not the branch — a commitment to a
person outranks everything else in the ranking model, and it is the one thing here
the user cannot see for themselves. Then the concrete resumption point, then the
uncommitted work sitting on a six-day-old branch.

What made that possible was one line at the end of the previous session
(`dave.sh next set RM-4471 "..."`) and one when the promise was made. Neither is
something D.A.V.E. can reconstruct afterwards, which is why he offers to capture
them at the moment they exist and never blocks on the answer.

## Example: picking a mission back up a week later

> **User:** what was I doing on the retry bug, and what did the Scout actually say?

`dave.sh mission show retry-bug` answers both without re-reading anything:

```
## Assignments

| Id | Agent | Charge | Returned | Verdict |
|---|---|---|---|---|
| retry-bug#1 | scout | why does the retry middleware double-fire | 2026-09-02 | partial — found it; the cache claim is unverified |
| retry-bug#2 | critic (opus) | attack the fix before it lands | — | **open** |
```

Two things this makes possible that prose in a transcript does not. The verdict is
still attached to the charge, so "the cache claim is unverified" has not quietly
become a fact in the intervening week. And `retry-bug#2` is visibly still owed —
a charge sent out and never graded is the single most forgettable thing in this
whole system, which is why `dave.sh mission status` exists to list them.

Charging the Critic again starts from `mission pack retry-bug --agent critic`,
which carries the objective, the done conditions, the undiscoverable context, the
project's cached codebase map, *and* what the Scout already found and how it
graded — so the second agent does not re-derive the first agent's work.

## Example: the Monday sweep

> /dave:review

```
Since 2026-09-01: 11h20m recorded (1h05m of it unverified).

Slipping:
  Maya — SSO demo build, due 2026-09-06 (OVERDUE)
  webcrawler — weekly cadence, nothing for 24d, 3 uncommitted files

Owed:
  sso-rollout — 1 charge(s) outstanding, oldest sent 9d ago

Rotting:
  4 parked items older than the review threshold — oldest: rewrite the CSV exporter
  AD-cache-warmup first logged 11d ago and still has no ticket

Quiet and fine:
  agent-skills (daily), gnome-music (maintenance), dnd-5e-api (dormant)

Drift: 6 drift call(s): third-repo ×4, unlisted ×2 — 4 of them into webcrawler
```

Three things about that output are deliberate.

**"Quiet and fine" is load-bearing.** `gnome-music` has not been committed to in two
months and that is the arrangement working, not a finding — it is on a `maintenance`
status with a `monthly` cadence. A sweep that listed it as a problem would be wrong,
and a sweep that is wrong three times stops being read.

**Drift is a pattern, not a scolding.** "Four of six went into webcrawler" is a fact
about the work. D.A.V.E. does not follow it with an observation about focus; the
persona forbids commenting on the user's character, and the review is not an
exception to that.

**What closed is not in there.** Closure is not recorded anywhere in the state tree,
so the sweep says so rather than inferring it from the log and sounding certain.
An inference presented as a record is the exact failure this design is built to
avoid.

## Combining with other skills

- **`codex-delegate`** — for implementation heavier than `constructor` should carry. D.A.V.E. writes the mission brief, Codex does the work, D.A.V.E. logs the outcome against the ref.
- **`archify`** — required by `cartographer` for the diagram half of a codebase map (`npx skills add tt-a1i/archify -g`). Cartographer analyses and hands over topology; archify owns the schema, layout and validation. Without it the brief still lands, minus the picture.
- **`ideator` / `constructor` skills** — the project-inception pipeline `brainstormer` hands off to. Brainstormer sharpens the hunch, `/ideator` briefs it, `/constructor` designs it. Distinct from D.A.V.E.'s same-named agents, which work a decided problem inside an existing codebase.
- **`dogfood`** / **`accessibility-audit`** — reach for these instead of `critic` when the check needs a real running browser.
- **`commit-documentor`** — pairs with `scribe`: one records to the docs repo, the other to the ticket.
- **`app-design`** — when a priority item turns out to be a whole project rather than a task.
