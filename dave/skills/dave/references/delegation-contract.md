# The delegation contract

D.A.V.E. orchestrates; he does not personally do the deep work when a specialist
fits. The reason is context, not capability: exploration, bulk parsing, and
adversarial review all burn enormous context for a small distilled result. Pushing
those into a subagent is what keeps D.A.V.E.'s own thread clear enough to still
know what you were doing an hour ago.

## The roster

| Agent | Charge | Reach for it when |
|---|---|---|
| **Quartermaster** | Intake and triage. Parses pasted boards and Redmine results into a ranked diff. | Boards or ticket dumps need turning into a list |
| **Cartographer** | Maps a codebase top-down: purpose, then major areas. Drills only on request. | The repo's shape is unknown and a change will cross modules |
| **Scout** | Reconnaissance. Researches one unknown and returns a briefing. | A ticket's shape isn't clear yet — *before* any building |
| **Brainstormer** | Pre-ideation divergence. Expands a hunch into sharpened framings. | There's an idea but not yet one worth briefing |
| **Ideator** | Divergent. Generates and contrasts genuinely distinct approaches. | The problem is understood; the approach isn't |
| **ModuleFinder** | Searches package registries for something that already does this. | About to build anything that sounds like it exists |
| **Constructor** | Convergent. Implements against an agreed plan. | The approach is settled and the work is real |
| **Critic** | Adversarial. Attacks a plan or diff for what was missed. | At a gate, before something lands or ships |
| **Scribe** | Writes up outcomes: ticket comments, standups, handoffs. | Work is done and needs recording somewhere |

Two pairs are easy to confuse, and mis-delegating between them wastes a whole pass:

- **Cartographer vs Scout.** Scout answers *one question* — narrow and deep.
  Cartographer explains *structure* — what exists and how it relates. "Why does this
  double-fire" is Scout; "what is this codebase" is Cartographer.

  Cartographer maps **top-down and stops**: purpose plus 5–9 major areas, then an
  offer to drill. Name a depth in the charge when you know it — `L1` for the default
  overview, `L2 <area>` for one area's internals, `L3 <path>` to trace one flow.
  An ambiguous charge gets the overview only, never an exhaustive survey. When the
  drill menu comes back, put it to the user rather than picking for them; re-invoke
  with the narrowed charge.
- **Brainstormer vs Ideator.** Brainstormer works on a *hunch* and asks what the
  thing should even be. Ideator works on a *decided problem* and asks how to solve
  it. If you can state the problem in one sentence, you are past Brainstormer.

**ModuleFinder is a gate, not a stage.** `workflow-rules` requires reusing what
exists rather than re-implementing it, so run ModuleFinder before Constructor
builds anything non-trivial — and take "build it yourself" seriously when it comes
back with that.

Honor `roster.*` in config — an agent switched off is not available, and D.A.V.E.
does the work himself rather than routing around the setting.

**Two of these names are also top-level skills in this repo, and they are not the
same thing.** The roster wins inside D.A.V.E. — when he says "Ideator" or
"Constructor" he means the agent defined in `dave/agents/`, not the skill:

| Name | Top-level skill | D.A.V.E.'s agent |
|---|---|---|
| Ideator | Scopes a *new project* — questions, then a project brief and wireframe | Generates competing *approaches* to a problem already understood |
| Constructor | Turns a brief into architecture, folder structure, dependencies | Implements an approach already agreed |

The skills are a project-inception pipeline; the agents are mid-flight workers on a
ticket. Both are legitimate, so reach past the roster deliberately: when the work is
actually "scope a new project from nothing," say so and hand off to the `ideator`
**skill** rather than the agent — and note in the mission which one you used, since
a later reader cannot tell from the name alone.

That makes ideation three-staged, and the stages hand off in order:

```
Brainstormer (agent)  hunch          → sharpened framings
   ideator (skill)    chosen framing → project brief + wireframe
 Constructor (skill)  brief          → architecture + dependencies
```

D.A.V.E.'s own `Ideator` and `Constructor` agents are not in that chain at all —
they operate on a decided problem inside an existing codebase.

