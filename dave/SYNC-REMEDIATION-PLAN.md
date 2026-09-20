# D.A.V.E. sync remediation plan

Created: 2026-09-19.
Status: in progress; staged implementation with smaller-model agents and primary-agent review.
Scope: all eight findings and four additional recommendations from the
[sync review](../app-design-output/recommendations.md).
Parent: [original sync implementation plan](SYNC-PLAN.md).

This file tracks follow-up work. The original plan remains the record of M1–M6
and its implemented deviations. Creating this plan does not mark any fix complete
or authorize changes to installed personal skills or live device configuration.

## Outcomes and constraints

- Offline mutations retain the identity of the entity the user selected.
- A view marked fresh represents the journals actually reduced, and consumers
  read a consistent generation of structured state and generated Markdown.
- Setup preserves user exclusions and protects local state before sharing starts.
- Conflict actions operate only on eligible vault files and describe their actual
  effect; journal recovery cannot silently discard durable events.
- Status distinguishes local setup, transport health, peer delivery, view
  freshness, and journal integrity.
- Both new devices and existing legacy devices have a safe, documented setup path.

Keep Bash/jq for the state layer, Python for the existing dashboard, Syncthing for
transport, Linux/WSL2 ext4 storage, and manual device pairing. No new runtime
dependency is planned. Check required locking/path utilities in preflight rather
than silently weakening guarantees when they are absent. Keep package installation
and service-start confirmation behavior; `--auto` must not acquire new authority.
Tests use disposable homes and mocks or loopback servers. Never push Git changes
or install/update the user's personal skills as a side effect.

## Coverage and tracking

Unchecked work is pending. Mark tasks complete only with linked implementation
and test evidence. Use the execution log below for blockers and material deviations.
Effort estimates are relative complexity, not calendar commitments.

| Work item | Review coverage | Priority | Depends on | Effort | Status |
|---|---|---|---|---|---|
| M0 Regression fixtures | Reproduced findings 1–5; gaps 6–8 | Foundation | — | Small | In progress |
| M1 Preserve exclusions | Finding 3; `.stignore` documentation | P1 | M0 | Small/medium | In progress |
| M2 Safe conflicts | Finding 4; action labels and previews | P2 | M0 | Medium | Complete |
| M3 Stable entity identity | Finding 1 | P1 | M0 | Large | In progress |
| M4 Consistent views | Finding 2 | P1 | M0 | Medium/large | In progress |
| M5 Journal integrity | Corrupt records and journal conflicts | Reliability | M2, M3, M4 | Medium | In progress |
| M6 Dashboard refresh | Finding 5 | P2 | M4, M5 | Medium | Pending |
| M7 Setup and health | Findings 6–7; credential recovery | P2 | M1, M6 | Medium/large | Pending |
| M8 Device upgrade | Finding 8; local ignores and copies | P2 | M1, M3, M5, M7 | Medium | Pending |
| M9 Integration and docs | Entire review | Release gate | M1–M8 | Medium | Pending |

Recommended execution order: M0, M1, M3, M4, M2, M5, M6, M7, M8, M9.
M1 is the first vertical slice: run setup through the existing CLI in a disposable
home with custom exclusions and migration archives, then prove both protection and
idempotence through the guided registration mock. It needs no live daemon.

## Ownership and files

Paths below are relative to `dave/skills/dave/` unless otherwise stated.
Keep bundle-required helpers and references inside this bundle.

```text
scripts/
  dave.sh                     command dispatch and help
  lib/
    common.sh                 local paths, utility checks, reader setup
    journal-core.sh           event/entity identity and append discipline
    views.sh, views.jq        snapshot acquisition, replay, publication
    render.sh                 render against a staged generation
    track.sh, mission.sh      resolve aliases before writing mutations
    sync.sh                   ignores, setup, health, safe conflict actions
    migrate.sh                shared-history import and local upgrade handling
  test/
    run.sh                    focused regression groups
    fixtures/                 new fixtures only where reused/needed
dashboard/
  readers.py                  pin one generation per logical read
  server.py                   change detection, retry, refresh notification
  dave_cli.py, api.py         status and conflict contracts
  static/app.js              health presentation, preview, action labels
```

