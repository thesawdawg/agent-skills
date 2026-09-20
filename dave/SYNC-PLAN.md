# D.A.V.E. state storage & sync refactor — plan

Status: implemented on feat/dave-journal-sync (M1–M6, 2026-09-19).
Branch: `feat/dave-journal-sync`. Existing approved plans govern scope; record
material deviations here.

Follow-up: [sync remediation plan](SYNC-REMEDIATION-PLAN.md) tracks the
2026-09-19 review findings and UX improvements. It is planned work, not a claim
that those fixes are implemented; M1–M6 below retain their original history.

## Deviations (as built vs. as planned)

- **Collision suffixing on ids** (`~<dev>`): the plan left promise/assignment
  ids to sort themselves out; two offline devices can mint the same `c<N>` /
  `mission#<n>`. The reducer rewrites the later event's id to `<id>~<dev>` on
  collision, so single-device ids stay clean.
- **Legacy `.path` fallback**: `_project_path`/`_projects_all` still read a
  `path` field from `project.json` when the local `projects.paths` map lacks
  the slug, so pre-migration trees keep working. `migrate` strips the field.
- **`_local_keys` in the dashboard config API**: planned as a marker of which
  merged keys came from `.local/config.json`; implemented as a top-level
  `"_local_keys": [...]` response field (not written to any file).
- **ChangeWatcher → `_views_ensure`**: the dashboard now calls `dave.sh state`
  when `journal/*.jsonl` mtimes move, so a Syncthing-delivered remote journal
  refreshes views without waiting for a local write — the plan assumed a
  local command would always trigger the rebuild.
- **Journal fingerprint uses `stat %y` (nanoseconds)**, not `%Y` — same-second,
  same-size journal edits were invisible at 1s granularity.
- **`import.snapshot` lives in `journal/<device>-import.jsonl`**, a separate
  file from the device's live journal (the plan implied the synthesis but not
  the filename); its envelope `ts` is the legacy `state.json.created`.