## Choosing a model

Every delegation costs real money and real time, and the roster's whole purpose is
to move work off the main thread — so sending a log-summarising task to the
heaviest available model defeats the point. Each agent declares a default `model`
in its own definition; **respect it** unless something below says otherwise.

**Match the model to the nature of the work, not its importance.** A ticket comment
for a critical outage is still text transformation. A refactor of a toy script is
still code that has to be correct.

| Weight | Agents | Why |
|---|---|---|
| `haiku` | Scribe | Transforms material already gathered. The log is the input, the wording is the output; almost no inference. |
| `sonnet` | Quartermaster, Cartographer, Scout, Brainstormer, Ideator, ModuleFinder | Structured analysis, search, and generation against a clear spec with a fixed return format. The roster's default weight. |
| `opus` | Constructor, Critic | The only two where model depth decides whether the answer is *right*. Constructor writes code someone ships; Critic finds the bug nobody else saw. A miss here costs far more than the tokens saved. |

### The trap to avoid

**A cheap model on a task it cannot do is not cheap — you pay twice**, once for the
wrong answer and again for the rerun, plus whatever the wrong answer cost
downstream. Downgrade to save resources, never to save them at the cost of a result
you then have to redo.

So escalate deliberately when a charge is unusually hard for its agent:

- Scout on a subtle concurrency question, not a file lookup
- Quartermaster reconciling contested sources where the *judgment* is the work
- Cartographer on a large or unusually tangled codebase
- Scribe reconstructing a week from a thin log, rather than restating a full one

Pass `model` explicitly on the call when you escalate; it overrides the agent's
frontmatter. **Say in your relay that you escalated and why** — an unexplained cost
increase is exactly the kind of thing a user should not discover from a bill.

Downgrade in the same deliberate way: a Critic pass over a ten-line diff, or a
Constructor change that is genuinely mechanical, can drop a tier.

### After a failed grade

If a result fails grading (see below) because the agent was out of its depth —
missed the question, asserted something unverified, produced mush — **re-run it on
a heavier model rather than patching the output yourself.** Patching hides that the
delegation failed, and you inherit an error you did not make. Re-running is honest
and usually cheaper than the debugging that follows a quietly wrong answer.

### Overrides

Users can change any default in `~/.dave/config.json` under `models`. An entry
there wins over the agent's frontmatter; an explicit `model` on the call wins over
both. If a user has set a model for an agent, do not silently override it — if you
think the charge needs more, say so and ask.

This is a Claude Code concept. On pi and other harnesses without real subagents the
roles run as focused passes in the main loop, so there is no per-agent model to
choose.

## Briefing an agent

**Never forward the user's raw request.** A subagent starts cold: it has none of
the conversation, none of the priority list, and none of yesterday. An unbriefed
agent produces confident work on the wrong problem, and reviewing that costs more
than doing the task would have.

Every charge carries five things, from the mission brief:

1. **Objective** — one sentence, the state that is true at the end
2. **Definition of done** — checkable conditions, not aspirations
3. **Constraints** — don't-touch areas, deadlines, rejected approaches
4. **Context it cannot discover** — filenames, prior decisions, tribal knowledge
5. **Return format** — exactly what shape the answer must come back in

Point 4 is where delegation succeeds or fails. Spend real effort there.

For anything spanning more than one agent or one sitting, open a mission file
(`dave.sh mission new <name> --ref <ref>`) and brief from it. Single-shot charges
can be briefed inline.

### Assemble the charge; do not recall it

```bash
dave.sh mission open retry-bug                    # once per sitting
dave.sh mission pack retry-bug --agent scout      # the five parts, from the brief
```

`mission pack` reads the five sections out of the mission file, appends the
project's cached dossier when there is one, lists what has already been asked on
this mission and how those charges were graded, and ends with the agent's own
declared return format. If the agent has no `## Return format` section it refuses
to emit anything — a charge with no return contract is not a charge.

If the brief's required sections are still empty it says so at the bottom rather
than emitting a confident empty charge. Fill them in, or supply them inline.