Repository-level owners: `tests/test_dashboard.py` for dashboard integration;
`docs/dave-sync.md` for operator guidance; `dave/README.md`, bundle `SKILL.md`, and
relevant `dave/commands/` entries for user-facing command changes. Update root
README only if catalog descriptions change. Record implemented design deviations
in `dave/SYNC-PLAN.md` without rewriting its history.

## M0 — Preserve failures as reproducible tests

- [ ] Recreate the five review repros inside the owned test suite; do not rely on
  `/tmp/dave-sync-review-repro.py` surviving this session.
- [ ] Give two-device fixtures deterministic device identities and timestamps;
  assert entity meaning as well as equality of final views.
- [ ] Add a deterministic synchronization barrier for arrivals during rebuild and
  overlapping local writers. Avoid timing-only sleeps as the race proof.
- [ ] Add transport fixtures for custom folder IDs, unavailable/auth-failed APIs,
  paused/unshared folders, and an old second-device state tree.
- [ ] Keep fixtures isolated from real HOME/config discovery, package managers,
  Syncthing, and personal credentials. Preserve the existing test isolation.

Acceptance: each relevant regression fails against the reviewed behavior for the
expected reason. Existing baseline remains documented: 57 sync assertions,
20 view assertions, and 19 dashboard tests passed during review. Add tests with
their fixes or explicitly track expected failures; do not weaken assertions to
obtain a passing baseline.

## M1 — Preserve ignore rules across setup and migration

- [ ] Factor one ignore-preparation helper used by setup and migration. Also use
  it when initializing a receiving vault before any folder registration.
- [ ] Maintain a clearly delimited required block for `/.local`, migration
  archives, and the existing editor-noise exclusions. Root-anchor owned paths.
- [ ] Preserve user patterns/comments outside that block. Place mandatory local
  exclusions before user negations because matching order matters; explain this
  ownership in docs. Refuse malformed managed markers without truncating the file.
- [ ] Write updates atomically. Handle absent files and repeated calls without
  duplication. Preserve user file permissions.
- [ ] Ensure migration archive protection exists even when migration precedes
  setup; do not register/share if required ignore preparation fails.
- [ ] Correct the claim that `.stignore` syncs. Prepare it separately on every
  device. A shared include file is unnecessary for the initial fix.

Tests: custom comments/patterns survive, earlier negations cannot expose `.local`,
setup twice is stable, migrate→setup and setup→migrate→setup retain exclusions,
failure leaves the original file intact, registration sees prepared rules.

Acceptance: neither device-local data nor migration archives become newly eligible
for sync due to a D.A.V.E. setup rerun. Existing user rules are preserved.

## M2 — Contain conflict actions and make their effect clear

- [x] Canonicalize vault, conflict path, original path, and parent paths. Validate
  both operands are inside the vault and outside `.local` and migration archives.
  Reject symlink escapes; choose a conservative rejection of symlink operands.
- [x] Parse the conflict suffix in the basename only, using the supported name
  format. Never strip a matching segment from a parent directory.
- [x] Check eligible file type and original/copy existence for each action.
  Keep the dashboard containment check as defense in depth.
- [x] Block generic destructive resolution for `journal/` immediately; M5 defines
  its recovery path. Do not treat deleting a journal copy like deleting prose.
- [x] Add canonical actions `keep-original` and `use-conflict-copy`; retain
  `keep-local`/`keep-remote` as documented compatibility aliases. Update help,
  returned messages, dashboard controls, API validation, and examples together.
- [x] Provide a read-only diff preview with both filenames and explicit deletion
  or replacement consequences. Bound large/binary previews and escape content.
- [x] Protect against a stale preview: record content hashes and recheck before
  applying a dashboard decision. If either file changed, require a refreshed
  preview. Preserve a local recovery copy before destructive replacement/removal.

Tests: `..`, absolute outsiders, symlink parents/operands, `.local` aliases,
archive paths, missing originals, valid filenames with spaces, journal copies,
legacy action aliases, changed-after-preview content, and preview escaping.

Acceptance: CLI and dashboard cannot mutate outside the allowed document area;
the user sees which bytes will be kept and can recover an accidental choice.
Path validation is not a promise of immunity to an adversarial process racing
filesystem operations; do not claim stronger guarantees than the implementation.

## M3 — Give entities immutable identity

- [ ] Add an opaque immutable `entity_id` to newly created promises and mission
  assignments. Generate it from collision-resistant randomness before append,
  independent of view-derived counters. Validate uniqueness during replay.
