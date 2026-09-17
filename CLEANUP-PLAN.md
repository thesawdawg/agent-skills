# Agent skills: evaluation and cleanup plan

Date: 2026-09-16

Status: implementation in progress. Baseline plan committed as `c5aee69`.

> ## Review comments — Devin, 2026-09-16
>
> Inline notes below are marked `> **Review (Devin):**`. Verdict: the plan is sound and correctly scoped — the verified defects are real, and the sequencing (correctness → distribution → merges → docs → additions) is right. My main disagreements: (a) the `skills/<name>/` container relocation is unnecessary churn given how the installer actually discovers skills — flatten `pi-skills/` to root and leave `dave/skills/dave` in place instead; (b) a few places where the plan under-states (pi-skills invisibility, `../dogfood` breakage) or where a cheaper/more concrete fix exists. Details inline.
>
> Evidence I gathered independently for this review:
>
> - **Installer discovery test (the big one):** `npx skills add thesawdawg/agent-skills --list` (skills@1.6.0) reports **16 skills: all 15 root skills plus `dave` (found via the `dave/skills/dave/` layout) — and none of the five `pi-skills/*` skills**. The pi-skills aren't merely redundant with root conventions; they are *not installable through the documented installer today*. This converts F4 from a tidiness issue into a functional defect and is the strongest argument for the user's instinct.
> - **`npx skill` is a different package.** `skill@1.0.2` (tonglei100/skill) is a CodeBuddy installer hardcoded to fetch `skills/<name>` subtrees from `vercel-labs/agent-skills` into `.codebuddy/skills/`; it has no `install` subcommand and cannot install this repo at all. If the user literally types `npx skill install`, nothing installs. The working command remains `npx skills add thesawdawg/agent-skills -g` — the plan's "confirm the actual installer" step is therefore mandatory, not pedantic.
> - **Playwright removal confirmed upstream** (microsoft/playwright#38151; removal announced in release notes). The replacement is `locator.ariaSnapshot()` (available since 1.49), which returns a YAML-ish text tree — arguably a *better* LLM-consumable format than the old JSON snapshot.
> - **Duplication measured:** ~2,200 lines of `USE_CASES.md`/chooser material (14 per-skill files + root 259 + pi-skills 543 + dave 207) plus a 781-line retired implementation plan and per-skill READMEs — against ~4,400 lines of actual `SKILL.md`. Roughly a third of the repo's markdown exists to help selection, a job frontmatter `description` already does (and demonstrably does well — the CLI's `--list` output is entirely description-driven).
> - **Doc destruction confirmed:** `doc-repo.sh revert` runs `git clean -fd` over the whole docs root — it permanently deletes untracked user files, not just files the run created.
>
> Recommended deltas to this plan, summarized: (1) replace the `skills/` container move with a flat-root flatten of `pi-skills/`; (2) keep `dave/skills/dave/` where it is — it's already discovered and already the plugin's internal layout; (3) ship Phase 1's independent fixes as small commits immediately; (4) add release tagging, a repo `AGENTS.md`, a shared `scripts/preflight.sh` convention, and a `--list` snapshot test to §6; (5) treat the `code-review` extraction as Phase-5 default-yes rather than "if used often enough"; (6) decide `app-design`'s name in Phase 3 while renames are cheap.

## Executive recommendation

**Keep a collection of small, useful skills. Stop maintaining separate harness identities, repeated selection guides, and competing orchestration workflows.**

The concern about complexity is justified, but this is primarily **duplicated instructions, packaging assumptions, and process**, not several copies of the same implementation. The browser driver is already shared, and the three formerly duplicated Pi/root skills have already been consolidated. Do not undo that reuse or collapse every specialist into one enormous skill.

Recommended direction:

1. One discoverable, harness-neutral catalog, installed through the skills CLI.
2. Remove `pi-skills/` as a category. Move three skills and merge the other two into existing workflows.
3. Retain D.A.V.E. as a portable skill with optional plugin integrations, not a plugin that needs conversion to become a usable skill.
4. Make independently selected installations work, or report explicit missing dependencies before starting.
5. Reduce mandatory interviews, artifacts, agent handoffs, and repeated documentation.
6. Add packaging checks, behavioral evaluations, and targeted runtime tests before adding more skills.

**Do not build a new installer, orchestration framework, browser framework, or skill registry to accomplish this cleanup.**

## 1. Scope and installation contract

The user confirmed that D.A.V.E. should remain supported, with agent-specific integrations optional. Existing repository files remain untouched by this assessment.

There are **21 `SKILL.md` entry points**:

- 12 task skills at the root.
- 3 convention skills: `coding-style`, `workflow-rules`, `memory`.
- 5 skills under `pi-skills/`.
- 1 nested D.A.V.E. skill, plus nine agent definitions, commands, hooks, and scripts.

The root README's “13 skills” count does not match its 12 non-D.A.V.E. task entries. The repo is also not literally “no runtime”: several skills bundle executable shell, Python, or Node helpers.

### Confirm the installer, not just its nickname

The user referred to `npx skill install`. This repository documents **`npx skills add thesawdawg/agent-skills -g`**, which matches the public Vercel skills CLI documentation reviewed for this assessment. The exact locally used package/version was not established. Do not silently assume that the singular package or `install` command is an alias.

Before implementation, record the actual installer package/version and test that version. For the documented CLI:

- `npx skills add ... --list` lists discoverable skills.
- `--skill <name>` permits selective installation.
- Symlink mode links agent directories to a canonical installed copy; it does not make the entire source repository available to each skill.
- Copy mode must work too.
- Discovery is layout-dependent and has changed over time. Current documentation names `skills/` as a standard container and describes separate plugin-manifest discovery.

A skill install must not be advertised as also registering plugin agents, commands, hooks, or always-on rules. Those are separate harness capabilities.

> **Review (Devin):** Resolved empirically — `npx skills add thesawdawg/agent-skills --list` works and discovers 16 skills (15 root + `dave`). Note it discovers `dave/skills/dave/` but *not* `pi-skills/*` — the five pi-skills are invisible to the installer as shipped. Also, if the user's "npx skill install" was literal: `skill` (singular) on npm is a different, CodeBuddy-targeted package that can only fetch from `vercel-labs/agent-skills`; it cannot install this repo. The README should also document the CLI's selective surface — `--list`, `--skill <name>`, `--copy`, `--all`, and `skills use` — since selective install is what makes "one repo, pick what you want" viable and weakens the case for splitting D.A.V.E. into its own repo.

## 2. Findings and evidence

### P0 — installation and execution correctness

