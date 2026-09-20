# D.A.V.E. sync review

Reviewed 2026-09-19 against the current working tree, including the six existing
modified files. Assessment only; implementation and user state were preserved.

## Model and scope

Each device appends structured mutations to its own journal. Syncthing transports
journals and shared documents; Bash/jq builds local views and Markdown. Guided
setup configures the transport; the CLI and dashboard expose status and conflict
resolution. The approved plan requires offline use on two devices and concurrent
sessions on each device. Review covered these paths, migration guidance, and
existing tests. No real Syncthing service, package installation, or device pairing
was performed.

## Findings

### 1. P1 — Offline updates can target the wrong promise or assignment

**Evidence:** `dave/skills/dave/scripts/lib/views.jq:75` renames a colliding
creation ID, but subsequent `promise.keep`, `promise.miss`, `promise.move`, and
`mission.grade` events retain their original IDs. Assignment readers join grades
by that ID (`scripts/lib/mission.sh:228`).

**Reproduced:** Device A created Ann's `c1`. Offline device B created Bob's `c1`
and marked it kept. After journal exchange, Ann was marked kept and Bob remained
open. Existing collision tests only check creation, not subsequent mutations.
Both devices converging on the same result does not establish correctness.

**Fix:** Mint immutable globally unique entity IDs at creation, with short CLI
aliases resolved to those IDs before writing events. Preserve reference identity
when replaying existing journals. Test offline create/update/exchange for both
promises and assignments, including multiple sessions on one device.
Effort: medium/high; address before extending the reducer.

### 2. P1 — Rebuild can certify stale views as fresh

**Evidence:** `scripts/lib/views.sh:70` reads the journal, publishes individual
view files, then fingerprints the current journals at line 88. There is no
rebuild lock or check that the input stayed unchanged.

**Reproduced:** A controlled fixture delivered another journal immediately after
the input stream was consumed. The resulting view omitted that event, but its
fingerprint matched the new journal set; `_views_ensure` did not repair it.
It remains stale until another journal change or an explicit rebuild. Concurrent
rebuilders can also publish different generations over one another.

**Fix:** Serialize local rebuilds; capture the input fingerprint before reading,
verify it before publication, and retry when inputs change. Record the fingerprint
of the input actually reduced, never a later state. Publish a coherent generation
of views and rendered output. A local lock alone cannot stop remote file arrivals.
Effort: medium.

### 3. P1 — Setup discards custom ignores and exposes migration archives to sync

**Evidence:** `scripts/lib/sync.sh:109` overwrites `.stignore` with five patterns.
It omits `.migrated-*/`. Migration only adds the archive exclusion if `.stignore`
already exists (`scripts/lib/migrate.sh`, archive step).

**Reproduced:** Starting with both `private/` and `.migrated-*/` exclusions, running
setup removed both. Thus both the normal migrate-then-setup sequence and rerunning
setup after migration leave archives eligible for transport. Archives can contain
the old Git repository and device-specific historical state.

**Fix:** Preserve user exclusions and maintain D.A.V.E.'s required patterns in an
idempotent managed block, accounting for first-match ordering. Include migration
archives in required exclusions regardless of command order. Test both migration
orders and repeated setup. Effort: small/medium.

### 4. P2 — CLI conflict resolution can delete files outside the vault

**Evidence:** `scripts/lib/sync.sh:520` checks a textual path prefix without
canonicalizing `..` or symlinked parent directories.

**Reproduced:** `sync conflicts resolve ../outside.sync-conflict-20260919-120000-ABC.md
keep-local` deleted a temporary file outside the fixture vault. The same check
can be bypassed to reach `.local`. This is a CLI containment defect, not a claimed
remote dashboard exploit: `dashboard/api.py:766` separately resolves paths and
checks their containment.

**Fix:** Resolve and validate both paths against the canonical vault and excluded
local directory before mutation; reject symlink escapes. Test traversal, symlink
parents, and `.local` aliases. Effort: small.

### 5. P2 — Dashboard misses remote journal changes with older mtimes

**Evidence:** `dashboard/server.py:116` watches only the maximum journal mtime.
Updating or adding another journal with an mtime below that maximum leaves the
watch signature unchanged. Failed refresh callbacks are also swallowed after the
signature has been advanced, preventing a retry without another change.

**Reproduced:** With one journal at mtime 2000000000, adding a peer journal at
1999999999 left `_scan_journal()` unchanged. Offline delivery and clock skew make
this relevant to sync. CLI reads still perform their own stronger freshness check.

**Fix:** Compare per-file signatures (name, size, nanosecond mtime), notify after
a successful refresh, and retry failed refreshes. Test older-file delivery,
replacement, deletion, and transient callback failure. Effort: small/medium.

