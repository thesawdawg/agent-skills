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

Running [pi](https://pi.dev) instead? pi has no plugin system, no MCP, and no
hooks, so the pieces map onto its own mechanisms — see
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
| `/dave:intake [source]` | Ingests a board or Redmine, reconciles into one ranked list |
| `/dave:check` | An honest drift check, right now |
| `/dave:park <thing>` | Captures a distraction without acting on it |
| `/dave:delegate [agent] <task>` | Briefs a roster agent properly |
| `/dave:standup [days]` | Turns the day's log into a standup, ticket comment, or time entry |

**The roster**

| Agent | Charge | Writes? |
|---|---|---|
| `quartermaster` | Boards and tickets → one ranked diff | no |
| `scout` | Reconnaissance before building | no |
| `ideator` | Genuinely distinct approaches | no |
| `constructor` | Builds the agreed thing | **working tree only** |
| `critic` | Attacks a plan or diff for what was missed | no |
| `scribe` | Drafts ticket comments, standups, commits | no — drafts only |

Only the Constructor touches the working tree, and even it never commits. Every
outward write — Redmine status, comment, time log — is drafted, shown in full, and
sent only on an explicit yes for that specific write.

**A SessionStart hook** injects your current focus and Now list into every session,
so D.A.V.E. is present from the first token rather than waiting to be summoned.
It stays silent when he isn't set up, and `hooks.session_start: false` in the
config turns it off.

## State

Everything durable lives in `~/.dave/` (override with `DAVE_HOME`) as plain
markdown and JSON you can read and hand-edit. `skills/dave/scripts/dave.sh` is the
only thing that writes there.

```
~/.dave/
  config.json        identity, personality dials, Redmine authority, boards
  priorities.md      THE list — Now / Next / Blocked / Someday. Yours, not his.
  state.json         current focus, last intake, last brief
  parking-lot.md     captured detours, with what they pulled against
  log/YYYY-MM-DD.md  timestamped activity, stamped with the focus ref
  missions/<slug>.md multi-agent mission briefs and their assignment table
  intake/            raw archived boards, so intake is auditable
```

`dave.sh brief` is a composite read — identity, focus, priorities, today's log,
and parked items in **one** call, so orienting at session start costs one tool
call rather than five. Run `dave.sh help` for the full command list.

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
| `hooks.session_start` | Set false to make him speak only when invoked |
