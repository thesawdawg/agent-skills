# commit-documentor: Practical Use Cases

This guide shows **when to invoke `commit-documentor`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full workflow and [references/rules.md](references/rules.md) for the applicability logic. The defining mechanic of this skill is that the mapping between code and docs is kept in a **committed local index** — so deciding what needs documenting is a local, reviewable operation, and the doc target is only written at publish time. It runs in either of two modes: `repo` (docs in a separate repository, published as a PR) or `local` (no separate docs repo — the skill creates and maintains a `docs/` tree in this repo and commits it, never pushing). See also the [top-level skills index](../USE_CASES.md).

## Use it when

Use `commit-documentor` right after committing, when the project's user-facing documentation lives in its own repo and could now be out of date.

Good uses include:

- A feature branch is finished and unpushed; you want its docs written before the PR
- A config key or CLI flag changed and you're not sure which pages mention it
- Onboarding a project to the workflow: build the initial doc index and set the rules
- A project with no docs at all: local mode creates and then maintains a `docs/` tree in-repo
- A periodic sweep: "are the last five commits reflected in the docs?"

Do not use it to review code quality (use `/code-review`), or to document a PR you haven't committed yet — this skill reads commits, not the working tree.

## User examples

> /commit-documentor

> Run commit-documentor — and skip anything under `internal/`.

> I just committed the new export endpoint. Check whether the docs repo needs updating.

> Sync my last three commits to the docs repo, but don't document the dependency bump.

> Set up commit-documentor for this project — docs live at git@github.com:me/docs.git.

> We don't have a docs repo — just keep docs in this repo and update them as I commit.

## Model selection cues

Select this skill when the user:

- Names the skill, or asks whether recent commits need documentation
- Refers to a separate docs repo / docs site that should track this project
- Asks to sync, update, or check documentation for commits they just made

Do not select it when:

- The user just wants a one-off README edit with no commit-driven review
- The user wants the commits themselves reviewed for bugs — that's `/code-review`
- Nothing has been committed yet — ask them to commit first, since the skill's unit of work is a commit

## Inputs the model should establish

- **`.agents/commit-documentor.json`** — mode, doc location, and rules. If missing, run first-run setup: one grouped question covering where docs live (separate repo, or **local mode** if they have none) plus the rules, then write the file once. Never guess a documentation location.
- **The doc index** at the config's `doc_index` path. If missing or stale, run the initial scan first and show it to the user before committing it.
- **Rules** — what never warrants a doc update (chore commits, dependency bumps) and what always does. Persist these in the config.
- **Commit range** — defaults to `@{u}..HEAD` (unpushed commits), falling back to `HEAD~1..HEAD`. Use an explicit range if the user gave one.
- **Any run-specific instruction** — it overrides the config for this run only.

## Example model plan

1. `scripts/doc-repo.sh config` — confirm the doc target is configured; if it exits 3, run first-run setup before reading a single commit.
2. `scripts/doc-repo.sh sync` — fast-forward the doc repo clone (a no-op in local mode); compare its SHA against the index header, rescanning if drifted.
3. Resolve the commit range (`@{u}..HEAD`), list the commits, read each diff with `git show`.
4. Classify every commit — needs docs / excluded by rule / no user-visible change — per [references/rules.md](references/rules.md).
5. For the "needs docs" set, look up target pages in the index, confirm with `scripts/doc-repo.sh search`, and read those pages in full.
6. Edit the pages in the doc repo clone; show `scripts/doc-repo.sh diff` plus a per-file rationale and the excluded-commit list, and ask for approval.
7. On approval: `scripts/doc-repo.sh publish docs/auto/<slug> <msg-file> <body-file>` — a docs-repo PR in `repo` mode, a docs-only commit on the current branch in `local` mode — then refresh the index header.
8. On decline: `scripts/doc-repo.sh revert`, take the correction, regenerate from step 5.

## Sample output

```
Range: @{u}..HEAD — 4 commits

  a1b2c3d  feat(api): add /v1/exports endpoint          → needs docs
  e4f5a6b  fix(cli): --format now defaults to json      → needs docs
  9c8d7e6  chore(deps): bump fastapi 0.110 → 0.111      → excluded (exclude_commit_types: chore)
  3f2e1d0  refactor: extract ExportSerializer           → no user-visible change

Doc targets (from .agents/commit-documentor/doc-index.md):
  docs/reference/api.md   ← a1b2c3d   (index: src/api/** → api.md, high confidence)
  docs/reference/cli.md   ← e4f5a6b   (index: src/cli/** → cli.md, medium confidence)

Proposed diff (2 files, +34 −6):
  docs/reference/api.md  +28 −2   new "Exports" section: POST /v1/exports, 202 response, polling
  docs/reference/cli.md   +6 −4   --format default changed from `table` to `json`

Not documented: 9c8d7e6 (chore rule), 3f2e1d0 (internal only).

Approve, or tell me what to change?
```

On approval:

```
Published: https://github.com/me/docs/pull/212
Branch docs/auto/exports-endpoint → main
Doc index SHA refreshed (7ab19c2); .agents/commit-documentor/doc-index.md now has an uncommitted change in this repo.
```

In `local` mode the last block reads instead:

```
Committed on feature/exports — docs/reference/api.md, docs/reference/cli.md
Not pushed: docs go out with your next push of this branch.
Doc index SHA refreshed; .agents/commit-documentor/doc-index.md has an uncommitted change.
```
