# D.A.V.E. state sync (Syncthing)

D.A.V.E. keeps its state in `~/.dave` (`$DAVE_HOME`). Since schema 3 that tree
is a Syncthing folder shaped like an Obsidian vault: every structured write is
an append to a per-device journal, Syncthing carries the files between devices,
and each device derives its own views locally. `dave.sh` is the only writer;
Syncthing only moves bytes. There is no git remote anywhere in the pipeline.

## Vault layout

```
~/.dave/
├── journal/
│   ├── <device>.jsonl          # this device's append-only event log
│   └── <other-device>.jsonl    # peers' journals, delivered by Syncthing
├── .local/                     # device-local; ignored by Syncthing (.stignore)
│   ├── device.json             # this device's id, created once
│   ├── config.json             # device-local overrides (hooks, sync, paths)
│   ├── views/                  # derived state — rebuilt from journals
│   └── render/                 # generated markdown (log/, parking-lot.md)
├── config.json                 # shared config (user, roster, review, projects)
├── priorities.md               # hand-editable; the ranked list
├── missions/                   # mission briefs, hand-editable markdown
├── intake/                     # archived intake boards
├── projects/<slug>/project.json  # shared project identity (no path — paths
│                               #   live in .local/config.json projects.paths)
└── .stignore                   # written by `dave.sh sync setup`
```

**What syncs:** `journal/`, `config.json`, `priorities.md`, `missions/`,
`intake/`, `projects/`, `.stignore`, `.obsidian/` (minus workspace files).

**What stays on the device:** everything under `.local/` — the device identity,
device-specific config, the derived views, and the rendered markdown. Views are
recomputed from the journals on every `dave.sh` invocation (fingerprint
checked, so a no-op costs one `stat` pass), so syncing them would only create
conflict opportunities for zero gain.

**The generated-file rule:** anything under `.local/render/` is *output*, not
source. Do not hand-edit `.local/render/log/*.md` or
`.local/render/parking-lot.md` — they are regenerated from the journal on the
next write and your edit will silently vanish. Add entries with
`dave.sh log "…"` and `dave.sh park "…"`; retire with `dave.sh parked done <n>`.

## Syncthing setup (Linux + WSL2)

1. **Install & enable** Syncthing inside WSL2 (not on the Windows side — the
   vault lives in the Linux filesystem):
   ```bash
   systemctl --user enable --now syncthing
   # or a systemd --user unit if your distro doesn't package one
   ```
   WSL2 has no systemd on some distros — then run `syncthing` under a
   supervisor or `nohup`, or enable Windows-side Syncthing pointing at the
   `\\wsl$` path (slower, but works).

2. **Windows firewall:** Syncthing listens on TCP 22000 (sync) and 8384 (GUI).
   WSL2's NAT normally hides these; if the devices can't see each other, allow
   inbound 22000 for the WSL host or set up the Windows-side relay/discovery
   rules Syncthing documents.

3. **Prepare the vault:** `dave.sh sync setup` writes `.stignore`
   (`.local/`, `.obsidian/workspace*`, `*.tmp`, `*.swp`, `.DS_Store`), ensures
   `device.json`, and flips `.sync.enabled` in `.local/config.json`.

4. **Add the folder** in the Syncthing GUI (`http://127.0.0.1:8384`):
   - Path: `~/.dave` — **use the same Folder ID on every device.** Syncthing
     suggests a random one per device; override it so the folders match.
   - Enable **Staggered File Versioning** — Syncthing's conflict copies are
     rare (journals never collide), but versioning is what makes a bad merge
     of `priorities.md` recoverable.
   - Share it with the other device; accept it there with the same Folder ID.

5. If `SYNCTHING_API_KEY` and `.sync.syncthing_url` are set in
   `.local/config.json`, `dave.sh sync status` also reports whether Syncthing
   itself is reachable and whether the folder is registered. Without them it
   says "not checked" — that is fine; sync still works.

## Obsidian

Point Obsidian at the vault over the WSL share:

```
\\wsl$\<distro>\home\<user>\.dave
```

(`<distro>` e.g. `Ubuntu`, `<user>` your Linux username.) `dave.sh sync setup`
writes an empty `.obsidian/app.json` when `.obsidian/` doesn't exist so
Obsidian recognises the folder as a vault. `priorities.md`, mission briefs and
the rendered logs all read as ordinary notes. Remember the generated-file rule
before editing anything under `.local/render/`.

## Day to day

`dave.sh sync status` shows one line per journal (device id, event count, last
event timestamp), whether the derived views are fresh, how many
`*.sync-conflict-*` files are sitting in the vault, and Syncthing reachability
when the API is configured. `--json` gives the same thing for the dashboard.

## Conflicts

Structured state cannot conflict: each device only appends to *its own*
journal file, so Syncthing never has two writers on one file. Prose can —
two devices editing `priorities.md` offline produce a
`priorities.sync-conflict-<date>-<device>.md` copy next to the original.

```bash
dave.sh sync conflicts                 # list copies and what they shadow
dave.sh sync conflicts resolve <file> keep-local    # drop the copy
dave.sh sync conflicts resolve <file> keep-remote   # copy replaces the original
```

There is no automatic merge: with no common ancestor there is nothing safe to
diff3 against, so `resolve` shows a `diff -u` of the two versions and only the
`keep-*` actions touch files.

## Migrating from the git-based sync

Run once, on one device (the tree is schema 3 afterwards):

```bash
dave.sh migrate
```

`migrate` folds the old root files (`state.json`, `notes.json`,
`commitments.json`, `missions.json`, `sessions.jsonl`, `assignments.jsonl`)
into a separate `journal/<device>-import.jsonl` snapshot, parses `log/*.md`
and `parking-lot.md` into events, moves `projects.root` / `projects.paths` /
`hooks` / `sync` from `config.json` into `.local/config.json`, and parks all
the originals — including `.git/` and `.gitignore` — under
`.migrated-<YYYY-MM-DD>/`. Nothing is deleted; the old git remote can be
removed by hand afterwards (it is no longer read).

On the other devices: let Syncthing deliver the migrated tree (or copy it),
then run `dave.sh sync setup`. Do **not** run `migrate` a second time — it
prints `already migrated` and exits, but the pre-check is only reliable once
the first migrated tree exists.

## The `~<dev>` id rule

Promise and assignment ids are minted per device from the local view
(`c1`, `mission#2`). Two devices that mint offline can produce the same id;
the view reducer detects the collision and suffixes the *later* event's id
with `~<device-id>` — so `c5` and `c5~laptop-3fa2c1` are two different
promises. The suffix is part of the id everywhere afterwards (`promise keep
c5~laptop-3fa2c1`). Single-device ids never grow a suffix.
