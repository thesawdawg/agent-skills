# D.A.V.E. — implementation plan: projects, instrumentation, orchestration, cadence

_Draft for review. Covers recommendations **A–D** from the design review._

Working document, not plugin content. Delete it or fold it into `README.md` once
the work lands.

---

## 1. Scope

| In | Out |
|---|---|
| **A** — a project layer, and cwd → project resolution | **E** — `~/.dave` as a git repo, structured `done`/`promote` mutations, GNU-only `date -d`/`sed`, `brief` side effects |
| **B** — time ledger, focus stack, commitments, next-action notes, git scan | **F** — renaming `ideator`/`constructor` agents off the skill collision, trimming the roster |
| **C** — mission assignment ledger, briefing packs, dossier cache, delegation doctrine | |
| **D** — the weekly sweep and its cadence | |

Two out-of-scope items reach into this plan and are called out where they land:

- **F's `allowed-tools` check is a hard pre-flight for C.** If the subagent tool in
  the installed Claude Code build is named `Agent` rather than `Task`, four
  commands cannot delegate at all and everything in Phase C is decoration. Checked
  in Phase 0.
- **E's structured mutations make D's sweep meaningfully better.** Without a
  recorded `done <ref>`, "what closed this week" is inferred from the log rather
  than known. Phase D ships without it and says so in its own output.

---

## 2. Decisions needed before Phase 0

These change the shape of the work. My recommendation is first in each list.

### Decision 1 — implementation language for the state layer

`dave.sh` is 312 lines today. A–D roughly triples it: event folding, git scanning,
and the review sweep are all more code than `park` and `log` were.

- **Stay bash + jq, split into `scripts/lib/*.sh` sourced by `dave.sh`.** _(recommended)_
  The plugin's value proposition is "plain files you can hand-edit and one script
  you can read". A Python rewrite is a rewrite, and it adds a dependency claim the
  README currently doesn't make.
- Rewrite the state layer in Python 3. Genuinely easier for the fold-and-sweep
  logic, near-universal availability, but throws away working, reviewed code and
  the "requires `jq`" promise becomes "requires Python".

Recommended split:

```
scripts/dave.sh          dispatch + help only
scripts/lib/common.sh    paths, die, jq helpers, slugify, json_edit, jsonl_append
scripts/lib/focus.sh     focus stack + time ledger
scripts/lib/project.sh   project registry, resolution, scan, dossier
scripts/lib/mission.sh   missions, assignments, packs
scripts/lib/review.sh    the sweep
```

### Decision 2 — do projects own refs, or do priority items name projects?

- **Projects own refs: `project.json` carries a `refs` array.** _(recommended)_
  `priorities.md` stays exactly as it is — no format change, no markdown parsing,
  no risk to the one file the user hand-edits most. Mapping is one direction and
  lives in structured state.
- Priority item lines gain a `· <project>` field. Reads nicer in the file, but now
  the ranked list has a parseable schema and every intake has to preserve it.

### Decision 3 — where mission metadata lives

- **One `missions.json` map, slug → metadata; assignments in a global
  `assignments.jsonl`.** _(recommended)_ Two files to fold, no per-mission sidecar
  sprawl, and `mission status` across all missions is one read.
- Per-mission `missions/<slug>.json` sidecars. More files, but each mission stays
  self-contained and hand-portable.

### Decision 4 — how honest is the time ledger allowed to be?

Wall-clock between `focus set` calls is not hours worked; lunch happens. Scribe is
forbidden from inventing hours, so an over-counting ledger is worse than none.

- **Record raw segments, cap them on read, and label unverified time.** _(recommended)_
  A segment with no log activity inside it is reported separately:
  `3h10m recorded, 45m of it with no log activity`. Scribe gets a basis *and* the
  caveat, which is exactly what its evidence rule already asks for.
- Only count time within `work_hours` and drop the rest. Cleaner numbers, but it
  silently discards real evening work.

---

## 3. Target state layout

After all four phases. Everything still plain, still hand-editable.