#### F1. D.A.V.E.'s installable core depends on files outside its package

[The core skill](dave/skills/dave/SKILL.md) lives under `dave/skills/dave/`, but the role definitions live under `dave/agents/`.

- [common.sh](dave/skills/dave/scripts/lib/common.sh), lines 10–14, derives `PLUGIN_ROOT` by ascending three directories from `scripts/`.
- [mission.sh](dave/skills/dave/scripts/lib/mission.sh), lines 20–23 and 395–399, loads `<plugin-root>/agents/<role>.md` and refuses to pack a mission without it.
- The [Pi installer](dave/scripts/install-pi.sh) copies roles into `references/roles/`, but the core's default lookup remains the plugin path. It supports `DAVE_AGENTS_DIR`, but the installer does not make that installed role directory the default.
- Core documentation links also ascend to plugin/root documents that a selected-skill install need not contain.

**Consequence:** source-checkout tests can pass while an isolated installed skill lacks required role files. This is a static packaging defect; the exact user's installed copy was not exercised.

**Recommendation:** put canonical role contracts inside the D.A.V.E. skill and resolve them relative to the script. Make optional plugin agents thin wrappers over those contracts. Test installed `mission pack`, not just installed `init`.

> **Review (Devin):** Verified — `common.sh:13` derives `PLUGIN_ROOT` by ascending three dirs, and `mission.sh` dies when `$PLUGIN_ROOT/agents/<role>.md` is absent. Concrete minimal fix consistent with this recommendation: keep `dave/skills/dave/` where it is (it's already discovered by the CLI — see §4 note), move the nine role files to `dave/skills/dave/references/roles/`, and make `_agents_dir` default to `$SCRIPT_DIR/../references/roles` with `DAVE_AGENTS_DIR` and the plugin path as overrides. For the plugin's `agents/*.md`: prefer thin wrappers that *instruct the spawned agent to read the canonical role file first* over generated copies — Claude Code agents can read files, and wrappers-that-read can't drift the way a sync script can. If full copies are required by a host, generate them in CI from the canonical source with a drift check rather than maintaining two edited files.

#### F2. Shared browser setup is inconsistent, and the locked API is incompatible

[dogfood](dogfood/SKILL.md) resolves its own install path and documents a detached browser process. [accessibility-audit](accessibility-audit/SKILL.md), lines 14–46, instead uses `../dogfood/scripts` from the caller's working directory, assumes Chromium is preinstalled, and names `run_in_background: true` as though every harness exposed that option.

The [driver](dogfood/scripts/browser-driver.mjs), line 103, calls `page.accessibility.snapshot()`. The [lockfile](dogfood/scripts/package-lock.json) selects Playwright **1.61.1**. Playwright's official **1.57** release notes say `page.accessibility` was removed.

**Consequence:** the snapshot command is incompatible with the declared locked dependency. This particularly undermines the text-only fallback used to claim portability. Confirmed by source/lockfile/upstream documentation, not by launching a browser in this assessment.

**Recommendation:** add a failing local browser smoke test, replace the obsolete call with a supported snapshot API and documented output shape, and centralize browser setup instructions. Preserve the difference between a structural snapshot and an axe accessibility audit.

> **Review (Devin):** Verified — `package-lock.json` resolves `playwright-core@1.61.1`, and upstream removed `page.accessibility` (microsoft/playwright#38151). Two concrete fixes, cheapest first: (a) pin `playwright` below the removal release, or (b) switch the `snapshot` command to `locator.ariaSnapshot()` — returns an indented text tree that models consume *better* than the old JSON, so this is an upgrade disguised as a fix. Before doing either, seriously evaluate the plan's own suggestion to drop the driver: Playwright MCP, Chrome DevTools MCP, and `agent-browser`-style CLIs are now maintained substitutes for a hand-rolled 308-line driver plus the detached-`nohup`-and-poll choreography that dominates dogfood's SKILL.md. What's worth keeping regardless is the JSONL evidence-stream convention (which lives in the skill text, not the driver). One more defect worth calling out explicitly: `accessibility-audit`'s `../dogfood/scripts/...` resolves relative to the *user's working directory*, so it isn't just inconsistent — it is broken in every scenario except running from inside the source checkout. That's a hard sibling dependency that must be declared and preflighted per packaging rule 3, not documented around.

#### F3. Policy conflicts and cleanup ownership need resolution

- [workflow-rules](workflow-rules/SKILL.md), lines 14–15, says never push, without exceptions.
- [D.A.V.E.](dave/skills/dave/SKILL.md), lines 268–275, directs an automatic closeout `sync push`.
- [commit-documentor](commit-documentor/SKILL.md) allows an explicitly approved remote publishing workflow, which still conflicts with the blanket no-push convention.
- [doc-repo.sh](commit-documentor/scripts/doc-repo.sh), lines 129–132, reverts/cleans the configured docs tree rather than tracking only drafts created by the current run. Its repo-mode commit also needs a regression test for unrelated pre-staged files.
- [dogfood](dogfood/SKILL.md), line 65, unconditionally truncates an existing findings file on startup.

**Recommendation:** retain the user's no-push default. Skills must stop at a prepared diff/commit and give the user the next command where policy prohibits publication. Do not reinterpret a skill invocation as permission to override policy. Any future exception must be explicitly decided by the user. Track run-owned output; never reset, clean, or overwrite unrelated work as routine cleanup.

> **Review (Devin):** Agree, and I'd sharpen two items. `doc-repo.sh revert` (`checkout --` + `clean -fd` over the whole docs root) can permanently destroy untracked files the run never created — I'd remove the `revert` subcommand outright rather than repair it; if rollback is wanted, track a per-run manifest of written files and delete only those. For dogfood's `: > issues.jsonl` truncation: prefer fail-if-exists or a run-ID'd output dir over silent truncation. On no-push: note that D.A.V.E.'s `sync push` exists specifically to sync `~/.dave` across devices (added in commit 48e241c) — the user may want to keep *that* as a deliberate, explicitly-invoked exception while keeping the blanket default. The fix is that no skill may *auto-invoke* it; requiring the user to run `dave sync push` themselves preserves both the feature and the policy.

### P1 — duplication and needless process

#### F4. `pi-skills/` is no longer a meaningful product boundary

[Its README](pi-skills/README.md) already states that root `dogfood`, `dependabot-validator`, and `pr-grill-me` use the same four-tool baseline. Root [app-design](app-design/SKILL.md) even calls itself “pi edition” and asserts that Pi lacks question and todo tools.

The useful requirements are **capabilities and execution assumptions**, not a separate harness brand: filesystem access, shell availability, stateless commands, browser support, image viewing, network access, and delegation.

**Recommendation:** promote useful portability practices to the authoring guide and specific preflight sections. Prefer supported native tools when available; document shell fallbacks where useful. Remove universal claims such as “every harness has Bash,” “you are multimodal,” or “Pi has no subagents.” Say what is available in the current session.

> **Review (Devin):** Stronger than stated: the CLI discovery test shows `pi-skills/*` isn't surfaced by `skills add` at all, so this boundary currently makes five skills uninstallable via the documented path — it's a defect, not a style choice. Second: don't delete `pi-skills/README.md` wholesale. It is the best authoring document in the repo — the capability→portable-fallback table, the no-shell-state rule, JSONL append over growing JSON arrays, detached long-lived processes, the small-model writing rules, and the security expectations are how *every* skill here should be written, not a pi-specific annex. Move it nearly verbatim into the authoring guide (STRUCTURE.md or a new AUTHORING section) rather than extracting a diluted summary. Third: preserve the attribution table per-skill (each moved skill should carry its upstream MIT notice in its own directory so attribution survives selective install).

#### F5. Three layers repeatedly describe selection and execution

The repository has a root chooser, per-skill `USE_CASES.md` files, a separate **543-line** Pi chooser, skill introductions, and additional README files. [STRUCTURE.md](STRUCTURE.md), lines 34–47, incorrectly treats `USE_CASES.md` as necessary for skill discovery. The Agent Skills specification requires `SKILL.md`, not that extra file.

Visible drift includes:

- Root counts and “no runtime” wording.
- “Mode A” in dogfood's app-design cross-reference after app-design's lifecycle changed.
- A claim at the end of the Pi README that the repo has no top-level license, although [LICENSE](LICENSE) exists.
- [D.A.V.E.'s 781-line implementation plan](dave/IMPLEMENTATION-PLAN.md) says all phases landed and explicitly asks to be removed or folded into documentation afterward.

**Recommendation:** one short human catalog, one authoring guide, frontmatter for activation, and on-demand examples only when they genuinely improve execution. Preserve upstream copyright/license notices before removing the Pi README. Avoid replacing these documents with a second hand-maintained metadata registry.

> **Review (Devin):** Agree, and I'd go one step further than "remove the mandatory requirement": delete per-skill `USE_CASES.md` outright. STRUCTURE.md's rule that "a skill without one is invisible to selection" is empirically false — the CLI found every skill purely via frontmatter `description`, and no harness reads `USE_CASES.md`. Folding the one or two best worked examples per skill into `references/` keeps their real value without maintaining 14 parallel selection docs. Quantified: ~2,200 lines of chooser material vs ~4,400 lines of actual skill content. The single remaining chooser should be the README table, generated or at least validated against the directory listing in CI so counts can't drift again.

#### F6. Delegation has competing owners and disproportionate defaults

[D.A.V.E.'s contract](dave/skills/dave/references/delegation-contract.md) covers role selection, task briefs, review, grading, and sequencing. [subagent-driven-development](pi-skills/subagent-driven-development/SKILL.md) repeats these responsibilities and mandates an implementer plus two reviewers per task and a final reviewer.

Meanwhile, [codex-delegate](codex-delegate/SKILL.md) deliberately resumes a continuous thread. These are different backend/session strategies, not policies every task should satisfy simultaneously. “Fresh focused pass in the main loop” also is not an independent reviewer or a new context.

**Recommendation:** D.A.V.E. owns optional multi-step coordination; provider skills own invocation/session mechanics. Keep ordinary direct execution as the default for small tasks. Let one review check both specification and quality unless risk justifies separate reviews. Reuse a worker for follow-up on the same task; use actual separate context when independent review is requested and supported. State honestly when only self-review occurred.

> **Review (Devin):** Agree. Worth naming the salvageable kernel in `subagent-driven-development` before folding it: "fresh context per task + fully self-contained brief pasted into the prompt + explicit acceptance criteria" is a genuinely good delegation pattern that D.A.V.E.'s contract should absorb as a reference section. The parts to drop are the *mandates* (implementer + two reviewers + final reviewer per task as default). Also endorse keeping codex-delegate/ollama-delegate as pure invocation mechanics — resisting the urge to give them policy is correct; they're adapters, not orchestrators.

#### F7. Role names and stage boundaries create work rather than clarify it

`ideator` means project scoping as a standalone skill and approach generation as a D.A.V.E. agent. `constructor` means architecture as a skill and implementation as an agent. The README and delegation contract repeatedly explain these collisions.

`app-design` rejects new projects, then takes ownership of writing specifications and milestone plans after the new-project chain. `constructor` already gathers the relevant architecture and constraints but mandates five separate output documents.

**Recommendation:** use one meaning per name, put implementation-plan ownership in the architecture/planning workflow, and make detailed artifacts optional sections of a useful primary document. Do not make a user repeat an interview when the approved brief already answers it.

> **Review (Devin):** Agree, plus a naming point the plan skirts: `app-design`'s name lies — it audits existing repositories and explicitly refuses new projects. Since this is a personal repo with a small install base, renaming it (e.g. `app-audit` or `repo-audit`) is cheap *now* and gets more expensive with every install. Decide in Phase 3 alongside the roster renames; if kept, at least fix the description to lead with "audit an existing app" (it already does — the mismatch is only the name). Same logic applies inside D.A.V.E.: renaming agent-Constructor → implementer and merging agent-Ideator → options removes the documented collision at the source, which also lets the README drop its "two name collisions" section entirely.

#### F8. Conventions are not an always-on policy mechanism

`coding-style` and `workflow-rules` duplicate git, type-hint, documentation, and general engineering rules. Both the root chooser and structure guide claim conventions load automatically; a portable `SKILL.md` cannot enforce that.

[flask-tests](flask-tests/SKILL.md) also contains concrete fixtures, module paths, and database assumptions for a different application. Installing it globally does not make those facts true in the current repository. [memory](memory/SKILL.md) should coexist with an existing harness memory system instead of asserting none exists.

**Recommendation:** merge the two conventions into one opt-in workflow/style package with detailed language guidance loaded on demand. Actual always-on behavior belongs in explicitly configured host/project rules, not an installation promise. Move the Flask-specific guidance to its owning project; do not invent a generic test framework to justify retaining it here.

> **Review (Devin):** Agree with one nuance: in harnesses that surface all installed skills, "use whenever writing code" descriptions *do* function as de-facto always-on — the defect is the enforcement promise, not the mechanism. So the merged skill should say plainly: "this is advisory; for guaranteed enforcement copy the relevant rules into the project's `AGENTS.md` / host rules file" — actionable instead of aspirational. On flask-tests: agree, relocate to the owning project (its `.agents/skills/` or AGENTS.md). Keep it here until the destination exists — but add a deprecation note to its frontmatter description now so it stops being picked up in unrelated projects.

### P1 — verification does not yet protect the public contract

#### F9. Existing tests are useful but incomplete

No repository-wide validation/CI entry point was found. D.A.V.E. has substantial state tests and an installer self-test; the deployment parser has a self-test. Equivalent behavioral tests were not found for the browser driver, Codex/Ollama wrappers, or documentation publishing helper.

The mission test run reported **46 passed, 0 failed** while also emitting:

```text
scripts/test/run.sh: line 576: today: command not found
```

The fixture calls a helper unavailable in the test shell; the runner still reports success. The Pi installer self-test passes but checks installed `init`, not installed `mission pack`.

**Recommendation:** count unexpected fixture/command failures as failures, without breaking intentionally asserted nonzero exits. Add copy/install execution tests and small trigger evaluations, not just more assertions that files exist.

> **Review (Devin):** The `today` failure is a one-line bug — `run.sh:576` calls `$(today)`, which isn't a function or a binary (should be `$(date +%F)` or a `today()` helper). Add to the CI set: `bash -n` + shellcheck across `dave/skills/dave/scripts/`, `node --check` on the driver, auto-discover and run every `*--selftest*`, and a `skills add --list` snapshot asserting the expected name set — that last one is the regression test that would have caught the pi-skills invisibility before this review did.

## 3. Skill-by-skill decisions

Preserve public skill names where possible. The proposed `skills/<name>/` layout changes location, not identity.

| Current entry | Decision | Result / rationale |
|---|---|---|
| `ideator` | Keep, shorten | Project brief and scope. Reuse supplied answers; avoid mandatory personality and repeated handoff explanations. |
| `constructor` | Keep, clarify | Architecture plus optional implementation plan. Move spec/milestone templates here from app-design. One primary architecture document by default, with sections instead of five required files. |
| `datasecurer` | Keep separate | Threat model, data protection, and recovery requirements are not ordinary architecture or runtime penetration testing. Reuse the approved brief; emphasize recovery verification. |
| `app-design` | Keep, narrow | Existing-repository assessment, including non-web and skill/script repositories. Support assessment-only mode without mandatory runtime QA or a new-project round trip. |
| `dogfood` | Keep, extend | Own functional QA and optional persona/UX assessment, one browser session and one evidence stream. |
| `accessibility-audit` | Keep separate | Standards-specific evidence, manual checks, coverage limits, and per-criterion reporting warrant a separate entry point. Reuse browser facilities, not the entire dogfood workflow. |
| `codex-delegate` | Keep, simplify | Codex invocation, session lifecycle, sandbox boundary, and output handling. Not a second general orchestration policy. |
| `ollama-delegate` | Keep, simplify | Text-only HTTP backend, model selection, bounded concurrency, output validation. Not interchangeable with a file-editing agent. |
| `dependabot-validator` | Keep, modestly extend | Allow manual/Renovate dependency updates when explicitly requested. Keep ecosystem-specific checks; do not require bot authorship as the source of truth. |
| `pr-grill-me` | Keep distinct | Author interview is the feature. Fix base/head handling; do not turn every code review into an interview. |
| `commit-documentor` | Keep, reduce setup | Preserve local/separate-repo modes; make an index optional for small documentation trees. Separate drafting, committing, and publishing; scope all operations to approved files. |
| `flask-tests` | Relocate | Move application-specific rules to the owning project after confirming its location. Keep available until that destination is established; do not silently delete it. |
| `workflow-rules` + `coding-style` | Merge | Retain `workflow-rules` as the public entry; move detailed style content into its references. Preserve user preferences rather than silently changing them. |
| `memory` | Keep optional | Reuse the configured memory location/provider; handle a missing index normally; do not duplicate facts already recorded by D.A.V.E. or the project. |
| `dave` | Keep, decouple | Portable state/priority skill with self-contained roles and optional host integrations. Preserve existing state and shell modules. |
| `pi-skills/adversarial-ux-test` | Merge into dogfood | Optional persona scenario and friction triage. Use task constraints rather than age stereotypes, forced complaints, or arbitrary click counts. Clearly label simulated feedback, not real user research. |
| `pi-skills/rest-graphql-debug` | Move unchanged in identity, shorten | Keep diagnosis flow in SKILL.md; move the 475-line reference material into focused symptom references. Declare optional Python `requests` dependency rather than assuming it exists. |
| `pi-skills/web-pentest` | Move, retain separate authorization boundary | Preserve authorization, scope, evidence protection, and non-destructive limits. Do not silently activate it from ordinary QA. Add defensive guardrail tests; do not expand offensive functionality as part of cleanup. |
| `pi-skills/cloudflare-temporary-deploy` | Move, harden | Distinct deployment task; retain parser and public-exposure approval. Verify a supported Wrangler version, avoid `@latest` instructions, and preserve the deployment process exit status through parsing. Do not redeploy merely to reveal a previously issued claim URL. |
| `pi-skills/subagent-driven-development` | Fold into D.A.V.E. execution reference | Keep acceptance criteria and staged verification; remove duplicate orchestration entry point after migration. If actual usage demands execution without D.A.V.E. setup, retain a very small stateless entry instead of forcing a priority-management ceremony. |

Expected steady-state catalog: **17 entries** if the proposed merges and Flask relocation are accepted, before any optional new entry. This is a consequence, not a quota; successful routing and preserved capabilities matter more than the count.

> **Review (Devin):** Table endorsements and refinements:
>
> - **`web-pentest` (keep separate):** strongest possible agree — it's the repo's one real safety surface. Retain the pi-README's "STOP — do these first" block convention verbatim at the top; that's exactly the case where mandatory-guardrail callouts earn their lines. Also worth keeping its pi-README sandbox/permission-gate guidance as a reference even after the pi branding is gone — it's good defensive practice for *any* harness.
> - **`adversarial-ux-test` → dogfood:** agree, and the merger gets easier once the browser driver question is settled — do the driver decision first, merge second, so the persona mode inherits whatever browser path survives.
> - **`rest-graphql-debug` (475 lines):** the single best candidate for the "lookup, not linear script" split — most of its bulk is symptom/reference tables that belong in `references/` regardless of where the skill lives.
> - **`cloudflare-temporary-deploy`:** add to "harden": pin a wrangler version in the docs and capture the deploy subprocess exit code explicitly — the parser passing while the deploy failed is a live failure mode.
> - **`subagent-driven-development`:** folding into D.A.V.E.'s execution reference is right; I'd go further and say *delete* the standalone entry rather than keep a "very small stateless entry" — resurrect it only if dave-less usage is actually observed. A kept-in-case skill is exactly the kind of duplication this cleanup is removing.
> - **`pr-grill-me`:** the base/head bug is real — `git diff HEAD..pr-N` diffs against *current checkout*, not the PR base. Fix: `gh pr view <N> --json baseRefName` (or remote default branch) then three-dot `git diff origin/<base>...pr-<N>` (merge-base semantics).
> - **`dependabot-validator`:** modest extension to manual/Renovate updates is fine; the name then misleads — consider `dependency-update-validator` or just let the description carry it.
> - **`memory`:** agree keep-optional; add that it should detect an existing harness memory system and defer rather than maintain a parallel store — the plan covers this, just flagging it's the difference between useful and harmful.
> - Missing from the table: **`app-design` rename decision** (see F7 note) and **`codex-delegate`/`ollama-delegate`** — agree they stay mechanics-only; also worth deleting their extra `README.md` files (they're the only skills with both README and USE_CASES — three doc layers for a delegation adapter).

### D.A.V.E. roster cleanup

Reduce overlapping roles without rewriting the state engine:

- Keep **Quartermaster** for intake/reconciliation and **Scribe** for work summaries.
- Keep **Cartographer** for reusable structural maps; use app-design only for a broader assessment.
- Use **Scout** for focused research, including dependency research as a selectable mode rather than a mandatory ModuleFinder stage.
- Consolidate Brainstormer/agent-Ideator into an **options** role; project inception still invokes the standalone ideator skill.
- Rename agent-Constructor to **implementer**; standalone constructor remains architecture.
- Keep **Critic** for evidence-backed review, with a shorter, task-sized contract.

This yields seven clear roles rather than nine. Preserve old role identifiers as lookup aliases during migration; do not rewrite historical mission assignments. Model mappings belong to optional harness configuration, not portable assumptions that every host has Haiku/Sonnet/Opus.

> **Review (Devin):** Agree with the seven-role target. Two additions: (a) the alias layer should live in role *lookup* (a name→file map, e.g. a `aliases` block or a symlinked `references/roles/ideator.md → options.md`) rather than rewriting stored mission files — cheaper and lossless; (b) once the canonical roles move inside the skill bundle (F1), the roster doc and the role files become one source of truth — put the roster table in `references/roles/README.md` or the delegation contract, not a third place.

## 4. Target organization and ownership

Use a standard `skills/` container rather than simply moving Pi entries into another mixed-layout root. That makes the catalog obvious to maintainers and to the documented CLI discovery rules.

> **Review (Devin):** This is my main disagreement. The empirical discovery test shows `skills add` already finds skills at **flat root** *and* at `<dir>/skills/<name>/` (that's how `dave` was found) — the CLI does not need the container. Meanwhile the move costs: (a) the `git clone → ~/.claude/skills` install path, which relies on `SKILL.md` sitting at top level of the clone — after the move it lands at `~/.claude/skills/skills/<name>/`, and whether nested personal skills are discovered there is version-dependent and unverified; (b) every relative link, the `PLUGIN_ROOT` derivation, the plugin manifest, and `install-pi.sh`; (c) ~17 directory moves of churn for an organizational benefit that the README table already provides. **Recommended alternative achieving the same end state:** keep the flat root (it *is* the catalog), move `pi-skills/<name>` → `<name>`, and leave `dave/skills/dave/` exactly where it is — it's already discovered, already the plugin's internal layout, and moving it would break the plugin's relative structure for zero gain. If the `skills/` convention is still wanted for ecosystem-consistency reasons, verify the clone path on the harnesses the user actually runs *before* Phase 2 — but I'd treat that as optional polish, not part of the cleanup.

```text
README.md                    concise catalog, primary install, optional integrations
STRUCTURE.md                 authoring, portability, contribution, verification rules
LICENSE                      existing repository license
skills/
  <name>/
    SKILL.md                 trigger, requirements, short workflow, completion criteria
    references/              only detail needed on demand
    templates/               retain existing convention; no cosmetic rename to assets
    scripts/                 optional, self-contained runtime helpers
  dave/
    SKILL.md
    references/roles/        canonical role instructions and return contracts
    scripts/                 existing dave.sh and modular libraries
    templates/
dave/                        existing optional plugin integration surface
  .claude-plugin/            existing manifest, adjusted rather than duplicated
  agents/                    thin host wrappers over installed role contracts
  commands/                  optional shortcuts into the installed portable skill
  hooks/                     optional host lifecycle integration
  scripts/                   adapter setup only, not another skill installer
.claude-plugin/              existing marketplace metadata, if still used
scripts/                     repository validation entry point
tests/                       packaging and behavioral fixtures
```

### Packaging rules

1. A selected skill must contain every required local reference, template, and helper. Up-links to the repository chooser are human documentation links, not runtime dependencies.
2. Resolve the skill's own files from the loaded source path or script location. Resolve the user's project independently. Never assume the shell is currently inside the installed skill.
3. A cross-skill helper is an **explicit dependency**, not an accidental relative path. Initially keep the browser implementation owned by dogfood; accessibility-audit and browser-based security checks either find that installed dependency or use a verified compatible host browser capability. Missing dependency means a clear preflight result, not a pretend successful run.
4. Use standard frontmatter such as `compatibility` for requirements where appropriate. Do not assume custom metadata causes the installer to install dependencies automatically.
5. The optional D.A.V.E. plugin depends on the separately installed portable D.A.V.E. skill. Its wrappers locate that installation and invoke/read it; they do not carry another edited SKILL.md. If a host cannot support that arrangement, keep its current integration temporarily and document the limitation until tested.
6. The Pi installer should eventually configure only optional shortcuts/integration. It must not transform/copy a second implementation of the portable skill.
7. Do not add root-level shared runtime libraries unless they will be included in the installed bundles. Avoid a dependency-resolver framework: a small explicit preflight for the few real dependencies is sufficient.
8. Runtime dependency installation should be reproducible and respect read-only skill installations. Prefer a lockfile-backed setup and an explicit writable cache when needed; do not routinely mutate the installed skill tree.

The distributable skill catalog is source content, not another host configuration directory. Preserve existing compatibility manifests; do not create parallel tool configurations unnecessarily.

> **Review (Devin):** Endorse all eight rules. Two additions:
>
> 9. **Scripts must not require a writable skill directory.** dogfood's `npm install` inside `scripts/` mutates the installed bundle — breaks on `--copy` installs owned by another user or read-only mounts. Install to a cache (`$XDG_CACHE_HOME`/output dir) with `npm ci`, or document it as user-managed environment setup.
> 10. **Validate links and attribution in CI.** A bundled `LICENSE`/NOTICE per adapted skill is a packaging property (selective install must carry it); broken relative links are the most likely regression of the flatten. Both are cheap greps, not a framework.
>
> Also flag rule 2's sharpest edge for symlink installs: `BASH_SOURCE`-derived paths resolve *through* the symlink, so scripts land in the canonical `~/.agents/skills` copy — correct — but any relative path that *wasn't* canonicalized (e.g. `../dogfood` from cwd, per F2) still breaks. The installed-bundle smoke tests should include the symlink case specifically.

## 5. Reduce process and documentation together

### A smaller SKILL.md contract

Use this shape as guidance, not another mandatory paperwork system:

1. When to use it, including the closest non-match.
2. Required input/capabilities and side-effect boundary.
3. A short workflow with explicit success and stop conditions.
4. Output and verification expectations.
5. Links to detailed references only where needed.

Aim for roughly 80–150 lines for ordinary workflows, but use a warning rather than a hard size gate. Complex safety-critical workflows may need more. Never move critical approval/scope rules out of the primary instructions merely to meet a line target.

> **Review (Devin):** Scale of the problem, measured: 9 of 21 SKILL.md exceed 150 lines — worst are `rest-graphql-debug` (475), `web-pentest` (382), `dave` (275), `dependabot-validator` (267), `subagent-driven-development` (263), `datasecurer` (255), `commit-documentor` (251), `coding-style`/`adversarial-ux-test` (232). The oversized ones are mostly lookup-style content that belongs in `references/` — the split is high-value, not cosmetic. Separately: the frontmatter `description`s are already good (the CLI's `--list` output reads well); the routing surface is *not* the problem — don't spend effort rewriting descriptions, spend it on bodies.

### Question and artifact budgets

- Ask only for missing information that changes the result. Existing user answers and approved artifacts are inputs, not an excuse to repeat an interview.
- Preserve the deliberate interview in pr-grill-me and explicit permission gates for deployment, publication, destructive operations, or security assessment.
- Assessment-only requests should produce a plan/report, not automatically start servers or launch several agents.
- Keep small tasks in the main session; use delegation only when requested or allowed and worthwhile.
- Prefer one primary document with sections. Split files only for independent consumption, size, sensitivity, or user preference.
- Retain existing output paths initially. Add an explicit run/output directory or resume/new-run choice before introducing a different global artifact convention.

### Documentation ownership

- README: a brief human catalog and install instructions. Derive names/counts from actual entries if maintaining counts at all.
- STRUCTURE: authoring and portability rules, including a single contributor verification command.
- SKILL frontmatter/body: activation and execution.
- Optional references/examples: non-obvious cases, not copies of the workflow.
- Remove mandatory per-skill USE_CASES requirements; fold useful examples into references and migrate useful chooser information into README.
- Retire completed implementation plans after preserving durable decisions in the appropriate references. This cleanup plan should also be retired once its decisions are implemented, rather than becoming a second operating manual.
- Preserve upstream notices with each affected distributable skill, so attribution survives selective installation and deletion of the Pi umbrella document.

## 6. Recommended additions, in priority order

### Add now: maintenance and reliability, not more orchestration

| Addition | Minimum useful scope | Value |
|---|---|---|
| Repository validator | Use the existing Agent Skills reference validator where suitable, then add local checks for duplicate names, bundled links/assets, and stale removed paths. Expose one command and run it in CI. | Catches catalog/package drift before release. |
| Installed-bundle smoke tests | Selected install, copy and symlink modes, unrelated working directory, paths with spaces, missing sibling dependency, and read-only skill source. | Tests the artifact users actually execute. |
| Trigger evaluation cases | Small reviewed prompt set with expected skill or expected abstention; track multiple unwanted activations and unnecessary handoffs. | Measures duplication at the routing boundary rather than by word count alone. |
| Lightweight capability preflight | Check required executables, browser/API availability, writable output, and optional dependencies without installing or connecting to unrelated services. | Makes partial installs and constrained harnesses fail clearly. |
| Targeted helper tests | Browser lifecycle/snapshot/axe; mocked Codex and Ollama responses; docs draft/publish isolation; deployment parser and process failure. | Protects the highest-impact executable behavior. |
| Run ownership and evidence status | Explicit output/run ID, no silent truncation, cleanup of only owned resources, and tested/not-tested/blocked reporting. | Prevents data loss and false claims of coverage. |

Preflight is a small command/section for skills that need it, not another user-facing skill or a new configuration service. Likewise, trigger evaluations should start as fixtures and manual checks, not an LLM-evaluation platform.

> **Review (Devin):** Endorse the six additions — this is the right "add" list and correctly excludes new orchestration. Expansions:
>
> - **Make preflight one shared convention, not N bespoke checks:** a repo `scripts/preflight.sh` pattern where each skill drops a `preflight.sh`/`checks` fragment keeps the mechanism identical across skills and gives CI a single entry point. Still small — one loop over fragments.
> - **Tag releases.** `skills add` installs from git HEAD with no pinning surface for users. `git tag vX.Y` per cleanup phase gives users a correlate-able revision and gives rollback a target beyond "the previous commit."
> - **Add `AGENTS.md` for this repo itself** (or make STRUCTURE.md serve explicitly): how to add a skill, run the validator, update the catalog. This repo will be maintained substantially *by agents* — the contributor rules should be agent-legible, and the pi-README authoring guidance folds in naturally here.
> - **Validator scope:** include the attribution-per-bundle check (packaging rule 10 above) and the `--list` snapshot test (F9 note) — both cheap, both catch classes of bug that already happened.
> - **`code-review` entry point: default-yes in Phase 5**, not "if used often enough." The gap (reviewing someone else's diff without an interview or dependency framing) is real and the Critic contract already exists to consume. Only defer if extraction reveals the contract is coupled to mission machinery — in which case document "invoke dave's critic" as the interim path rather than duplicating it.
> - One addition the plan doesn't mention: a **`--selftest`/validate convention already half-exists** (install-pi.sh, parse_deploy_output.py). Formalize it: any script with logic ships `--selftest`, CI runs all of them. It's the cheapest coverage win in the repo.

### Extend existing tools where capability is genuinely missing

- **Browser QA:** first evaluate whether a maintained browser CLI or native browser tool already meets the needs. If retaining this driver, add only capabilities demanded by the workflows: supported text snapshots, viewport control for responsive/reflow checks, reliable lifecycle/cleanup, and stale element-reference detection. Do not maintain two browser backends without a concrete compatibility need.
- **PR/dependency review:** establish the real base/head and merge-base instead of assuming current HEAD is the PR base. `pr-grill-me` currently uses `git diff HEAD..pr-N`, which can omit the PR entirely when already on its head or include unrelated changes from another branch. Add reproducible before/after dependency tests and an explicit “inconclusive” result when prerequisites cannot run.
- **D.A.V.E.:** expose a lightweight execution path that accepts an existing plan without requiring Redmine/boards/project registration. Reuse existing mission/state mechanisms when persistence is useful; do not introduce another ledger. Keep remote synchronization optional and subject to the resolved no-push policy.
- **Memory:** detect missing setup cleanly and reuse the chosen memory system. Do not mirror D.A.V.E.'s priorities, project facts, and logs into another store.
- **Security assessment:** test existing authorization and scope enforcement with mocked/loopback targets, including rejection cases. A browser navigation alone is not proof that redirects/subrequests remained in scope. Preserve or tighten safeguards; do not add exploitation features as part of this work.

### Optional later: one general review entry point

There is a real gap between the author interview (`pr-grill-me`) and dependency-specific validation: **ordinary review of someone else's diff or of a local change**.

If this is a frequent need, expose D.A.V.E.'s existing Critic method as a small `code-review` skill. Move the canonical review method into that package and make D.A.V.E. consume it; do not copy the entire critic workflow. Keep the dependency explicit, or defer extraction if independent installation becomes more trouble than the entry point is worth.

No additional ideation, planning, orchestration, generic Flask scaffolding, or harness-specific QA skills are recommended now. Fill the spec/milestone gap inside constructor instead of adding a new planning skill.

## 7. Implementation sequence and acceptance criteria

Each phase is independently reviewable. Do not mix catalog relocation, state schema changes, and behavior changes in one large commit.

### Phase 1 — establish the baseline and fix known correctness gaps

**Priority:** P0. **Relative size:** medium. **Risk:** low-to-medium.

- Record the actual installer package/version and current discoverable names.
- Add installed-bundle and browser regression tests before changing the affected implementations.
- Fix D.A.V.E. role resolution and the missing test fixture helper; make unexpected setup failures fail the test run.
- Fix browser snapshot compatibility and accessibility setup assumptions.
- Resolve no-push behavior and protect pre-existing docs/output files. Add regressions for broad cleanup and unrelated staged changes.

**Exit criteria:** installed D.A.V.E. can pack a mission without plugin-parent files or a manual path override; browser snapshot works against the lockfile; an intentionally broken fixture fails; approval/cleanup tests preserve unrelated data. No claim that a complete skill is portable until its required path has been exercised.

> **Review (Devin):** Phase 1 contains several *independent* fixes that don't depend on any layout decision — the `$(today)` bug, the Playwright pin/`ariaSnapshot` swap, dogfood's truncation guard, scoping/removing `doc-repo.sh revert`, and the no-push auto-invocation. These are pure bugfixes; ship them as small separate commits now rather than batching them behind the whole phase. Only the D.A.V.E. role-bundling fix is entangled with the layout question — and under the flat-root alternative it gets *simpler* (roles move within `dave/skills/dave/`, no relocation).

### Phase 2 — unify distribution without changing public skill identities

**Priority:** P1. **Relative size:** medium. **Risk:** medium, primarily installation compatibility.

- Move standalone skills into `skills/<name>/`, including the portable D.A.V.E. bundle.
- Move `rest-graphql-debug`, `web-pentest`, and `cloudflare-temporary-deploy` out of `pi-skills/`.
- Temporarily keep the two planned-to-merge skills as single canonical entries until Phase 3, rather than removing capability mid-migration.
- Bundle role contracts, necessary references, and attribution.
- Update the primary install documentation and existing plugin wrappers/manifests.
- Reduce Pi integration to optional host setup after the universal install works.

**Exit criteria:** CLI discovery returns the expected unique names; selected installs pass preflight/asset checks in copy and symlink mode; no required reference assumes a source checkout; optional integrations have a separate verified setup path. D.A.V.E.'s existing `~/.dave` state is unchanged.

> **Review (Devin):** Under the flat-root alternative (§4 note) this phase shrinks to: `git mv pi-skills/<name> <name>` for the three movers + temporarily-kept two, bundle D.A.V.E. roles in place, update docs/manifests. The `dave/skills/dave` move and the 12 root moves disappear entirely. Either way, add a concrete gate: snapshot `npx skills add thesawdawg/agent-skills --list` output before and after — expected post-flatten set is 20 names (16 current + 4 of the 5 pi-skills, with sdd's disposition decided), then 17 after Phase 3 merges. That snapshot is the cheapest possible proof the distribution fix worked.

### Phase 3 — merge duplicated workflows and simplify roles

**Priority:** P1. **Relative size:** medium. **Risk:** medium, mainly routing regressions.

- Merge persona UX into dogfood and staged execution into D.A.V.E.'s optional execution reference.
- Merge coding-style into workflow-rules references, preserving user preferences.
- Simplify the roster and retain compatibility aliases for stored role names.
- Move spec/milestone ownership from app-design to constructor.
- Move Flask guidance to its confirmed owning project; leave it available if that destination is not yet known.
- Introduce proportionate questions, artifacts, and review stages.

**Exit criteria:** representative old prompts still reach the intended capability; a small task does not activate multiple orchestration workflows; self-review is not reported as independent review; existing mission histories still resolve their roles. The user explicitly approves removal of superseded installed entries.

### Phase 4 — collapse documentation and add ongoing checks

**Priority:** P1. **Relative size:** small-to-medium. **Risk:** low.

- Consolidate the root/Pi choosers and remove mandatory per-skill USE_CASES paperwork.
- Remove harness branding from portable workflow bodies; keep short capability-specific notes.
- Correct counts, runtime prerequisites, licensing statements, and completed-plan drift.
- Add one verification command and CI; keep dependency/tool versions controlled rather than `@latest`.

**Exit criteria:** every operational fact has a clear owner; no active link points to retired `pi-skills/` paths; useful upstream notices remain bundled; validation and selected-install tests run reproducibly.

### Phase 5 — add only capabilities justified by actual usage

**Priority:** P2. **Relative size:** small individually. **Risk:** low-to-medium.

- Improve browser capabilities only where retained workflows require them.
- Add the small general review entry point if used often enough.
- Extend dependency review to non-Dependabot updates without introducing another validator skill.

**Exit criteria:** each addition replaces repeated manual work or closes a demonstrated gap, has focused tests, and does not duplicate an existing owner.

### Migration and rollback safeguards

- Keep a reviewed old-name/path → new owner mapping in the migration change.
- Do not leave old and new directories both discoverable as full copies of the same skill.
- Do not assume updates uninstall entries that were merged or renamed. Show the user which installed entries need removal/reinstallation, using the verified installer commands; get approval before removal.
- Source moves keep frontmatter names stable. Retired names can be documented temporarily without retaining duplicate full workflows.
- Do not mass-edit user configuration, replace hand-edited rules, or rewrite D.A.V.E. history. If a state migration becomes necessary later, make it a separate backed-up, tested change.
- Preserve a known-good revision and compare install discovery/bundle behavior before and after each phase. Revert the relevant source change rather than deleting user state to recover.

## 8. Verification performed for this assessment

| Check | Result |
|---|---|
| Repository state before and after exploration | Clean; no existing files changed. |
| D.A.V.E. mission tests: `bash dave/skills/dave/scripts/test/run.sh mission` | 46 passed, 0 failed reported, **with an unexpected `today: command not found` fixture error**. Not considered a clean validation result. |
| Pi installer: `bash dave/scripts/install-pi.sh --selftest` | Passed in a temporary installation, including idempotence. Does not prove installed mission briefing works. |
| Deployment parser: `python3 pi-skills/cloudflare-temporary-deploy/scripts/parse_deploy_output.py --selftest` | Passed. No deployment performed. |
| Browser syntax: `node --check dogfood/scripts/browser-driver.mjs` | Passed; this does not validate Playwright API compatibility. |
| Packaging/dependency review | Inspected local skill paths, role lookup code, installer transforms, browser driver, and lockfile; checked upstream specification/CLI/API documentation. |

Not performed: full D.A.V.E. suite, installation into the user's actual skill directories, browser launch/runtime QA, Codex/Ollama calls, external issue writes, security scans, public deployments, or git publication. The full D.A.V.E. suite contains Git configuration/push exercises; the selected mission tests avoid those operations. No subagents were used.

> **Review (Devin):** Additional verification performed for this review: `npx skills add thesawdawg/agent-skills --list` (skills@1.6.0) — **16 skills discovered: 15 root + `dave` via `dave/skills/dave/`; zero of five `pi-skills/*`**. `npm view skill` / `npm view skills` — confirmed they are different packages (see §1 note). Upstream confirmation of `page.accessibility` removal and the `locator.ariaSnapshot()` replacement. `run.sh:576` `$(today)` call site, `doc-repo.sh` revert/clean lines, `common.sh` `PLUGIN_ROOT` derivation, `mission.sh` agent lookup, `pr-grill-me` `git diff HEAD..pr-N`, and dogfood's `: > issues.jsonl` all inspected directly — each cited claim reproduces.

This is a structural and targeted correctness assessment, not a complete security audit or certification of every helper script.

## Sources

Repository evidence is linked throughout. External documentation was checked on the assessment date:

- [Agent Skills specification](https://agentskills.io/specification): package structure, required frontmatter, compatibility metadata, progressive disclosure, reference validation.
- [Vercel skills CLI](https://github.com/vercel-labs/skills): documented `skills add` interface, selective installation, copy/symlink modes, discovery, and host-specific features.
- [Playwright release notes](https://playwright.dev/docs/release-notes): removal of `page.accessibility` in version 1.57.

**Bottom line:** unify distribution, make installed bundles trustworthy, and reduce duplicate process before broadening the catalog. Preserve domain-specific evidence and safeguards; remove the bureaucracy around them.

## Execution log — 2026-09-16

- User approved Devin's flat-root revision: keep root skills and
  `dave/skills/dave`; flatten the five Pi entries before merging three entries.
- Baseline: locally cached `skills@1.6.0`, `skills add . --list` discovers
  16 names, matching Devin's remote-source result. Test local source because
  unpublished cleanup cannot be validated by querying remote HEAD.
- Preserve `app-design` and `dependabot-validator` public names; narrow/extend
  descriptions rather than introduce additional installed-name migrations.
- Keep Flask guidance here pending an identified owning project. No installed
  entries, personal rules, or D.A.V.E. state will be removed or migrated.
- Retain this plan as the requested execution/change record; retire the already
  completed D.A.V.E. implementation plan after preserving durable guidance.
- D.A.V.E. isolated-copy regression reproduced missing `/tmp/agents/critic.md`.
- Git metadata is read-only in the workspace; authorized commits use the
  escalation mechanism. No push will be performed.

- Phase 1: bundled nine role contracts and thin plugin wrappers; isolated copy
  and symlink mission-pack checks pass; 46 mission assertions pass without the
  missing `today` fixture error. Test runner captures unexpected ERR events,
  including subshell failures, and fails the suite.
- Docs regression failed before repair by committing an unrelated untracked
  document. Both local/repo modes now pass approved-file isolation tests and
  retain unrelated staged files. Broad revert refuses execution; publication
  helper creates local commits only. Dogfood refuses existing findings files.

- Browser decision: retain the existing shared driver for the shell-only + axe
  contract; allow capable native tools without adding a second bundled backend.
  Reviewed maintained alternatives: https://github.com/microsoft/playwright-mcp
  and https://github.com/vercel-labs/agent-browser. Snapshot uses documented
  `locator.ariaSnapshot()` (https://playwright.dev/docs/api/class-locator#locator-aria-snapshot).
- Browser regression reproduced the removed snapshot API under Playwright 1.61.1.
  Runtime packages and matching Chromium were installed only under `/tmp`;
  Chromium requires execution outside this workspace's process sandbox.
- Browser setup now prepares a lockfile-keyed writable cache. Driver gains
  viewport control, exclusive launch ownership, graceful signal cleanup, and
  invalidated element references after actions/navigation.
- PR interview now resolves verified base/head OIDs and merge-base; it neither
  compares against arbitrary HEAD nor deletes a potentially user-owned branch.

### Phase 2 distribution

- Flattened all five Pi skill directories without changing their frontmatter names.
  D.A.V.E. stays at `dave/skills/dave`. Bundled MIT notices preserve upstream
  attribution in selected installs, including individual credits and GSD references.
- Expected intermediate discovery is **21**, not the review's 20: 16 baseline
  plus all five moved entries. Final is 19 with three merges, retained Flask,
  and the new review entry point. Counts are derived from the actual catalog.
