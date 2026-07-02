---
name: dependabot-validator
description: Validate a Dependabot PR's package updates against the current project to find compatibility issues before merging. Use when the user wants to check whether a Dependabot pull request is safe to merge, or when they want to understand the impact of a dependency upgrade.
---

# Dependabot Validator Skill (pi-adapted)

Analyzes a Dependabot PR's dependency changes against the current project to surface breaking changes, deprecated APIs, and compatibility issues before merging.

Uses only the four core tools (**Read, Write, Edit, Bash**) plus `git` and `curl`. No harness-specific web-search or API tool is required — changelog lookups go through package-registry HTTP APIs via `curl`, which are deterministic and need no search engine.

## Prerequisites

This skill fetches the PR branch with **`git` over your existing remote access** — no token or `gh` CLI needed. GitHub exposes every PR branch at `refs/pull/<PR_NUMBER>/head`.

Verify remote access works:
```bash
git ls-remote origin HEAD
```

## Inputs

- **PR number** (required). If the user didn't give one, ask: "What's the Dependabot PR number?"
- The command runs inside the target repo (current directory).

## Workflow

Work through these steps in order. If your harness has a task list, track each step on it.

### 1. Fetch the PR and read what it changes

Fetch the PR branch into a local temp branch:
```bash
git fetch origin pull/<PR_NUMBER>/head:pr-<PR_NUMBER>
```

Read the commit messages — Dependabot always names the package and versions there:
```bash
git log pr-<PR_NUMBER> --not HEAD --pretty=%B
# e.g. "Bump lodash from 4.17.20 to 4.17.21"
# or   "Bump actions/checkout from 3 to 4"
```

Parse every `Bump <package> from <X> to <Y>` line into a working list, one row per package:
```
{ package, ecosystem, from_version, to_version }
```

Diff the manifests and lockfiles between your branch and the PR branch to confirm exactly what changed:
```bash
git diff HEAD..pr-<PR_NUMBER> -- \
  package.json package-lock.json \
  requirements.txt Pipfile.lock \
  Cargo.toml Cargo.lock \
  go.mod go.sum \
  pom.xml build.gradle \
  Gemfile.lock composer.lock
```

**Do not delete the temp branch yet** — later steps compare against it. You'll remove it in Step 8.

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

For each updated package, find where and how the project uses it:

**npm / Node.js:**
```bash
grep -rEl "require\(['\"]<pkg>|from ['\"]<pkg>" --include=*.js --include=*.ts --include=*.mjs .
```

**Python:**
```bash
grep -rEl "import <pkg>|from <pkg>" --include=*.py .
```

**Rust:**
```bash
grep -rEl "use <pkg>::|extern crate <pkg>" --include=*.rs .
```

**Go:**
```bash
grep -rEl '"<module-path>"' --include=*.go .
```

Then open the matching files (Read tool) and note the specific symbols, functions, and APIs the project actually calls from each package. A package that's installed but never imported is low-risk regardless of what changed.

### 4. Research breaking changes (via curl, no search engine needed)

For each updated package, fetch the changelog / release notes for the version range directly from the registry or GitHub. Pick the command for the ecosystem:

**npm** — registry metadata (includes repository URL and versions):
```bash
curl -sSL "https://registry.npmjs.org/<pkg>" | python3 -m json.tool | head -100
```

**PyPI:**
```bash
curl -sSL "https://pypi.org/pypi/<pkg>/json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['info']['home_page'], d['info']['project_urls'])"
```

**GitHub releases** (works for any package whose repo you know — e.g. GitHub Actions like `actions/checkout`):
```bash
curl -sSL "https://api.github.com/repos/<owner>/<repo>/releases" | python3 -c "import sys,json; [print(r['tag_name'], '-', (r['body'] or '')[:500]) for r in json.load(sys.stdin)]" | head -80
```

If none of these resolve a changelog (private package, moved repo), **ask the user for the changelog or release-notes URL** and `curl` that, or note that breaking-change research was inconclusive for that package.

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

### 6. Run the test suite (regression check)

Check out the PR branch's dependency state if practical, then run the project's tests. Pick the ecosystem command:

```bash
npm test 2>&1 | tail -50          # npm
pytest --tb=short -q 2>&1 | tail -50   # Python
cargo test 2>&1 | tail -50        # Rust
go test ./... 2>&1 | tail -50     # Go
mvn test -q 2>&1 | tail -50       # Java (Maven)
```

If tests can't run (missing environment, secrets, database), say so in the report and rely on the static analysis from Steps 3–5.

### 7. Check for peer / transitive dependency conflicts

```bash
npm ls 2>&1 | grep -iE "UNMET|invalid|peer dep" | head -30   # npm
pip check 2>&1 | head -30                                    # Python
cargo check 2>&1 | head -30                                  # Rust
```

### 8. Clean up

Remove the temp branch created in Step 1:
```bash
git branch -D pr-<PR_NUMBER>
```

### 9. Write the report

Produce this report for the user:

---

## Dependabot PR Validation Report

**PR:** #<number> — <title>
**Base branch:** `<branch>` | **Updated packages:** <count>

### Package Analysis

| Package | From | To | Risk | Notes |
|---------|------|----|------|-------|
| `<pkg>` | `x.y.z` | `a.b.c` | ✅ Safe / ⚠️ Review / ❌ Breaking | <one-line summary> |

### Findings

For each ⚠️ or ❌ package:
- **What changed** in the new version that affects this project
- **Where the project uses it** (file paths, line numbers if found)
- **What action is needed** (no action / update call sites / add adapter / block merge)

### Test Results
✅ Passed / ⚠️ Skipped (reason) / ❌ Failed (summary)

### Peer Dependency Conflicts
✅ None detected / ⚠️ Conflicts found (list them)

### Recommendation

**MERGE SAFE** — No breaking changes detected. All updates are patch/minor fixes or security patches with no API-surface impact on this codebase.

— or —

**REVIEW BEFORE MERGING** — These packages need attention first: (list packages + required actions)

— or —

**DO NOT MERGE** — Breaking changes detected that will cause failures. Required fixes listed above.

---

## Tips for Common Ecosystems

### npm / Node.js
- Semver major bumps (1.x → 2.x) almost always have breaking changes.
- Check `peerDependencies` changes in the updated lib's `package.json`.
- Watch for renamed exports or CommonJS → ESM transitions.

### Python
- Check if the package dropped a Python version.
- Watch for import-path renames (`from pkg import OldClass` → `from pkg.new import OldClass`).
- Review type-annotation changes if the project uses mypy/pyright.

### Rust
- Check whether public trait implementations changed (method signatures, added required methods).
- Feature-flag changes can silently remove functionality.

### Go
- Module-path changes mean all imports must be updated.
- Interface changes break any code that implements or accepts the interface.

### Java
- Check for removed annotations or changed annotation parameters.
- Spring Boot / Jakarta EE namespace migrations are common breaking points.