```
~/.dave/
  config.json                 # + projects.*, parking.*, review.* blocks
  state.json                  # schema_version 2: focus_stack, active_mission, drift_events
  priorities.md               # UNCHANGED format
  parking-lot.md              # unchanged
  notes.json                  # ref → next physical action                       (B)
  commitments.json            # promises made to people                          (B)
  sessions.jsonl              # append-only time ledger                          (B)
  assignments.jsonl           # append-only delegation ledger                    (C)
  missions.json               # slug → {project, ref, status, opened, closed}    (C)
  scan-cache.json             # git scan results + TTL                           (B)
  log/YYYY-MM-DD.md           # unchanged, + mission stamp on lines
  intake/YYYY-MM-DD-<src>.md  # unchanged
  missions/<slug>.md          # unchanged template; Assignments table now rendered
  projects/<slug>/
    project.json                                                                 (A)
    dossier.md                # cached Cartographer L1 + the HEAD it was made at (C)
```

---

## 4. Phase 0 — pre-flight and foundations

**Goal:** verify the delegation path works at all, and lay the plumbing every later
phase uses.

### 0.1 Pre-flight checks

1. **Subagent tool name.** Confirm whether this Claude Code build exposes the
   subagent tool as `Task` or `Agent`. `brief.md`, `intake.md`, `standup.md` and
   `delegate.md` all declare `allowed-tools: [..., "Task", ...]`. If the name is
   stale, delegation fails silently — no error, just an orchestrator that never
   orchestrates. **Fix before Phase C.** One-line change per command file.
2. **`jq` version.** `--argjson` and `input_line_number` usage below assume jq ≥ 1.6.
3. Decide whether to declare Linux-only in the README, or defer (this is E).

### 0.2 Schema version and migration

- Add `schema_version: 2` to `state.json`.
- `require_init` gains a version check: a v1 state file triggers
  `dave.sh migrate`, which creates the new files, converts `.focus` into a
  one-element `.focus_stack`, and stamps the version. Idempotent.
- Exit code **4** = "set up, but schema is behind". Distinct from exit 3
  ("not set up"), which the skill already keys on.

### 0.3 Shared helpers (`scripts/lib/common.sh`)

```bash
jsonl_append <file> <json>     # single-line append, creating the file if absent
jsonl_fold <file> <jq-prog>    # slurp + reduce, tolerating a truncated last line
json_get <file> <path> [dflt]  # read with a default, never fails the script
config_get <path> [default]    # config.json accessor honoring absent keys
now_iso / today / slugify      # moved from dave.sh unchanged
git_probe <path>               # branch, dirty, ahead/behind, last commit — or "notagit"
```

`jsonl_fold` tolerating a truncated final line matters: an append interrupted
mid-write must not poison every later read.

### Acceptance

- `dave.sh migrate` on a v1 tree produces a v2 tree with no data loss; running it
  twice changes nothing.
- `dave.sh help` lists every command in the plan.
- All existing commands (`brief`, `focus`, `park`, `log`, `standup`, `mission`,
  `intake`) behave identically to today.

---

## 5. Phase A — the project layer

**Goal:** Dave can name, resolve and report on a project. The session that opens in
`~/Projects/webcrawler` knows it is in webcrawler.

### A.1 `projects/<slug>/project.json`

```json
{
  "slug": "webcrawler",
  "name": "Web Crawler",
  "path": "/home/sawyer/Projects/webcrawler",
  "status": "active",
  "goal": "one sentence — what finishing looks like",
  "refs": ["RM-4471", "KB-platform-sso-rollout"],
  "cadence": "weekly",
  "added": "2026-09-08",
  "last_touched": "2026-09-08T14:02:11-04:00"
}
```

`status`: `active` | `paused` | `maintenance` | `archived`.

`cadence` (`daily` | `weekly` | `monthly` | `dormant`) is what keeps the Phase D
sweep from becoming noise. Without it every quiet project looks like a problem;
with it, silence on a `maintenance` project is correct and silence on a `daily`
project is a finding.

### A.2 Commands

```
project add <path> [--name N] [--slug S] [--cadence C] [--goal "..."]
project list [--status active]        # table, or --json
project show <slug>                   # config + refs + latest scan + open missions
project status <slug> <status>
project link <slug> <ref>             # and: project unlink
project of <ref>                      # reverse lookup, prints slug or nothing
project resolve [path]                # cwd → slug; walks up to a git root, matches
                                      # registered paths by realpath; silent if none
project touch <slug>                  # stamp last_touched
```

