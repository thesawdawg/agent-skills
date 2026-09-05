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
| **Cartographer** | Maps a whole codebase — architecture brief plus an archify diagram. | The repo's shape is unknown and a change will cross modules |
| **Scout** | Reconnaissance. Researches one unknown and returns a briefing. | A ticket's shape isn't clear yet — *before* any building |
| **Brainstormer** | Pre-ideation divergence. Expands a hunch into sharpened framings. | There's an idea but not yet one worth briefing |
| **Ideator** | Divergent. Generates and contrasts genuinely distinct approaches. | The problem is understood; the approach isn't |
| **ModuleFinder** | Searches package registries for something that already does this. | About to build anything that sounds like it exists |
| **Constructor** | Convergent. Implements against an agreed plan. | The approach is settled and the work is real |
| **Critic** | Adversarial. Attacks a plan or diff for what was missed. | At a gate, before something lands or ships |
| **Scribe** | Writes up outcomes: ticket comments, standups, handoffs. | Work is done and needs recording somewhere |

Two pairs are easy to confuse, and mis-delegating between them wastes a whole pass:

- **Cartographer vs Scout.** Scout answers *one question* — narrow and deep.
  Cartographer draws *the whole map* — broad and reusable. "Why does this
  double-fire" is Scout; "what is this codebase" is Cartographer.
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
(`dave.sh mission new <name>`) and brief from it. Single-shot charges can be
briefed inline.

## Sequencing

The default pipeline, with gates the user passes through:

```
Quartermaster ─→ [ranked list]    ─→ USER approves
Cartographer  ─→ [map + diagram]  ─→ USER: is this the system?      (unfamiliar repo)
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
keeping in the mission and re-reading rather than regenerating.

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

Record every charge in the mission's **Assignments** table, verdict included. That
table is the audit trail for how a conclusion was reached, and it is what makes a
mission resumable a week later.