- [ ] Store the selected `entity_id` in keep/miss/move/grade events. Resolve CLI
  aliases against a current view before append; never retarget a stored event
  because another journal changes an alias.
- [ ] Keep familiar short IDs as display aliases where unambiguous. Permit an
  explicit stable identifier for ambiguous cases; return the effective alias and
  identity after creation so concurrent sessions do not report misleading IDs.
- [ ] Update reducer joins, mission ledger folding, dashboard selectors, and JSON
  consumers to use immutable identity. Preserve compatible presentation fields.
- [ ] Make identities for legacy creations deterministic from their original
  event identity; include stable snapshot-record positions for imported entities.
  Do not rewrite source journals to implement this mapping.
- [ ] Specify legacy reference resolution explicitly. Honor unambiguous references
  and existing suffixed IDs. For colliding unsuffixed IDs, do not assume that the
  mutation's device proves which object was selected: old events lack causal
  context and can be genuinely ambiguous after previous syncs.
- [ ] Surface ambiguous legacy mutations as unresolved diagnostics instead of
  applying them to a guessed entity. Provide an explicit mapping repair event
  referencing the original event and intended stable entity, after user selection.
  Test replay of that repair without altering historical lines.
- [ ] Version the new event/reader contract and document a coordinated writer
  upgrade. Do not claim old binaries are safe merely because a schema field was
  incremented; inspect their compatibility checks. Mixed old/new writers remain
  unsupported until a specific tested protocol exists.

Tests: offline duplicate aliases followed by keep/miss/move/grade; out-of-order
journal delivery; identical timestamps; three concurrent sessions on one device;
legacy suffixed IDs; imported records; truly ambiguous legacy mutations; mapping
repair; and rejection of duplicate immutable IDs with different creation content.

Acceptance: both devices converge on the intended entity statuses and assignment
verdicts. No existing ambiguous history is silently reassigned. Original journals
remain byte-for-byte unchanged by upgrade/rebuild.

## M4 — Publish consistent generations of views

- [ ] Add a per-device rebuild lock under `.local`. Require working locking for
  the concurrent-session guarantee, with a clear preflight error if unavailable.
  Define lock acquisition order; avoid re-entering the append lock from rebuild.
- [ ] Capture a sorted source signature before input collection; copy/read the
  input into staging, then compare signatures after collection. Retry changed
  inputs with a bounded attempt count. Record the signature of the input used.
- [ ] Never replace that recorded signature with a later fingerprint. A journal
  arriving after collection must leave the published generation detectably stale.
- [ ] Build JSON, JSONL, Markdown, and integrity metadata in one generation under
  `.local/generations/<id>/`. Render from staged JSON, not live views.
- [ ] Publish only fully validated generations by atomically replacing a single
  `current` pointer on the same filesystem. Retain compatibility paths for
  `.local/views` and `.local/render` without sequential publication of files.
- [ ] Pin the resolved generation once per CLI read/command phase and dashboard
  request; repin deliberately after a command writes an event. A symlink switch
  alone does not prevent mixed reads across multiple file opens.
- [ ] Preserve the last complete generation on interruption or retry exhaustion;
  report stale/busy rather than fresh. Clean abandoned staging safely. Retain
  published generations until active readers release them; document the bounded
  reader-retention/cleanup mechanism before enabling automatic deletion.
- [ ] Keep a failed append distinct from a successful durable append followed by
  a refresh failure, so callers do not retry and duplicate a recorded mutation.

Tests: arrival after collection, during rendering, and before publication;
overlapping rebuilds; readers spanning pointer replacement; process termination
before publication; missing derived files; no-change fast path; sustained churn
and bounded retries. Assert both coherent output and honest freshness.

Acceptance: a generation is never labeled fresh using a signature of unread
events. Readers never combine files from different generations. Failed refresh
does not erase the last complete state or misreport a committed event as absent.

## M5 — Diagnose damaged history and recover journal conflicts

- [ ] Add event-aware journal validation without changing generic JSONL helpers'
  behavior for unrelated callers. Identify file and line/event identity in errors.
- [ ] Distinguish an incomplete final line from malformed interior records,
  invalid event envelopes, unsupported event versions/types, and conflicting
  event identities. Avoid logging complete sensitive payloads by default.
- [ ] Exclude `*.sync-conflict-*` journals from ordinary replay. Otherwise their
  duplicated event prefixes can double-count logs, sessions, or commitments.
