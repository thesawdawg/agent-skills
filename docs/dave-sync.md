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

## Syncthing setup

### 1. Install (native Linux or inside WSL2)

The vault lives in the Linux filesystem, so Syncthing runs on the Linux side —
on the Windows machine that means *inside* WSL2, not on Windows itself.

```bash
sudo apt install syncthing     # debian/ubuntu; newer builds: apt.syncthing.net
sudo dnf install syncthing     # fedora
sudo pacman -S syncthing       # arch

systemctl --user enable --now syncthing   # user service, no root needed
```

WSL2 without systemd: run `syncthing` under `nohup` or a supervisor — the GUI
lands on `http://127.0.0.1:8384` either way. (Windows-side Syncthing pointed at
`\\wsl$` also works, but is slower and not recommended.)

**Windows firewall:** Syncthing listens on TCP 22000 (sync) and 8384 (GUI).
WSL2's NAT normally hides these; if the devices can't see each other, allow
inbound 22000 for the WSL host or set up the Windows-side relay/discovery
rules Syncthing documents.

### 2. `dave.sh sync setup` (guided)

Run it once per device — it is part of first-run setup and safe to re-run. It
always does the vault-side prep, then walks the Syncthing side as far as it
can:

1. Writes `.stignore` (`.local/`, `.obsidian/workspace*`, `*.tmp`, `*.swp`,
   `.DS_Store`), ensures `device.json` and `.obsidian/app.json`, and flips
   `.sync.enabled` in `.local/config.json`.
2. Checks `syncthing` is on PATH (override the binary name with
   `SYNCTHING_BIN`). When it isn't, it names the one install command for the
   detected package manager (apt, dnf, pacman, zypper) and — on a terminal —
   offers to run it. Off a terminal it prints the command and the
   user-service line and stops; nothing non-interactive installs packages.
3. Finds the API key: `SYNCTHING_API_KEY` / `.local/config.json` first, then
   scrapes `<apikey>` and the GUI address from Syncthing's own `config.xml`
   (`$SYNCTHING_CONFIG`, then `$XDG_CONFIG_HOME/syncthing`,
   `~/.config/syncthing`, `~/.local/state/syncthing`). When the daemon has
   never run on the host — no `config.xml` — or has a config but isn't
   answering, setup offers to start it first: the systemd user unit where
   one exists, a detached `syncthing` process where it doesn't (WSL without
   systemd), then waits for the GUI to open before continuing.
4. Asks the daemon for its device id and whether a folder already covers the
   vault.
5. **Registers `~/.dave` for you** — folder id `dave-vault` (a fixed id, so the
   "same Folder ID on both devices" rule is automatic), filesystem watching
   for instant propagation, staggered versioning. On a terminal it asks first;
   `dave.sh sync setup --auto` skips the prompt for scripted runs — but
   `--auto` only covers this prompt; it never installs or starts anything.
   If the folder exists but lacks versioning it offers to patch that too.
6. Saves the discovered key/url to `.local/config.json` (device-local, never
   synced) so `sync status` can report daemon health afterwards.
7. Prints this device's Syncthing id and the pairing steps below.

Every step degrades to printed instructions — nothing in the guided path is
required for sync to work; it only saves you a trip to the GUI (and, on a
terminal, a trip to the package manager and `systemctl`).

### 3. Pairing the devices (once)

Syncthing pairing is mutual — each device must know the other:

1. Run `dave.sh sync setup` on the second device; it prints that device's id.
2. In either GUI (`http://127.0.0.1:8384`), add the other device's id under
   **Add Remote Device** — or just accept the introduction prompt Syncthing
   pops up when an unknown device connects.
3. Share folder `dave-vault` with the new peer (Edit Folder → Sharing) and
   accept the share prompt on the other side. The identical folder id is what
   makes the two folders one folder.

`dave.sh sync status` shows `syncthing: folder registered` plus this device's
Syncthing id once setup has run — the id is the value the peer needs.

### 4. Manual GUI route (fallback)

If the guided path can't reach the daemon (no `config.xml`, non-standard
home, remote Syncthing), do it by hand at `http://127.0.0.1:8384`:

- **Add Folder** — path `~/.dave`, Folder ID `dave-vault` (any id works, but
  it must be *identical on every device* — Syncthing suggests a random one,
  override it).
- Enable **Staggered File Versioning** — conflict copies are rare (journals
  never collide), but versioning is what makes a bad merge of `priorities.md`
  recoverable.
- Share it with the other device; accept it there with the same Folder ID.
- Optionally export `SYNCTHING_API_KEY` (GUI → Actions → Settings → API Key)
  or set `.sync.syncthing_api_key` / `.sync.syncthing_url` in
  `.local/config.json` so `sync status` reports reachability instead of
  "not checked". Sync works without them.

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

Structured state rarely conflicts: each device only appends to *its own*
journal file, so in normal operation Syncthing never has two writers on one
file. It is not impossible — a cloned device identity, a restored backup, or a
tree copied by hand can put two writers behind the same journal name. Prose
conflicts more readily: two devices editing `priorities.md` offline produce a
`priorities.sync-conflict-<date>-<device>.md` copy next to the original.

```bash
dave.sh sync conflicts                              # list copies and what they shadow
dave.sh sync conflicts preview <file>               # read-only: the diff and the consequence
dave.sh sync conflicts resolve <file> keep-original      # drop the copy
dave.sh sync conflicts resolve <file> use-conflict-copy  # copy replaces the original
```

`keep-local` and `keep-remote` remain accepted as aliases for the two canonical
actions. Both destructive actions copy the bytes they discard into
`.local/conflict-recovery/` first, so a wrong choice is recoverable. Pass
`--expect <sha256>` (and `--expect-original <sha256>`) from `preview --json` to
refuse the action if either file changed since you looked at it; the dashboard
always does this.

Resolution only ever touches regular files inside the vault and outside
`.local`, the `.migrated-*` archives, and `journal/`. Symlinked operands are
refused rather than followed, and the `.sync-conflict-` suffix is parsed in the
filename alone, so a directory carrying that infix is never rewritten. These
checks bound what a resolution can name; they are not a guarantee against
another process changing the files between the check and the action.

There is no automatic merge: with no common ancestor there is nothing safe to
diff3 against, so `merge` shows a `diff -u` of the two versions and leaves both
files alone.

### Journal conflicts

A `*.sync-conflict-*` copy of a journal is *not* resolved by keeping one side —
the discarded file can hold durable events that exist nowhere else. Those copies
are excluded from ordinary replay and recovered on their own path:

```bash
dave.sh sync journal-conflicts <file>                  # preview: unique vs duplicate events
dave.sh sync journal-conflicts <file> --apply <sha256> # import the unique events
```

Recovery is preservation-first: the source copy is backed up under
`.local/recovery/`, events are imported under their original identities, and
replay deduplicates by identity, so repeating an import cannot duplicate
history. If the two files disagree about the *contents* of the same event
identity, recovery refuses and keeps both files for manual reconciliation.

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
