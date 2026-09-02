---
name: commit-documentor
description: After committing, check whether the change needs documentation in a separate documentation repository, draft the doc updates for approval, and on approval commit and push them to the doc repo (branch + PR by default). Uses a committed config for DOC_REPO, a committed local doc index to keep queries cheap and in sync, and user-defined rules for what does and does not warrant a doc update. Use when the user runs commit-documentor, or asks to document, sync, or check docs for their recent commits.
---

# Commit Documentor

Reviews the commits the user just made, decides whether they change anything the
documentation repo claims to describe, drafts the doc edits, and — only after the
user approves — publishes them to the doc repo.

See also: [USE_CASES.md](USE_CASES.md) for trigger phrases and a worked example,
[references/rules.md](references/rules.md) for how the applicability rules are
evaluated, and the [top-level skills index](../USE_CASES.md).

**The doc repo is a separate repository from the project.** Every write to it is
outward-facing: never commit or push there without an explicit approval in this
conversation for the specific diff you are about to push.

## Prerequisites

Three things must exist before the workflow runs. Establish them in this order.

### 1. Config (DOC_REPO)

Read via `scripts/doc-repo.sh config`. It looks for, in order:

- `.claude/commit-documentor.json` in the project repo
- `.commit-documentor.json` in the project repo

If neither exists, the script exits 3. **Do not guess a doc repo.** Copy
[templates/config-template.json](templates/config-template.json) to
`.claude/commit-documentor.json`, ask the user for `doc_repo.path` (local clone),
`doc_repo.remote`, `doc_repo.branch`, and `doc_repo.docs_root`, and write it. Then
offer to commit that config to the project repo.

Requires `jq`. `gh` is only needed for the PR step.

### 2. Doc index (initial scan)

The index lives in the project repo at the config's `doc_index` path (default
`.claude/commit-documentor/doc-index.md`) and is **committed** — it is the local,
reviewable map of code area → doc page, and it is what keeps doc-repo querying
cheap and in sync.

If the index is missing, or its recorded doc-repo SHA is behind the current one,
run the scan before anything else:

```bash
scripts/doc-repo.sh sync     # clone or fast-forward the doc repo
scripts/doc-repo.sh list     # every doc file under docs_root
```

Then, for each significant top-level code area in the project (directories under
the source root, the CLI, the API surface, config), search the doc repo for it:

```bash
scripts/doc-repo.sh search "<module name>" "<command name>" "<env var>"
```

Fill in [templates/doc-index-template.md](templates/doc-index-template.md) from the
results, including the two negative sections — undocumented code areas, and doc
pages with no code owner. Both are load-bearing later: the first tells you when to
propose a *new* page, the second tells you what to leave alone. Record the doc
repo's current SHA in the header so drift is detectable next run.

Show the index to the user before committing it — a wrong mapping silently
mis-targets every future run.

### 3. Rules

Rules live under `rules` in the config: `exclude_commit_types`,
`exclude_paths`, `always_document_paths`, and free-form `instructions`. On first
setup, ask the user what should never trigger a doc update (e.g. chore commits and
dependency bumps) and what must always trigger one, and write their answers into
the config rather than carrying them only in conversation. See
[references/rules.md](references/rules.md) for precedence.

Any instruction the user gives when invoking the skill applies to this run only and
**overrides** the config; if it looks durable ("stop documenting CLI flag changes"),
offer to add it to the config.

## Workflow

Track each step as a task.

### 1. Establish the commit range

Default: everything on the branch not yet on origin.

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 \
  && range="@{u}..HEAD" || range="HEAD~1..HEAD"
git log --format='%h %s' $range
git diff --stat $range
```

If the user passed a range or a SHA as an argument, use that instead. If the range
is empty (nothing unpushed), say so and stop — there is nothing to document.

### 2. Review the commits

For each commit, read the actual diff, not just the subject:

```bash
git show --stat <sha>
git show <sha> -- <paths of interest>
```

Fold in whatever extra instruction the user gave when invoking the skill. Judge
each commit on what the diff *does*, not what its message claims — a commit typed
`chore:` that changes a default config value is a behavior change and the message
is wrong.

### 3. Decide applicability

Apply the rules from [references/rules.md](references/rules.md) to each commit and
classify it: **needs docs**, **excluded by rule** (name the rule), or **no
user-visible change**. Then, for the commits that need docs, use the doc index to
find the target pages, and confirm against the live doc repo:

```bash
scripts/doc-repo.sh sync
scripts/doc-repo.sh search "<symbol>" "<flag>" "<endpoint>"
```

Read the target pages in full before editing them. If a needed page does not exist
and the area is listed under "Undocumented areas", propose a new page — but say
plainly that it is new, and where it would sit.

If nothing needs docs, report the classification per commit and stop. That is a
successful run, not a failure.

### 4. Draft the updates

Edit the files in the doc repo clone directly (they are local). Match the
surrounding page's structure, voice, and heading depth — read neighbors before
writing. Keep edits minimal and scoped to what the commits actually changed; do not
opportunistically rewrite unrelated prose.

Present for approval:

```bash
scripts/doc-repo.sh diff
```

Show the user the full diff, plus a short per-file rationale tying each edit to a
specific commit, and the list of commits you excluded and why.

### 5a. Approved → publish

Default `push_mode` is `pr`: branch, push, and open a PR against the doc repo's
default branch.

```bash
scripts/doc-repo.sh publish "<branch_prefix>/<short-slug>" <msg-file> <body-file>
```

Write the commit message to a file first (subject line + body referencing the
source commit SHAs and project repo). Use
[templates/doc-pr-body.md](templates/doc-pr-body.md) for the PR body. If
`push_mode` is `direct`, commit and push to `doc_repo.branch` instead — still only
after approval.

Report the PR URL (or pushed branch) back to the user. Then update the doc index's
recorded SHA and any changed mappings, and mention that the index file in the
project repo now has an uncommitted change.

### 5b. Declined → regenerate

Ask what was wrong, take the added instruction, and redo step 4 against the same
commit set — reset the doc repo working tree first so drafts don't stack:

```bash
git -C "$(scripts/doc-repo.sh path)" checkout -- .
git -C "$(scripts/doc-repo.sh path)" clean -fd
```

Regenerate as many times as the user wants. If the correction is durable, offer to
write it into the config's `rules.instructions`. If the user declines entirely,
leave the doc repo clean and stop — do not push a partial draft.

## Hard rules

- Never push to the doc repo without approval of the specific diff in this session.
- Never edit paths the config or index marks as hand-maintained / no code owner.
- Never invent doc content that the commits do not support — if the code's behavior
  is ambiguous, ask rather than documenting a guess.
- Never rewrite the project repo's own commits; this skill only writes docs and the
  index.
- Leave the doc repo clean on exit: either published, or reverted.