- **Migration archive**: `.migrated-<date>/` also collects `.git/`,
  `.gitignore`, `scan-cache.json` (moved to `.local/` instead when absent
  there — it's derived but expensive) and stray `*.jsonl.bak-*` files.
- **`_config_merged` memoization**: per-process cache keyed on both config
  files' stat fingerprints, invalidated by `json_edit` — added at review as a
  perf fix; `config_get`/`config_bool`/`cmd_config`/`cmd_brief` call it in the
  current shell because command substitution would drop the cache.
- **Orphaned `park.done` ids are ignored** in the reducer (a `park.done` whose
  id matches nothing is dropped rather than erroring — old trees can carry
  them).
- **Guided `sync setup`** (user request, post-implementation): setup now finds
  the local Syncthing daemon, scrapes its api key from `config.xml`, and
  registers the vault as folder `dave-vault` over the REST API — prompted on a
  tty, `--auto` for scripted runs — then persists the credentials to
  `.local/config.json`. `sync status` additionally reports the
  daemon's device id for pairing.
- **First-run install/start walkthrough** (user request, post-implementation):
  the "automated installation is out of scope" line softened — `sync setup`
  is now part of SKILL.md's first-run flow and walks the host side: it names
  the install command for the detected package manager (apt/dnf/pacman/
  zypper) and offers to run it, and when the daemon has never run or isn't
  answering it offers to start it (systemd user unit, else a detached
  process) with bounded waits for `config.xml` and the API. All
  host-changing steps still require a confirmed tty; `--auto` covers only the
  folder-registration prompt. Device pairing remains manual.

## Goal

Replace the git-remote sync (sequential, one-writer contract in `lib/sync.sh`)
with a **Syncthing-moved, Obsidian-vault-shaped `DAVE_HOME`** where two devices
with several sessions each can write concurrently, every write syncs
immediately, and conflicts are impossible by construction for structured state
and detected/repairable for prose.

## Requirements (from interview)

- Two devices: Linux + Windows/WSL2. Multiple D.A.V.E. sessions may be open on
  each device at once.
- Sync must happen automatically after every write; no user-run push step.
- Sync engine: Syncthing. The vault should be openable in Obsidian as an
  optional viewer/editor; Obsidian is **not** the transport.
- Frequent Markdown appends (log lines, parked items) become events and the
  Markdown is rendered from them. `priorities.md`, mission briefs and intake
  archives stay hand-editable documents.
- Git sync is dropped entirely; no legacy mode and no export command.
- History: the event journal is the history for structured state; Syncthing
  file versioning covers prose. No git layer.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Transport | Syncthing; Obsidian is an optional viewer | Headless sync, free, `.stignore` for device-local files |
| Structured state | Per-device append-only event journals; everything else is a derived view | Each device writes only its own journal file, so cross-device write conflicts cannot occur |
| Log / parking lot | Events; Markdown **rendered per device** into a non-synced path | Rendered files never sync, so no conflict copies of generated content |
| Hand-edited prose | `priorities.md`, `missions/*.md`, `intake/*` stay documents; last-writer-wins plus conflict detection and a merge helper | Rarely edited, human-owned, pleasant in Obsidian |
| History | Journal is the history; enable Syncthing "staggered" file versioning on the folder for prose. No git. | Zero extra daemons |
| Reducer language | bash + jq | Keeps the state layer's zero-Python contract; the dashboard keeps reading the same view files |
| WSL | Run Syncthing **inside WSL2** so `DAVE_HOME` is on ext4; Obsidian on Windows opens the vault via `\\wsl$\...` | `/mnt/c` (9p) breaks `flock`, mtime granularity and `chmod 600` |
| Git sync | Removed, including `sync setup/pull/push` and the `brief` pre-pull | Confirmed by user |

## Target layout

```
~/.dave/                          # the vault; the Syncthing folder
  .stignore                       # .local/  .obsidian/workspace*
  .obsidian/                      # optional; only app.json/appearance synced
  config.json                     # SHARED config: user, personality, roster, models, review, parking
  journal/
    <device-id>.jsonl             # this device's events (the only file here this device writes)
    <other-device>.jsonl          # read-only from this device's point of view
  priorities.md                   # document, hand-editable
  missions/<slug>.md              # briefs, hand-editable
  intake/<date>-<name>.md         # archives
  projects/<slug>/project.json    # shared identity: slug, name, goal, status, cadence, refs (NO path)
  .local/                         # NOT synced (.stignore)
    device.json                   # {id, hostname, created}
    config.json                   # device overrides: projects.root, project paths {slug: path}, hooks
    views/                        # derived: state.json missions.json notes.json commitments.json
                                  #          sessions.jsonl assignments.jsonl + .fingerprint
    render/log/YYYY-MM-DD.md      # generated from events
    render/parking-lot.md         # generated from events
    scan-cache.json
```

The `$STATE`, `$NOTES`, `$COMMITMENTS`, `$SESSIONS`, `$ASSIGNMENTS`,
`$MISSIONS_JSON`, `$SCAN_CACHE`, `$LOGDIR` and `$PARKING` variables in
`lib/common.sh` are repointed to `.local/…`, so readers change almost nothing.

## Event model

One line per mutation:

```json
{"ts":"<iso-utc>","seq":N,"dev":"<device-id>","sid":"<session-id>","type":"focus.set","data":{...}}
```

- Total order is `(ts, dev, seq)`. `seq` is a per-device monotonic counter so
  same-second events order correctly; clock skew between devices only affects
  genuinely concurrent edits to the same entity, and the deterministic
  tie-break makes both devices converge on the same result.
- Same-device sessions are serialised by the existing `flock` in
  `jsonl_append` (`lib/common.sh`).
- Event types map 1:1 to today's writers:
  `focus.set|push|pop|clear`, `session.close`, `next.set|clear`, `log.add`,
  `park.add|done`, `promise.add|keep|miss|move`, `drift.record`,
  `mission.create|open|close|assign|grade`,
  `project.add|status|link|unlink|touch|scan`, `intake.archive`, `brief.seen`,
  `priorities.set` (records the fact plus a content hash; the content is the
  document).
- Items referenced by position today (`parked done <n>`) get stable ids
  (`<ts>-<dev>-<seq>`); the CLI still accepts `<n>` and resolves it against the
  current view.
- Reducer: one jq program folding the sorted union of `journal/*.jsonl` into
  each view. `_views_ensure` compares a fingerprint (size + mtime of every
  journal file) to `views/.fingerprint` and rebuilds only when stale; cheap
  enough to run at the top of every read command. Truncated tail lines are
  skipped (existing `jsonl_stream` behaviour).

## Milestones

### M1 — Journal core (`lib/journal-core.sh`, `lib/views.sh`)

- `device_id` (creates `.local/device.json` on first use), `event_append`,
  `_views_ensure`, `dave.sh rebuild`, `.local/` bootstrap in `init`.
- No writers converted yet. Views rebuilt from an empty journal must equal
  today's fresh `init` output byte-for-byte.
- Tests (`run.sh journal|views`): ordering, `seq` ties, truncated tail,
  two-journal union, fingerprint staleness.

### M2 — Convert writers

- Module by module: `focus.sh` → `track.sh` → `journal.sh` → `mission.sh` →
  `project.sh`. Every `json_edit "$STATE" …` becomes `event_append` + view
  refresh.
- Command output and exit codes unchanged, so the existing test suite is the
  regression harness.
- Add per-module "two devices, interleaved events, identical views on both"
  tests using two `DAVE_HOME`s that share `journal/` by copy.

### M3 — Rendered Markdown + local/shared split

- `log.add` / `park.add|done` render `.local/render/log/YYYY-MM-DD.md` and
  `.local/render/parking-lot.md` with a header line:
  `<!-- generated by dave.sh; edit with dave.sh log / park -->`.
- `config.json` split: shared in the vault, device overrides in
  `.local/config.json`; `config_get` reads local-over-shared.
- `projects/<slug>/project.json` drops `path`; per-device paths live in
  `.local/config.json` under `projects.paths` keyed by slug. `_project_resolve`
  and `scan` use the local map.

### M4 — Sync commands (`lib/sync.sh` rewrite)

- `sync setup [--vault PATH]`: writes `.stignore`, `device.json`, optional
  `.obsidian/` skeleton; prints the Syncthing folder-add checklist, and if a
  Syncthing REST API key is available on localhost, verifies the folder is
  shared.
- `sync status`: event count and last event per device, view freshness,
  `*.sync-conflict-*` count, Syncthing reachability.
- `sync conflicts [--resolve <file> keep-local|keep-remote|merge]`: lists
  conflict copies for prose; `merge` uses `diff3` when available, otherwise
  prints both paths for the user.
- Remove `sync pull/push`, the `brief` pre-pull and all git handling.
- Dashboard (`dave/skills/dave/dashboard/`): Pull/Push controls become
  Status / Conflicts / Rebuild; `ChangeWatcher` watches `journal/` and prose.
  Sync API routes and `tests/test_dashboard.py` updated to match.

### M5 — Migration (`SCHEMA_VERSION=3`)

- `dave.sh migrate` synthesises `journal/<device>-import.jsonl` from existing
  `state.json`, `notes.json`, `commitments.json`, `missions.json`,
  `sessions.jsonl`, `assignments.jsonl`, `log/*.md`, `parking-lot.md`
  (line-format parsers already exist in `review.sh` and dashboard
  `readers.py`; port to jq/awk).
- Moves originals to `.migrated-<date>/`, splits config, writes `.local/`.
- Idempotent; refuses to run twice on the same tree. Missions registered in
  `missions.json` without a brief (e.g. `hybrid-stage-4`) are reported as
  warnings, not failures.
- Migration is one-way; backups are the safety net.

### M6 — Docs & WSL guidance

- Update `dave/README.md`, `dave/skills/dave/SKILL.md`, `dave/commands/*.md`,
  dashboard help text, root `README.md` catalog entry if the description changes.
- New `docs/dave-sync.md`: Syncthing inside WSL2 (systemd, autostart), folder
  versioning settings, pointing Obsidian at `\\wsl$\<distro>\home\<user>\.dave`,
  the "generated file" rule, conflict resolution walkthrough.

## Risks / trade-offs

- **Clock skew**: two edits to the same entity within the skew window may not
  resolve to the wall-clock-later one, but both devices converge on the same
  answer. Acceptable for one human on two machines.
- **Hand-editing a rendered log** in Obsidian is lost on the next render. The
  header warns; `priorities.md` and briefs remain the hand-edit surfaces.
- **Rebuild cost** grows with journal length; at tens of events per day jq folds
  thousands of events well under a second. Add yearly journal rotation
  (`<dev>-YYYY.jsonl`) only if it becomes measurable.
- **Syncthing not running** on a device degrades to local-only state; `sync
  status` and the dashboard surface it. No data is lost; it catches up later.

## Verification

- `bash scripts/verify.sh` at every milestone.
- New `run.sh` groups: `journal`, `views`, `sync`, `migrate`.
- `tests/test_dashboard.py` extended for the new sync API shape.
- Manual two-tree soak: two `DAVE_HOME`s, a script that copies `journal/`
  between them after each command, assert identical views on both sides.

## Out of scope

- Git-based sync of any kind, including a one-shot export.
- Running `DAVE_HOME` on the Windows filesystem (`/mnt/c`).
- Automated Syncthing installation or device pairing (printed guidance only).
  Folder *registration* moved in scope post-implementation: guided `sync
  setup` performs it over the REST API on confirmation.
