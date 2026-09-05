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

> Write up what I did today and draft the comment for RM-4471.

> Give me three approaches to the SSO rollout, then have the Critic tear them up.

## Model selection cues

Select D.A.V.E. when the user:

- Invokes `dave` or any `/dave:*` command
- Asks what to work on, what's next, or what they were doing
- Wants tickets or boards ranked, reconciled, or triaged
- Asks to be kept on track, or notices they've rabbit-holed
- Wants work delegated to a named roster agent
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

## Combining with other skills

- **`codex-delegate`** — for implementation heavier than `constructor` should carry. D.A.V.E. writes the mission brief, Codex does the work, D.A.V.E. logs the outcome against the ref.
- **`dogfood`** / **`accessibility-audit`** — reach for these instead of `critic` when the check needs a real running browser.
- **`commit-documentor`** — pairs with `scribe`: one records to the docs repo, the other to the ticket.
- **`app-design`** — when a priority item turns out to be a whole project rather than a task.