- [ ] Persist integrity diagnostics alongside each generation and expose them in
  CLI/dashboard status. A tolerated incomplete tail is visible as a warning;
  fatal integrity failures preserve the last good generation and mark it stale.
  Allow status/diagnostic commands to run even if normal state refresh fails.
- [ ] Add a journal-specific read-only recovery preview: compare event identities,
  show duplicate and unique events, and flag differing payloads for one identity.
- [ ] Implement explicit preservation-first recovery for unambiguous unions: keep
  source backups, import missing events without inventing new identities, and
  deduplicate by stable event identity during replay. Do not modify peer-owned
  journal files. Refuse automatic resolution of divergent same-identity events;
  keep both files and explain the required manual reconciliation.
- [ ] Make repeated recovery idempotent and retain diagnostic evidence. Generic
  keep-original/use-copy actions must remain unavailable for journals.

Tests: partial tail, malformed middle line, valid JSON with invalid envelope,
unsupported version, identical duplicated prefix, unique events in either copy,
same identity/different content, restart during recovery, and recovery rerun.

Acceptance: damaged or conflicting history cannot be silently presented as a
healthy complete view, and recovery never drops a unique valid event unnoticed.

## M6 — Refresh the dashboard reliably

- [ ] Replace maximum-mtime watching with a sorted per-file signature containing
  name, size, and nanosecond mtime, aligned with M4's freshness contract. Include
  additions, removals, and conflict/integrity changes.
- [ ] Refresh on startup when required, including journals delivered before the
  watcher was created. Advance the successful signature only after publication.
- [ ] Retry transient refresh failures with bounded backoff; expose the current
  failure without killing the watcher or continuously spawning CLI processes.
- [ ] Publish SSE refresh notifications after the new generation is available.
  Keep prose/config changes visible independently of journal generation changes.
- [ ] Add separate bounded health polling for M7: daemon/peer connectivity can
  change without any vault file changing. Do not block ordinary page reads on
  repeated transport probes.

Tests: an older peer file arriving under a newer maximum, same-second same-size
replacement, deletion of a non-newest file, failed callback then success with no
further journal write, startup with stale views, and notification ordering.

Acceptance: delivered events appear without a local mutation or manual reload,
and transient refresh failures recover without needing another file change.

## M7 — Make setup and sync health actionable

- [ ] Centralize bounded Syncthing API calls and structured error classification.
  Before implementing new endpoints, verify request/response shapes against
  current official Syncthing documentation and representative supported versions.
- [ ] Canonicalize equivalent folder paths. Adopt the actual ID of an existing
  matching folder; expose it in setup output, status, and pairing instructions.
- [ ] Add `sync setup --folder-id ID` for a receiving device/custom registration.
  Keep `dave-vault` as the default only for a new folder. Detect ID/path collisions;
  do not rename, rebind, or replace another existing folder automatically.
- [ ] Preserve existing sharing/versioning configuration when patching owned
  settings. URL-encode folder IDs in API paths.
- [ ] Implement credential precedence with source tracking: explicit environment,
  local configuration, then daemon XML discovery. If an explicit credential fails,
  report it; if a saved credential is rejected, try rediscovery and persist a new
  key only after a successful authenticated request.
- [ ] Honor explicit config paths, XDG config/state directories, and supported
  defaults. Parse GUI settings without assumptions about unrelated XML blocks.
  Report TLS/certificate failure separately; do not disable verification to make
  discovery succeed or expose keys in diagnostics.
- [ ] Offer daemon startup only for appropriate unavailable-local-daemon cases,
  not authentication/TLS errors. Keep installation and startup tty confirmations.
- [ ] Add structured status fields for configuration, API reachability/auth,
  actual folder identity, pause/error state, sharing, per-peer connectivity and
  pending delivery, local freshness, and journal integrity. Retain legacy fields
  as derived compatibility summaries while migrating callers.
- [ ] Define health precedence: errors/unknown measurements must not become
  healthy zeroes; unshared has no delivery target; offline means delivery is
  unknown/pending; caught-up requires a current successful observation for the
  reported connected peers. Do not imply every offline peer has acknowledged.
- [ ] Persist timestamps of successful observations locally. Display observation
  age and distinguish it from last journal event time or durable acknowledgement.