### 6. P2 — Status cannot distinguish a working sync connection from setup alone

**Evidence, code trace:** `scripts/lib/sync.sh:479` only checks folder registration.
Configured-but-unreachable and never-configured daemons both become `not checked`.
It never checks peer connections, sharing, folder pause/error state, or transfer
completion. Setup sets `enabled=true` before proving a daemon exists (line 126).

**Impact:** An unshared or paused folder can show `enabled` and `folder registered`
while another device receives nothing. The plan promises visibility when the
daemon stops, but the current response collapses that into an ambiguous state.

**Fix:** Keep setup state separate from transport health. Report unconfigured,
unreachable/authentication failure, unshared, peer offline, syncing, caught up,
and folder error as available. Show pending work and last confirmed contact;
avoid promising delivery based on a successful local write. Effort: medium.

### 7. P2 — Existing folders produce pairing instructions with the wrong ID

**Evidence, code trace:** `scripts/lib/sync.sh:403` accepts an existing folder by
path regardless of ID, but line 427 always tells the user to share `dave-vault`.
A vault manually registered as `personal-dave` is accepted, then the user is told
to share an ID that does not identify that folder. A new second device is offered
the fixed ID instead.

**Fix:** Carry the actual registered folder ID into all instructions and status;
allow the receiving device to use that ID. Normalize equivalent folder paths
before matching. Test a pre-existing folder with a custom ID and trailing slash.
Effort: small/medium.

### 8. P2 — Upgrade guidance does not handle an existing second-device legacy tree

**Evidence, code trace:** `docs/dave-sync.md:194` says to deliver the migrated tree
to other devices and run setup without migrating them. `scripts/lib/common.sh:79`
rejects any tree retaining legacy root files with exit 4. Downloading a new journal
does not itself archive those pre-existing files. Local checkout paths/hooks also
need preservation on that device. Copying the entire vault, as the same paragraph
allows without exclusions, additionally copies `.local/device.json` and defeats
the one-writer-per-journal assumption.

**Fix:** Document a concrete receiving-device upgrade: back up and reconcile
unsynced legacy work, prepare a clean receiving tree, preserve that machine's
local configuration, and create a fresh device identity. Explicitly exclude
`.local` from manual copies. Provide a supported helper if this is a frequent
workflow. Effort: medium; coordinate with identity and ignore fixes.

## Functionality and UX improvements

- Rename conflict actions to **Keep original** and **Use conflict copy**, with a
  content preview and explicit deletion consequence. Syncthing chooses conflict
  copies by mtime/device ordering and synchronizes them; the copy is not reliably
  the remote edit. Current labels imply provenance they cannot establish.
  See [Syncthing conflict behavior](https://docs.syncthing.net/users/syncing.html).
- Correct `docs/dave-sync.md:30`: `.stignore` itself does **not** sync. Require local
  ignore preparation before accepting a folder; use a shared included rules file
  if shared rules are wanted. See [Syncthing ignore behavior](https://docs.syncthing.net/users/ignoring.html).
- Make credential recovery actionable. A saved but rotated key currently prevents
  rediscovery from XML, and an authentication failure gets a daemon-start offer.
  Respect `XDG_STATE_HOME` when finding newer Syncthing configurations; explain
  non-default GUI/TLS configuration failures rather than treating all as downtime.
- Surface malformed journal records and unexpected journal conflict copies.
  Silently skipping invalid JSON is useful for an interrupted tail, but users
  need a diagnostic when durable history is damaged. Never offer generic
  overwrite/delete resolution for a journal without checking event preservation.

## Verification and next steps

- Existing sync tests: **57 assertions passed** (mock transport and host helpers).
- Existing view tests: **20 assertions passed**.
- Five additional isolated repros confirmed findings 1–5; the rebuild repro
  deterministically injects an arrival at the vulnerable boundary rather than
  relying on scheduler timing. Reproduction harness: `/tmp/dave-sync-review-repro.py`
  in this review session; its temporary vaults are deleted automatically.
- Findings 6–8 are supported by code paths, not a live multi-device deployment.
- Dashboard HTTP regressions: **19 tests passed**. The initial sandboxed run
  could not create its loopback socket; rerunning with approved socket access
  passed. This was an environment restriction, not a feature failure.
- No real-device soak, browser interaction, installation, or service startup was
  tested. Repository-wide verification is unnecessary for this report-only change;
  catalog entries and bundles were not changed.

Prioritize entity identity, rebuild consistency, and ignore preservation. Then
repair conflict containment and dashboard refresh detection, followed by transport
health reporting and onboarding. Add regression coverage for each reproduced
failure; passing convergence tests alone do not establish semantic correctness.