`project add` with no `--slug` derives one from the directory name. `project add`
on an unregistered path that is not a git repo still works — not every project is
a repo.

### A.3 Config additions

```json
"projects": {
  "root": "/home/sawyer/Projects",
  "autodiscover": false,
  "use_gh": false,
  "dossier_stale_commits": 50
}
```

`autodiscover: true` lets `project list` surface unregistered directories under
`root` as candidates — suggested, never auto-added. Registration stays a decision.

### A.4 Hook change (`hooks/session-start.sh`)

Add, before the existing block:

1. `dave.sh project resolve "$PWD"`.
2. **Match:** emit a project block first — project name and goal, its focused ref,
   its next action (Phase B), open missions (Phase C), and one line of git state
   (Phase B) — then the global Now list, shortened.
3. **No match:** exactly today's behavior, byte for byte.

The hook's existing discipline holds: silent when unconfigured, silent when
`hooks.session_start` is false, and the "you are not D.A.V.E. unless invoked"
clause stays exactly as written.

Budget: the injected block must stay under ~25 lines. It is paid for on every
session in every directory, including ones that have nothing to do with Dave.

### A.5 Skill and command changes

- `SKILL.md` → step 1 of the operating loop becomes "Orient — project first, then
  list". `brief` output leads with the resolved project when there is one.
- New `/dave:project` command: register, switch, show, set status. Keeps command
  sprawl down by covering all four verbs in one.
- `brief` gains a project section when `project resolve` hits.

### Acceptance

- `dave.sh project add ~/Projects/webcrawler` then `project resolve
  ~/Projects/webcrawler/src/deep/dir` prints `webcrawler`.
- `project resolve /tmp` prints nothing and exits 0.
- Starting a session in a registered project injects the project block; starting
  one in `/tmp` injects exactly what it injects today.
- `project show` on a project with no refs, no missions and no git remote does not
  error.

---

## 6. Phase B — instrumentation

**Goal:** the rules Dave already enforces get the data they need. Nothing here is a
new rule; it is all backfill for rules already written.

### B.1 Focus stack (`state.json`)

```json
"focus": {"ref": "RM-4471", "label": "retry double-fire", "started": "...", "project": "webcrawler"},
"focus_stack": [ { ...parent focus... } ]
```

`.focus` remains the current top so the hook and `drift` keep working unchanged.

```
focus push <ref> [label]   # parent to the stack, close its time segment
focus pop                  # restore parent, open a new segment for it
focus set <ref> [label]    # unchanged: replaces the top, does not stack
focus clear                # close the segment, empty the stack
```

This makes the drift protocol's third door real: **continue** should `push`, not
overwrite. Today a deliberate detour destroys the parent focus and its timer.

`focus set|push` resolves `--project` automatically via `project of <ref>`, falling
back to `project resolve $PWD`.

### B.2 Time ledger (`sessions.jsonl`)

One line per closed segment:

```json
{"ref":"RM-4471","label":"retry double-fire","project":"webcrawler","start":"...","end":"...","minutes":94,"log_lines":6}
```

Written on `focus set`, `focus push`, `focus pop`, `focus clear`.

**Open-segment handling (Decision 4).** The current focus has no `end`. On read,
`dave.sh time` closes it at `min(now, start + time.max_segment_minutes)` — default
240 — and reports it as open. A focus left set overnight contributes four hours,
flagged, not sixteen silently.

**Unverified time.** `log_lines` counts log entries falling inside the segment. A
segment with zero is real elapsed time with no evidence behind it, and `time`
reports the split:

```
$ dave.sh time RM-4471 --since 2026-09-01
RM-4471  6h20m across 5 segments
         4h55m with log activity · 1h25m unverified (2 segments)
         open now: 38m (since 14:02)
```

That split is what Scribe needs. Its evidence rule already says never estimate;
this gives it something to not-estimate *from*.

```
time [ref] [--since DATE] [--project P] [--json]
```

### B.3 Next-action notes (`notes.json`)

```json
{ "RM-4471": {"text": "instrument retry middleware ~line 88", "updated": "...", "project": "webcrawler"} }
```

```
next set <ref> "<text>"
next show [<ref>|--project <slug>]
next clear <ref>
```

