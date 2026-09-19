# D.A.V.E. state storage & sync refactor — plan

Status: approved 2026-09-19 (decisions below confirmed by Sawyer). Not started.
Branch: `feat/dave-journal-sync`. Existing approved plans govern scope; record
material deviations here.

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
- Automated Syncthing installation or configuration beyond printed guidance and
  optional REST-API verification.
