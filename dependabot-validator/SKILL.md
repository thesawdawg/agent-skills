---
name: dependabot-validator
description: Validate dependency updates from Dependabot, Renovate, or manual changes against the current project to find compatibility issues before merging. Use when the user wants to check whether a Dependabot pull request is safe to merge, or when they want to understand the impact of a dependency upgrade.
---

# Dependabot Validator Skill

Analyzes a Dependabot PR's dependency changes against the current project to surface breaking changes, deprecated APIs, and compatibility issues before merging.

Uses only the four core tools (**Read, Write, Edit, Bash**) plus `git` and `curl`. No harness-specific web-search or API tool is required — changelog lookups go through package-registry HTTP APIs via `curl`, which are deterministic and need no search engine.

## Prerequisites

This skill fetches the PR branch with **`git` over your existing remote access** — no token or `gh` CLI needed. GitHub exposes every PR branch at `refs/pull/<PR_NUMBER>/head`.

Verify remote access works:
```bash
git ls-remote origin HEAD
```

## Inputs

- **PR number** (required). If the user didn't give one, ask: "Which PR or base/head refs should I review?"
- The command runs inside the target repo (current directory).

## Workflow

Work through these steps in order. If your harness has a task list, track each step on it.

### 1. Fetch the PR and read what it changes

Resolve actual base/head refs from PR metadata (`gh pr view <N> --json
baseRefName,baseRefOid,headRefOid`) or user-supplied refs for manual updates.
Fetch those refs without overwriting local branches, verify their OIDs match the
metadata, and compute `git merge-base <base-oid> <head-oid>`. Never use the current
checkout as the assumed base. If history is insufficient, report inconclusive.

Read manifests and lockfiles at the merge-base and head. Derive each package's
ecosystem and before/after version from those files; commit messages are hints,
not the source of truth. Record exact OIDs and the comparison list. No bot author
or `Bump ...` message is required.

### 2. Detect the project ecosystem

Identify the ecosystem from files in the repo root:
- `package.json` → npm / Node.js
- `requirements.txt` / `pyproject.toml` / `Pipfile` → Python / pip
- `Cargo.toml` → Rust / cargo
- `go.mod` → Go modules
- `pom.xml` / `build.gradle` → Java / Maven / Gradle
- `Gemfile` → Ruby / Bundler
- `composer.json` → PHP / Composer

### 3. Scan the codebase for how each package is used

**First: the distribution name is not always the import name.** Dependabot bumps the *distribution* (registry) name, but code imports a possibly-different identifier. Examples: Python `beautifulsoup4` imports as `bs4`, `Pillow` as `PIL`; npm `@org/pkg` may be imported by subpath; a package can expose several modules. So treat the **registry package name** and the **source import identifier** as separate values — work out the real import name(s) before scanning (check the package's own docs/registry metadata), and if you can't establish it, report usage detection as *uncertain* rather than concluding "unused."

**Scan tracked source only.** Use `git grep`, which searches only checked-in files — so it never descends into `node_modules/`, `.venv/`, `vendor/`, `dist/`, `build/`, or `.git/` and analyze dependency internals instead of your project. Substitute the **import** identifier for `<import>`:

```bash
git grep -nE "require\(['\"]<import>|from ['\"]<import>" -- '*.js' '*.ts' '*.mjs'   # npm
git grep -nE "import <import>|from <import>" -- '*.py'                              # Python
git grep -nE "use <crate>::|extern crate <crate>" -- '*.rs'                          # Rust
git grep -nE '"<module-path>"' -- '*.go'                                            # Go
```

If the tree isn't a clean git checkout, fall back to grep with explicit exclusions:
```bash
grep -rEl "<pattern>" --include='*.py' --exclude-dir={node_modules,.git,.venv,venv,vendor,dist,build,target} .
```

Then open the matching files (Read tool) and note the specific symbols, functions, and APIs the project actually calls. A package that's installed but never imported is low-risk regardless of what changed.

### 4. Research breaking changes (via curl, no search engine needed)

For each package: find the source repo, confirm both versions exist, then read the release notes **strictly between `from_version` and `to_version`**. Use the recipes in [references/registry-lookups.md](references/registry-lookups.md): npm/PyPI registry metadata for repo/homepage and version existence, GitHub releases filtered to the version range, and a CHANGELOG fallback. Extract fields with a small Python filter — do **not** `head` a raw registry document (it's large, field order isn't a contract, and you'll cut off exactly what you need).

**If you cannot establish the release notes** for a package (private, moved/renamed repo, no tags, API rate-limited): ask the user for the changelog URL and `curl` it, or explicitly mark that package **"breaking-change research inconclusive"** in the report. **Do not default an un-researched package to Safe.**

Focus your reading on:
- **Breaking API changes** — removed/renamed exports, changed function signatures
- **Deprecated features** the project uses
- **Peer/runtime requirement changes** — e.g. now requires Node 18+, Python 3.10+
- **Behavior changes** that could cause silent failures or test breaks
- **Security advisories** patched by the update (Dependabot often fixes CVEs)

### 5. Cross-reference usage vs. changes

For each package, compare what the project uses (Step 3) against what changed (Step 4), and assign a risk level:
- **Safe** — patch/minor with no breaking change touching anything the project uses.
- **Review needed** — the update touches an API the project uses; a manual check or small code change may be required.
- **Breaking** — the update removes or renames something the project calls; code changes are mandatory before merging.

### 6. Compare reproducible baseline and updated tests

Create two detached worktrees in a fresh run directory using the reviewed base
and head OIDs. Never change the user's checkout. Install from each lockfile and
run the same relevant test commands with matching environment versions. Python
runs need separate virtual environments; do not install into the user's environment.
Capture full logs and actual exit codes (use `set -o pipefail` if piping to `tee`).

Compare outcomes: a failure present on both revisions is not automatically caused
by the update. Verify the resolved package versions, not just successful install
commands. If prerequisites, credentials, or tests are unavailable, the result is
**INCONCLUSIVE**, with static findings and the untested behavior named. Do not
claim merge safety from a skipped or unrepresentative test run.

### 7. Check for peer / transitive dependency conflicts

```bash
npm ls 2>&1 | grep -iE "UNMET|invalid|peer dep" | head -30   # npm
pip check 2>&1 | head -30                                    # Python
cargo check 2>&1 | head -30                                  # Rust
```

### 8. Clean up

Remove only the worktrees created by this run, using `git worktree remove` without
`--force`. If generated or modified files prevent removal, report and retain the
worktree for review. No local PR branch needs deletion.


## Report

Produce the validation report using
[references/report-template.md](references/report-template.md). Test results are
marked passed only when run against the PR's updated deps in the worktree —
never from a run in the current checkout. Recommendations are **MERGE SAFE**,
**REVIEW BEFORE MERGING**, or **DO NOT MERGE**.

Ecosystem-specific breaking-change patterns live in
[references/ecosystem-tips.md](references/ecosystem-tips.md).