Cheapest item in the plan and the largest daily payoff: it removes the
re-orientation cost that makes people abandon systems like this. Surfaced by
`brief`, by the session hook, and by `project show`.

**Where it gets captured:** the skill instructs Dave to record a next action when
focus changes or a session winds down — `focus clear` and `focus push` are the
natural prompts. Never blocking; if the user does not answer, no note is written.

### B.4 Commitments (`commitments.json`)

```json
[{"id":"c7","who":"Maya","what":"SSO demo build","due":"2026-09-12","ref":"RM-4471",
  "project":"webcrawler","status":"open","created":"...","closed":null}]
```

```
promise add "<who>" "<what>" <due> [--ref R] [--project P]
promise list [--open] [--due-within N]
promise keep <id> | promise miss <id> | promise move <id> <new-due>
```

`brief` surfaces open promises due within `review.promise_horizon_days` (default 3).
This is what makes ranking factor #1 — "a commitment made to someone", deliberately
ranked above deadlines — something Dave can actually see rather than something the
user has to remember to type into a priority line.

### B.5 Git scan (`scan-cache.json`)

```
scan [slug] [--json] [--fresh]
```

Per active project: branch, dirty file count, untracked count, ahead/behind, last
commit date and subject, count of branches with no commit in 30 days.

- Uses `git -C <path> --no-optional-locks`, never `fetch` — ahead/behind is against
  the last-known remote ref, and the output says so rather than implying a fetch.
- Results cached with `projects.scan_ttl_seconds` (default 300) so `brief` and the
  hook never pay for a cold walk.
- A path that is not a repo, or is gone, is reported as such and never fatal.
- Optional: `gh pr list --json` when the remote is GitHub and `projects.use_gh` is
  true and `gh` is on PATH. Degrades silently on any failure.

This is the one signal that is always current. Boards are stale by design and
Redmine needs an MCP; git is sitting right there, and it is how the sweep in Phase D
knows a project has gone quiet without being told.

### B.6 Drift events

`state.drift_events` is declared in `init` today and never written. Give it a
writer:

```
drift record <kind> <outcome> [--ref R] [--project P]
   kind:    unlisted | third-repo | parked-resurfaced | no-focus
   outcome: parked | promoted | continued
```

The skill calls this when a drift episode resolves. It costs one call per episode
and buys the Phase D sweep a real line: _"six drift calls this week, four of them
into webcrawler while RM-4471 was in Now."_ That is a pattern the user can act on;
a single in-session nudge is not.

### Acceptance

- `focus set A` → `focus push B` → `focus pop` leaves focus on A, with two segments
  for A and one for B in `sessions.jsonl`.
- A focus set 9 hours ago and never closed reports as capped and open, not 9h.
- `time RM-4471` on a ref with no segments prints zero and exits 0.
- `scan` on a 4-project tree completes in under 2s cold, under 50ms cached.
- `scan` with one project path deleted reports that project as missing and still
  scans the rest.

---

## 7. Phase C — orchestration as a mechanism

**Goal:** a delegation is a recorded object, and a mission survives a session
boundary without depending on the model's diligence with a markdown table.

**Blocked on Phase 0.1.** If the subagent tool name is stale, fix it first.

### C.1 Assignment ledger (`assignments.jsonl`)

Event-sourced, append-only, two event types:

```json
{"type":"assign","id":"sso-rollout#3","mission":"sso-rollout","agent":"scout",
 "model":"sonnet","charge":"...","project":"webcrawler","ref":"RM-4471","ts":"..."}
{"type":"record","id":"sso-rollout#3","verdict":"partial",
 "summary":"answered the question; the claim about the cache layer is unverified","ts":"..."}
```

```
mission assign <mission> <agent> "<charge>" [--model M] [--ref R]   # prints the id
mission record <id> --verdict V [--summary "..."]
mission status [mission]     # open assignments, oldest first
```

**Verdict vocabulary** — defined, because "graded" without a fixed vocabulary
becomes prose again:

| Verdict | Meaning | What Dave does |
|---|---|---|
| `trust` | Met the definition of done, item by item | Relay as-is |
| `partial` | Usable, with named gaps | Relay with the gaps stated as gaps |
| `rerun` | Failed grading — out of its depth | Re-run heavier or re-briefed, per the contract |
| `discard` | Answered a different, easier question | Do not relay; re-brief |

