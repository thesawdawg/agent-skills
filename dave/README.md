# D.A.V.E.

**Digital Assistant for Various Endeavors** — an orchestrator plugin for Claude Code.

He holds one ranked priority list across Redmine and your kanban boards, keeps the
session pointed at it, delegates deep work to a roster of specialists, and records
what actually happened. The register is JARVIS: composed, competent, quietly
amused, and willing to argue with you when the work leaves the list.

The problem he exists for is the one that starts as "quick look at this" and ends
three repositories later with the ticket untouched.

See [USE_CASES.md](USE_CASES.md) for worked examples and
[skills/dave/SKILL.md](skills/dave/SKILL.md) for the operating loop.

## Install

Two routes. The second is likely what you want, since `~/.claude/skills/` is
already a clone of this repository.

**As a marketplace plugin:**

```bash
claude plugin marketplace add /apps/agent-skills && claude plugin install dave@agent-skills
```

**Or via the skills directory** — a plugin under `~/.claude/skills/` auto-loads
next session as `dave@skills-dir`, no install step:

```bash
git -C ~/.claude/skills pull
```

Then set him up. First run detects an unconfigured state and walks you through it:

```bash
/dave:brief
```

Requires `jq`.

### Other harnesses

Running [pi](https://pi.dev) instead? pi has no plugin system and no hooks, and no
MCP unless you add the `pi-mcp-adapter` extension — so the pieces map onto its own
mechanisms — see
**[INSTALL-PI.md](INSTALL-PI.md)** for the full guide and the honest account of
what does and doesn't carry over. The short version:

```bash
./scripts/install-pi.sh --with-agents-md
```

## What you get

**Commands**

| Command | Does |
|---|---|
| `/dave:brief` | Orients you — focus, what's in Now, what's stale, what's parked |
| `/dave:focus <ref>` | Locks onto one item so drift can be measured against it |
| `/dave:project [slug]` | Registers or reports on a project — the container an item belongs to |
| `/dave:mission [slug]` | Opens, inspects or closes a mission, and shows what's still owed |
| `/dave:intake [source]` | Ingests a board or Redmine, reconciles into one ranked list |
| `/dave:check` | An honest drift check, right now |
| `/dave:park <thing>` | Captures a distraction without acting on it |
| `/dave:delegate [agent] <task>` | Briefs a roster agent properly |
| `/dave:standup [days]` | Turns the day's log into a standup, ticket comment, or time entry |

**The roster**

| Agent | Charge | Model | Writes? |
|---|---|---|---|
| `quartermaster` | Boards and tickets → one ranked diff | sonnet | no |
| `cartographer` | Codebase map, top-down: purpose → areas → drill on request | sonnet | its own artifacts |
| `scout` | Reconnaissance on one question, before building | sonnet | no |
| `brainstormer` | Expands a hunch into sharpened framings | sonnet | no |
| `ideator` | Genuinely distinct approaches to a decided problem | sonnet | no |
| `module-finder` | Finds an existing package instead of rebuilding it | sonnet | no — never installs |
| `constructor` | Builds the agreed thing | **opus** | **working tree only** |
| `critic` | Attacks a plan or diff for what was missed | **opus** | no |
| `scribe` | Drafts ticket comments, standups, commits | haiku | no — drafts only |

Models are sized to the *nature* of each charge, not its importance: `haiku` for
transforming material already gathered, `sonnet` for structured analysis against a
fixed return format, `opus` only where model depth decides whether the answer is
right. Delegating exists to move work off the main thread — running all of it on the
heaviest model defeats that. Override any of them under `models` in the config.

Only the Constructor touches the working tree, and even it never commits.
Cartographer writes only its own brief and diagram; ModuleFinder never installs
anything.

`cartographer` maps **top-down and stops**: what the system is for, then its 5–9
major areas, then an offer to drill into one. It does not survey an entire
repository on an ambiguous request — that produces a document nobody reads and is
stale in a week. Ask for `L2 <area>` or `L3 <path>` when you want depth.

Its diagram half needs the [`archify`](https://github.com/tt-a1i/archify) skill:

```bash
npx skills add tt-a1i/archify -g
```

Without it you still get the written brief, and it says the diagram is missing
rather than inventing a picture.

Every outward write — Redmine status, comment, time log — is drafted, shown in full,
and sent only on an explicit yes for that specific write.

**A SessionStart hook** injects the project you're in, your current focus, where
you left it, anything promised and coming due, and the Now list into every session,
so D.A.V.E. is present from the first token rather than waiting to be summoned.
It stays silent when he isn't set up, and `hooks.session_start: false` in the
config turns it off.

## State

Everything durable lives in `~/.dave/` (override with `DAVE_HOME`) as plain
markdown and JSON you can read and hand-edit. It sits beside `~/.agents/` rather
than inside it deliberately: `~/.agents/` holds *configuration* that skills read,
while this is a working document you edit yourself every day and will want to find,
back up, and version on its own. Set `DAVE_HOME=~/.agents/dave` if you'd rather
keep everything under one roof. `skills/dave/scripts/dave.sh` is the
only thing that writes there.

```
~/.dave/
  config.json        identity, personality dials, Redmine authority, boards
  priorities.md      THE list — Now / Next / Blocked / Someday. Yours, not his.
  state.json         current focus and its stack, last intake, drift events
  parking-lot.md     captured detours, with what they pulled against
  notes.json         where you left off, per ref
  commitments.json   what you promised, to whom, by when
  sessions.jsonl     the time ledger — one record per closed focus
  log/YYYY-MM-DD.md  timestamped activity, stamped with the focus ref
  projects/<slug>/   goal, cadence, linked refs, cached codebase dossier
  missions/<slug>.md multi-agent mission briefs; the assignment table is rendered
  missions.json      per-mission project, ref, status
  assignments.jsonl  every charge and every verdict, append-only
  intake/            raw archived boards, so intake is auditable
  scan-cache.json    last known git state per project (regenerated, disposable)
```

`dave.sh brief` is a composite read — the project you're standing in, focus,
priorities, today's log, promises coming due and parked items in **one** call, so
orienting at session start costs one tool call rather than five. Run
`dave.sh help` for the full command list.

**Time is recorded, not estimated.** Every closed focus banks a segment, and
`dave.sh time <ref>` reports the total *and* how much of it has no log activity
behind it. Scribe quotes both, because a time entry that quietly rounds unverified
minutes into the total becomes someone's billing data.

**A delegation is a record, not a paragraph.** `mission assign` returns an id;
`mission record` grades it `trust`/`partial`/`rerun`/`discard`. The mission's
Assignments table is rendered from those events, so it cannot drift out of sync
with what actually happened, and `mission status` says what has been asked for and
never came back.

**Projects are a facet, not a second list.** `dave.sh project add <path>` registers
one; the session-start hook then leads with the project you're actually sitting in.
Rank stays global — a per-project ranking would let three projects each hold a
number-one item, which is the problem this exists to solve.

## Design notes

**One list, four sections.** `Now` is capped (default 3) and *is* the operative
definition of on-track. Filling it requires taking something out, and he asks
which rather than quietly expanding the cap.

**Drift is not "unplanned work."** That's often correct. Drift is unplanned work
*you didn't decide on*. A deliberate detour is a decision, and decisions get
respected and logged, not re-litigated. When drift does trigger, the protocol is
fixed: name it in one sentence with the concrete number, offer **park / promote /
continue**, act on the answer, drop it. At most once per episode — a settled
objection raised twice is how this plugin becomes something you uninstall.

**Boards are stale by default.** There's no kanban API; you paste them in. Board
age is tracked and surfaced, and a drift call that depends on week-old board data
asks for a fresh board instead of being confidently wrong about your priorities.

**Delegation is briefing, not forwarding.** A subagent starts cold. Every charge
carries objective, definition of done, constraints, the context it can't discover,
and the return format. That fourth item is where delegation succeeds or fails.

**Nothing outward is automatic.** Redmine writes and rewrites of `priorities.md`
both require your explicit approval, per write. He never invents hours — if the log
is thin he asks, because a fabricated time entry is a false record in your team's
system.

## Configuration

`~/.dave/config.json`, created on first run from
[the template](skills/dave/templates/config-template.json). The dials worth
knowing:

| Key | Effect |
|---|---|
| `user.address_as` | What he calls you — `"sir"`, your name, or `""` |
| `personality.wit` | `dry` (default) · `light` · `off` |
| `personality.pushback` | `firm` (default) · `gentle` · `off` |
| `redmine.authority` | `read-only` · `propose-writes` (default) · `auto-routine` |
| `priorities.max_now` | How many things may sit in Now (default 3) |
| `priorities.drift_threshold_minutes` | How long unlisted work runs before he says something (default 45) |
| `kanban.stale_after_days` | When a board's age gets flagged (default 7) |
| `roster.<agent>` | Set false to take an agent off the roster |
| `models.<agent>` | Which model that agent runs on — `haiku` / `sonnet` / `opus` / `inherit` |
| `hooks.session_start` | Set false to make him speak only when invoked |