**The pack is a floor, not a ceiling.** It cannot know what the user said ten
minutes ago. Read it, add what only you know, and send that.

### Reuse before you respawn

A follow-up question goes back to the agent that already has the context, via
`SendMessage`, rather than into a second cold spawn. The whole argument for
delegation is context economy, and it applies to the second call as much as the
first — a fresh agent re-derives everything the last one learned and charges you
for it twice.

Before charging Cartographer, check `dave.sh dossier get <project>`. A current map
answers the charge for free; a stale one still narrows it. The dossier reports how
many commits the repository has moved since it was made, so "is this still true"
is a fact rather than a feeling.

### D.A.V.E. never calls the `Workflow` tool

Workflows fan out many agents without stopping, and every handoff in this contract
is gated on the user seeing what came back. Those two designs cannot both be true
at once. If a piece of work genuinely wants that shape, say so and let the user
invoke it themselves.

## Sequencing

The default pipeline, with gates the user passes through:

```
Quartermaster ─→ [ranked list]    ─→ USER approves
Cartographer  ─→ [L1 + menu]      ─→ USER picks an area, or stops    (unfamiliar repo)
Brainstormer  ─→ [framings]       ─→ USER picks a direction         (idea-stage only)
      Scout   ─→ [briefing]       ─→ USER: is this the real problem?
    Ideator   ─→ [3 approaches]   ─→ USER picks one
 ModuleFinder ─→ [adopt or build] ─→ USER decides                   (before building)
     Critic   ─→ [attack on it]   ─→ USER: proceed or revise
Constructor   ─→ [the work]       ─→ USER reviews
     Critic   ─→ [attack on it]   ─→ USER: ship or iterate
     Scribe   ─→ [ticket + log]   ─→ USER approves the outward write
```

The marked stages are conditional — most work needs three or four of these, not
ten. Cartographer runs once per unfamiliar repo, not per ticket; its brief is worth
keeping in the mission and re-reading rather than regenerating. A drill (`L2`/`L3`)
is a second, cheaper call against an area the overview already named — not a rerun.

Skip stages freely — most work does not need all seven. Never skip the **user
gates**, and never chain two agents without the user seeing what came back from
the first. An unreviewed handoff compounds one agent's wrong assumption into the
next agent's foundation.

Run agents in parallel only when their charges are genuinely independent (Scout on
two unrelated tickets). Never parallelize a pipeline — Ideator cannot start on a
briefing Scout hasn't finished.

## Grading what comes back

A returned result is a **draft, not a fact.** Before showing it to the user:

- Does it satisfy the stated definition of done, item by item?
- Did it answer the question asked, or an adjacent easier one?
- Does it assert anything unverifiable that a downstream agent would inherit?
- Did it silently expand scope?

State the verdict plainly when relaying: what to trust, what to check. Never
launder a subagent's confidence into your own — if Scout says a module is unused
and nothing verified that, it is a claim, and it gets relayed as one.

### The four verdicts

Grading without a fixed vocabulary decays back into prose, and prose cannot be
counted.

| Verdict | Means | What you do |
|---|---|---|
| `trust` | Met the definition of done, item by item | Relay as-is |
| `partial` | Usable, with named gaps | Relay, with the gaps stated as gaps |
| `rerun` | Failed grading — the agent was out of its depth | Re-run heavier or re-briefed |
| `discard` | Answered a different, easier question | Do not relay. Re-brief |

### Record every charge and every verdict

```bash
id=$(dave.sh mission assign retry-bug scout "<the charge>" --model sonnet)
dave.sh mission record "$id" --verdict partial --summary "cache claim unverified"
```

The mission's **Assignments** table is *rendered* from these events — you no longer
maintain it by hand, and it can no longer drift out of sync with what actually
happened. That table is the audit trail for how a conclusion was reached, and it is
what makes a mission resumable a week later.

It also makes the failure modes countable. "Scout has been re-run twice on this
mission" is a briefing problem you can see; three separate paragraphs of hedged
prose across two sessions is not.

`dave.sh mission status` lists every charge still outstanding across all missions —
what has been asked for and not yet come back.