`rerun` and `discard` are the two the contract already describes in prose and has
no way to count. Once counted, "Scout has been re-run twice on this mission" is a
briefing problem you can see.

### C.2 The Assignments table becomes rendered, not maintained

`mission show <slug>` prints `missions/<slug>.md` with the Assignments table
**generated** by folding `assignments.jsonl`. The template keeps its table as a
placeholder for hand-editing, but Dave stops being responsible for keeping a
markdown table in sync — which is the current design's most likely silent failure.

### C.3 Mission metadata (`missions.json`)

```json
{ "sso-rollout": {"project":"webcrawler","ref":"RM-4471","status":"open",
                  "opened":"2026-09-08","closed":null} }
```

```
mission new <name> [--project P] [--ref R]     # unchanged output: prints the path
mission open <slug>                            # sets state.active_mission
mission close <slug> [--outcome "..."]
mission list [--open] [--project P]
```

`state.active_mission` stamps `log` lines, so `mission show` can fold in the log
entries belonging to the mission. That closes the loop between "what happened" and
"what we asked for".

### C.4 Briefing packs

```
mission pack <mission> --agent <name> [--extra "..."]
```

Emits the five-part charge assembled from real state rather than recalled:

1. **Objective** — the mission's Objective section
2. **Definition of done** — the mission's checklist
3. **Constraints** — the mission's Constraints section
4. **Context it cannot discover** — the mission's Context section, plus the project
   dossier pointer, plus prior assignments on this mission and their verdicts
5. **Return format** — extracted from `agents/<name>.md`'s `## Return format` block
   (plugin root derived from `SCRIPT_DIR/../../..`; if the file is missing, the
   pack says so rather than emitting a charge with no return contract)

The contract already names point 4 as where delegation succeeds or fails. It is
also the point a model paraphrases from memory on the fourth delegation of a long
session. Generating it removes that failure mode.

**The pack is a draft, not a send.** Dave still reads it, adds what only he knows
from the conversation, and can edit freely. It is a floor on quality, not a
replacement for judgment.

### C.5 Dossier cache

```
dossier set <project> < cartographer-output.md
dossier get <project>       # content + staleness verdict
```

`dossier.md` is stamped with the git HEAD it was built at. `get` reports commits
since and calls it stale past `projects.dossier_stale_commits` (default 50).

The contract says Cartographer "runs once per unfamiliar repo, not per ticket" and
that its brief is "worth keeping in the mission" — with no store to keep it in.
This is the store, and it is per-project rather than per-mission, which is the
right grain for something that describes a repo.

### C.6 Delegation contract changes

Additions to `references/delegation-contract.md`:

- **Reuse before respawn.** A follow-up question goes back to the agent that
  already has the context (`SendMessage`) rather than cold-spawning a second one.
  A cold spawn re-derives everything the first one learned, and the contract's own
  argument for delegation — context economy — applies to the second call too.
- **Check the dossier before charging Cartographer.** A fresh dossier answers the
  charge for free.
- **Dave never calls the `Workflow` tool.** Workflows fan out many agents without
  user gates, and Dave's model is gated at every handoff by design. Writing this
  down stops a future contributor from adding it and quietly removing the gates.
- **Record every charge and every verdict** with `mission assign` / `mission record`.
  Replaces "record it in the Assignments table", which had no mechanism.
- Escalation and downgrade guidance stays exactly as written — it is good.

### C.7 Command changes

- New `/dave:mission` — open, status, close, and show what is outstanding.
- `/dave:delegate` gains: consult the dossier, use `mission pack` for the charge,
  and `mission record` the verdict before relaying. The five-part briefing prose
  stays; it is now backed by a command.

### Acceptance

- `mission assign` → `mission show` renders the row without anything editing the
  markdown by hand.
- `mission record` on an unknown id fails loudly rather than appending an orphan.
- `mission pack` for an agent whose definition has no `## Return format` block
  refuses to emit a charge and says why.
- `mission status` across three missions with eight assignments returns in one read.
- A truncated final line in `assignments.jsonl` does not break `mission show`.

---

## 8. Phase D — the sweep