- [ ] Use a bounded aggregate probe budget and cache health briefly for dashboard
  reads. Surface pending bytes/items when supported and preserve useful partial
  results when an endpoint fails or is unavailable on a supported version.
- [ ] Make setup output distinguish local preparation, registration, and pending
  pairing. Keep local operation usable during transport outages.

Tests: no credentials, bad explicit key, rotated saved key, custom XDG state home,
TLS failure, timeout, malformed response, unsupported endpoint, custom ID,
trailing-slash path, ID collision, paused folder, folder error, no remote devices,
one connected/one offline peer, pending transfers, caught-up observation, stale
cached observation, and daemon loss without a journal change.

Acceptance: status provides a useful next action and never equates registration
or `enabled=true` with delivery. Existing folder IDs work across both devices.
Mock responses cover the declared API contract; no real account is required.

## M8 — Provide a safe second-device upgrade path

- [ ] Document separate flows for a fresh device, an existing schema-2 tree, an
  existing schema-3 tree, and a manual copy. Keep the local setup instructions
  beside the sync/migration feature rather than in unrelated safeguards.
- [ ] For legacy peers, stop old writers first, back up outside the shared tree,
  inventory unsynced differences, and choose the authoritative initial import.
  Do not independently import identical history on both devices.
- [ ] Preserve device-specific checkout paths/hooks in a local backup. Reconcile
  unique legacy work explicitly before replacing the receiving tree; do not
  silently archive differences as if they were already imported.
- [ ] Prepare an empty receiving location with local ignores before accepting the
  share. Receive shared history, initialize a new local identity, and restore only
  this machine's intended overrides. Do not restore another machine's device ID,
  sequence counter, credentials, generated views, or transport configuration.
- [ ] Add a non-destructive onboarding/preflight check with actionable diagnostics
  for remaining legacy files, missing ignores, existing local identity, and mixed
  writer versions. It must not bulk-delete, pair devices, or rewrite history.
- [ ] State manual-copy exclusions explicitly: `.local`, migration archives,
  temporary files, and device-specific transport state. Recreate local ignores
  and identity before writing. Cloned identity cannot always be detected from
  one local tree, so do not promise automatic clone detection.
- [ ] Document verification: unique device IDs, expected shared folder ID,
  protected local paths, expected entity counts, one event originating on each
  device, and consistent rebuilt results after exchange.
- [ ] Document rollback before writes and recovery after writes separately. Never
  replace shared journals with a backup after new events have been accepted.

Tests: pristine receiver; legacy peer with leftover root files; local hooks/path
restoration; peer with unsynced work; repeated onboarding checks; manual-copy
fixture omitting `.local`; distinct identities and journals after first writes.

Acceptance: following the documented flow avoids exit-4 dead ends, duplicate
snapshot imports, copied writer identities, and loss of device-local settings.

## M9 — Integration, documentation, and completion gates

- [ ] Run focused shell groups and dashboard tests for each changed milestone.
  Add test groups if existing substring filters cannot target the new cases.
- [ ] Run an automated two-home soak with deterministic journal exchange: both
  offline, overlapping sessions, alias collisions and subsequent mutations,
  delayed arrivals, interrupted rebuild, conflict detection/recovery, and restart.
  Assert semantic results and event preservation, not just byte equality.
- [ ] Exercise dashboard status and conflict preview/actions through its loopback
  API. Verify keyboard operation, readable errors, and accessible labels for the
  changed controls in a local browser fixture when browser tooling is available.
- [ ] Update CLI help, command docs, bundle instructions, README references, and
  `docs/dave-sync.md`. Remove claims of immediate delivery or impossible conflicts
  that exceed the tested guarantee. Record additive JSON/action compatibility.
- [ ] Run `bash scripts/verify.sh`. Repair the stale verifier comment that calls
  the current sync exercise a Git-push test; inspect the tests and remove obsolete
  skip logic only after confirming every sync test uses mocks/loopback transport.
  No verification command may publish or contact real configured providers.
- [ ] Run `git diff --check`; verify required new fixtures/helpers stay bundled
  and links resolve. Update the root catalog only if entries/descriptions change.
- [ ] Record test commands/results and any environment limits below. A real
  Linux↔WSL2 Syncthing smoke test remains a deployment follow-up requiring access
  to both devices; mocks must not be reported as that test. Supply a checklist
  for connect, offline writes, reconnect, daemon restart, and custom folder ID.