**Goal:** move Dave from "session assistant" to "tracker". Orientation is daily and
already exists; the sweep is what catches a project going quiet, and it is the
piece that makes the project layer worth having.

### D.1 `dave.sh review [--days 7] [--json]`

Emits **facts it can compute**, clearly separated from **material the model must
judge**. That separation is the whole design — a sweep that asserts judgment from
thin data will be wrong confidently, which is the one thing this plugin's persona
is built to avoid.

**Computed:**

- Projects whose `cadence` is out of step with their real activity (`scan` last
  commit + `last_touched` + log mentions). `maintenance` and `dormant` projects
  going quiet are not findings.
- Projects with uncommitted work older than N days, or branches stale past 30 days.
- Open commitments due inside the horizon, and any past due.
- Time ledger for the window, by project and by ref, with the unverified split.
- Drift events for the window, grouped by kind and destination.
- Open missions with no assignment activity in N days.
- Parked items older than `parking.review_after_days` (default 14).
- `AD-` items whose first mention in `log/` is older than
  `review.adhoc_grace_days` (default 5) — the SKILL already says an `AD-` item
  surviving a few days is a smell, and first-log-mention dates it without needing
  per-item timestamps.

**Handed to the model to judge:**

- The **Blocked** section of `priorities.md` — which blockers have had no chase.
  These are prose and stay prose; the script surfaces them, the model reads them.
- What actually closed. **Without E's structured `done <ref>`, this is inferred
  from the log and the sweep must say so** rather than presenting it as a record.

### D.2 `/dave:review`

Weekly. Output shape, in this order — worst first, and short:

```
Since Monday: 3 projects touched, 11h20m recorded (1h05m unverified).

Slipping:
  webcrawler — cadence weekly, last commit 24 days ago, 3 uncommitted files
  Maya's SSO demo is due Friday and RM-4471 has 0m recorded this week

Rotting:
  4 parked items older than 14 days
  AD-cache-warmup first logged 11 days ago and still has no ticket

Quiet and fine:
  gnome-music (maintenance), dnd_5e_api (dormant)

Drift: 6 calls — 4 into webcrawler while RM-4471 was in Now.
```

The persona rules apply unchanged: no moralizing, no lecture, plain delivery of bad
news. **"Quiet and fine" is load-bearing** — a sweep that only ever lists problems
trains the user to stop reading it.

### D.3 Cadence and scheduling

**Be careful here.** The `schedule` skill creates *cloud* routines, and `~/.dave`
is local — a cloud agent has no access to it, so a scheduled cloud `/dave:review`
would produce a confident review of nothing. Do not recommend it.

Honest options, in order:

1. **A local scheduler** — a systemd user timer or cron entry running
   `claude -p "/dave:review"` in a registered project directory, Monday morning.
2. **`/loop`** for a session that is already open and should keep checking.
3. **Habit** — `/dave:review` on Monday. Costs nothing and works everywhere.

Ship (1) as a documented, opt-in snippet in the README. Do not install a timer as
part of setup; a productivity plugin that adds a system timer without being asked
is a plugin that gets uninstalled.

### D.4 Config additions

```json
"review": { "day": "monday", "adhoc_grace_days": 5, "promise_horizon_days": 3 },
"parking": { "review_after_days": 14 }
```

### Acceptance

- `review` on a fresh install with one project and no history produces a short,
  correct, non-alarming report and exits 0.
- A `maintenance` project with no commits in 60 days does not appear under
  "Slipping".
- `review --json` is consumable by the command without the model re-parsing prose.
- The "what closed" section states its own weakness when E has not landed.

---

## 9. Cross-cutting work

### Documentation

| File | Change |
|---|---|
| `skills/dave/SKILL.md` | Operating loop step 1 becomes project-first; new "Standing duty: the sweep"; state-layer section gains the new files |
| `references/delegation-contract.md` | C.6 — reuse before respawn, dossier check, no Workflow, record every charge |
| `references/priority-model.md` | Commitments are now recorded objects; drift events are recorded; `AD-` ageing is computed |
| `references/persona.md` | One addition: how the sweep sounds. Same rules, longer output, and "quiet and fine" is a legitimate finding |
| **new** `references/projects.md` | The project layer: registration, cadence, resolution, dossier, scan |
| `README.md` | Command table gains `/dave:project`, `/dave:mission`, `/dave:review`; the opt-in timer snippet |
| `USE_CASES.md` (both) | A multi-project worked example and a sweep example |
| `INSTALL-PI.md` | pi has no hooks — cwd resolution has to be manual there. State the gap plainly, as that file already does for other gaps |
| `templates/config-template.json` | `projects`, `review`, `parking`, `time` blocks with `_comment_*` keys |

### Testing

`dave.sh` has no tests today and is about to triple. Add `scripts/test/` with plain
shell tests (bats if available, a runner script if not), against a temp `DAVE_HOME`:

- init → migrate → idempotent re-migrate
- the focus/push/pop/clear matrix and the segments each produces
- open-segment capping
- jsonl fold with a truncated final line
- `project resolve` from a nested path, an unregistered path, and a non-repo
- `review` on an empty tree

CI is out of scope; a runnable `scripts/test/run.sh` is not.

### Migration and compatibility

- Every new file is created lazily. A v1 tree keeps working until `migrate` runs.
- `priorities.md`, `parking-lot.md`, `log/`, `intake/` and `missions/*.md` formats
  are **unchanged**. Nothing in A–D rewrites a file the user hand-edits.
- New commands degrade rather than fail: no projects registered → `resolve` is
  silent and `brief` looks exactly like it does today.

---

## 10. Sequencing and effort

| Phase | Depends on | Rough size | Ship value alone? |
|---|---|---|---|
| 0 — pre-flight, schema, libs | — | ~150 lines, 1 sitting | No, but 0.1 is a real bug hunt |
| A — project layer | 0 | ~250 lines + hook + 1 command | **Yes** — cwd resolution alone is worth it |
| B — instrumentation | 0, A (for `project` fields) | ~350 lines | **Yes** — next-action notes on their own |
| C — orchestration | 0.1 hard, A for dossier | ~300 lines + contract rewrite | **Yes** — the ledger alone fixes resumability |
| D — sweep | A, B, C | ~200 lines + 1 command | Needs A and B to have anything to say |

Each phase is independently shippable except D. If the appetite runs out, stopping
after B leaves a strictly better plugin than today, with no half-built machinery.

**Suggested order if all of it happens:** 0 → A → B → C → D, then revisit E, whose
`~/.dave`-as-a-git-repo item gets more valuable the more state these phases add.

---

## 11. Risks

1. **Command surface explosion.** `dave.sh` goes from 15 commands to roughly 40.
   Mitigation: Decision 1's lib split, grouped `help` output, and only three new
   slash commands rather than one per feature.
2. **The sweep becoming noise.** The single most likely failure. Mitigations are in
   the design: `cadence` per project, "quiet and fine" as a real section, worst-first
   ordering, and computed facts kept separate from judged ones.
3. **Time ledger dishonesty.** Covered by Decision 4, capping, and the unverified
   split — but it is worth re-reading Scribe's evidence rule after B lands and
   confirming nothing in the new data tempts it to estimate.
4. **Hook cost.** The session-start block is paid in every directory on every
   session. Keep it under 25 lines and cache the scan; if it ever needs a git walk
   at hook time, that is a design error.
5. **Two sources of truth for "what am I working on."** `priorities.md` (prose) and
   `projects/*/project.json` (structured) can disagree. Decision 2 keeps the
   mapping one-directional to limit this, and `project show` should surface a ref
   that no longer appears in `priorities.md` rather than hiding it.
6. **Scope creep into E.** D's "what closed" wants structured mutations. Resist
   inside these phases; note the weakness in the output instead.

---

## 12. Open questions for review

1. Decisions 1–4 in §2.
2. Does `project` need a **remote tracker** field now (the Redmine project id / the
   GitHub `owner/repo`), or does that wait for the tracker generalization work?
   Adding the field now is cheap; using it is not.
3. Should `focus` be **per-project** rather than global — one focused ref per
   project, and switching projects switches focus — or does one global focus stay
   the honest model of a person who can only do one thing at a time? I lean global,
   with the stack covering detours.
4. Is the weekly sweep the right period, or does a **fortnightly** one get read
   more carefully?
5. Should `next set` be **prompted automatically** when a session ends with a focus
   held, or does that cross the line into nagging?