- [ ] Review all coverage rows, close completed checkboxes, and summarize residual
  limitations. Do not mark a milestone complete if its acceptance criteria fail.

## Compatibility, rollout, and rollback

1. Land regression coverage and ignore/containment protections in focused changes.
2. Implement and test identity and generation changes together with compatibility
   readers. Capture a disposable legacy baseline before changing replay behavior.
3. Upgrade all writers before enabling the new event format in a real shared vault;
   document version requirements and prevent unsupported writes in new tooling.
4. Keep journals immutable. Backups and repair mappings belong in the recovery
   procedure, not an automatic destructive journal rewrite.
5. Reverting cache implementation can rebuild from compatible journal input;
   reverting to an old writer after new-format events exist is not safe by default.
   Prefer roll-forward repair unless replay compatibility was explicitly verified.

## Decisions to close during implementation

These are bounded engineering decisions, not missing user requirements. Record
the selected design and evidence here before closing the related milestone.

| Decision | Proposed default | Resolve by |
|---|---|---|
| Entity/event compatibility | Add stable IDs, retain aliases, explicitly diagnose ambiguous legacy updates | M3 |
| Generation retention | Atomic pointer plus pinned readers; remove only unreferenced generations | M4 |
| Integrity policy | Warn on partial tail; preserve last good view for fatal corruption; keep status usable | M5 |
| Journal recovery representation | Idempotent preserved-event import with original identities and payload comparison | M5 |
| Supported Syncthing APIs | Verify official contracts; degrade unavailable metrics to unknown | M7 |
| Receiving-device automation | Non-destructive preflight and documented migration; no automatic reconciliation of unique history | M8 |

## Execution log

| Date | Milestone | Change / evidence / blocker | Status |
|---|---|---|---|
| 2026-09-19 | Planning | Review mapped to M0–M9; no implementation performed | Plan created |
| 2026-09-19 | M3 | Fixed a stale presentation join: `_mission_rows`, the global `mission status` filter, and `readers.py assignment_rows` still folded `type == "record"` rows that the reducer no longer emits, so every graded charge read as open. Verdicts are now read from the row the reducer folded by entity identity. Evidence: `run.sh mission` 46/46 | Fixed |
| 2026-09-19 | M5 | Fixed journal recovery preview counts: `index($id)` compared identity pairs as a *subsequence*, so every incoming event counted as unique and none as duplicate. Replaced with a keyed lookup. Evidence: `test/integrity.py` 4/4 | Fixed |
| 2026-09-19 | M0/M1/M3 | Updated two stale assertions to the intended behavior rather than weakening them: `.stignore` is root-anchored `/.local` (M1), and `state.json` now carries `identity_diagnostics` (M3) | Aligned |
| 2026-09-19 | M2 | Implemented containment and effect clarity: canonicalized operands, symlink refusal, basename-only suffix parsing, `.local`/`.migrated-*`/`journal/` exclusion, canonical `keep-original`/`use-conflict-copy` with legacy aliases, read-only bounded `sync conflicts preview`, digest-guarded resolve, and `.local/conflict-recovery` copies. Dashboard previews before every destructive action and sends the digests. Evidence: new `sync_conflict_safety` group 15/15, `review-regressions.sh` traversal PASS (narrowed expected-failure list to `dashboard-refresh`), 3 new dashboard tests | Complete |
| 2026-09-19 | Verification | `run.sh` 437/437; `m1-ignore.sh` 16/16; `generations.py` 3/3; `integrity.py` 4/4; `test_dashboard.py` 21/21; `review-regressions.sh` 4 pass / 1 xfail (M6); `verify.sh` all checks passed; `git diff --check` clean | Green |

## Completion checklist

- [ ] All eight findings have a passing regression or verified documented flow.
- [ ] All four additional review recommendations are implemented and documented.
- [ ] No ambiguous legacy mutation is silently applied to a guessed entity.
- [ ] Freshness, health, and integrity accurately describe their measured state.
- [ ] Existing user edits, exclusions, source journals, and local settings survive.
- [ ] Full verification passes; any untested deployment behavior is named.
- [ ] Parent plan and this tracking file reflect the implementation as delivered.

Stage execution note: the user authorized staged implementation with smaller-model
agents and primary-agent review. M0 fixtures land alongside their fixes rather
than blocking unrelated implementation on intentionally failing tests. Initial
Terra agents were unavailable; work was reassigned to Luna agents.
