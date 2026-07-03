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

Fetch the PR branch into a local temp branch. **Replace `<PR_NUMBER>` with the actual number everywhere it appears** (e.g. for PR 42: `pull/42/head:pr-42`):
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

For each package: find the source repo, confirm both versions exist, then read the release notes **strictly between `from_version` and `to_version`**. Extract fields with a small Python filter — do **not** `head` a raw registry document (it's large, field order isn't a contract, and you'll cut off exactly what you need).

**Step 4a — npm: get the repo/homepage and confirm both versions exist.**
```bash
curl -sSL "https://registry.npmjs.org/<pkg>" | python3 -c '
import sys, json, re
d = json.load(sys.stdin)
repo = re.sub(r"^git\+|\.git$", "", (d.get("repository") or {}).get("url") or "")
print("repo:", repo or "(none)")
print("homepage:", d.get("homepage") or "(none)")
vs = d.get("versions", {})
for v in ("<from_version>", "<to_version>"):
    print(v + ":", "present" if v in vs else "MISSING from registry")
'
```

**Step 4a — PyPI (Python):** repo/homepage and project URLs.
```bash
curl -sSL "https://pypi.org/pypi/<pkg>/json" | python3 -c '
import sys, json
d = json.load(sys.stdin)["info"]
print("homepage:", d.get("home_page") or "(none)")
print("project_urls:", d.get("project_urls") or {})
'
```

**Step 4b — GitHub releases within the version range.** Once you have `<owner>/<repo>` from 4a, print only releases whose tag is in `(from_version, to_version]`, with full bodies (not truncated to a fixed length):
```bash
curl -sSL "https://api.github.com/repos/<owner>/<repo>/releases?per_page=100" | python3 -c '
import sys, json, re
frm, to = "<from_version>", "<to_version>"
def key(t): return [int(x) for x in re.findall(r"\d+", t.lstrip("vV"))[:3]] or [0]
data = json.load(sys.stdin)
if isinstance(data, dict):                       # error object (rate-limited / not found)
    print("release lookup FAILED:", data.get("message")); sys.exit()
lo, hi = key(frm), key(to)
hits = sorted((r for r in data if lo < key(r["tag_name"]) <= hi), key=lambda r: key(r["tag_name"]))
for r in hits:
    print("###", r["tag_name"]); print((r["body"] or "").strip()); print()
if not hits:
    print("NO releases found in range", frm, "->", to, "— try tags or CHANGELOG (Step 4c).")
'
```

**Step 4c — fallback if the project keeps a CHANGELOG instead of GitHub Releases:**
```bash
curl -sSL "https://raw.githubusercontent.com/<owner>/<repo>/HEAD/CHANGELOG.md" | sed -n '1,200p'
```
Read the entries between the two versions.

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

### 6. Run the test suite against the PR's dependency state (regression check)

⚠️ **Tests must run with the *updated* dependencies, not your current checkout.** Running `npm test` in the current working tree tests your *existing* deps and can produce a false MERGE SAFE without ever exercising the update. Use an isolated **git worktree** checked out to the PR branch, install the updated deps there, and run tests there.

Create the worktree (replace `<PR_NUMBER>`):
```bash
git worktree add ./.dependabot-validator/pr-<PR_NUMBER> pr-<PR_NUMBER>
```

Install the updated deps and run tests **inside** the worktree. Each command uses a subshell `( cd … && … )` so it works even if your harness runs each Bash call in a fresh shell (the `cd` doesn't need to persist):
```bash
( cd ./.dependabot-validator/pr-<PR_NUMBER> && npm ci && npm test ) 2>&1 | tail -60                       # npm
( cd ./.dependabot-validator/pr-<PR_NUMBER> && pip install -r requirements.txt && pytest --tb=short -q ) 2>&1 | tail -60   # Python
( cd ./.dependabot-validator/pr-<PR_NUMBER> && cargo test ) 2>&1 | tail -60                               # Rust
( cd ./.dependabot-validator/pr-<PR_NUMBER> && go test ./... ) 2>&1 | tail -60                            # Go
( cd ./.dependabot-validator/pr-<PR_NUMBER> && mvn test -q ) 2>&1 | tail -60                              # Java (Maven)
```
(For Python, prefer a throwaway venv inside the worktree if the project uses one, so you don't mutate the ambient environment.)

If tests genuinely can't run (missing environment, secrets, database), say so **explicitly** in the report and rely on the static analysis from Steps 3–5 — **do not report MERGE SAFE on the basis of tests you didn't actually run against the update.**

### 7. Check for peer / transitive dependency conflicts

```bash
npm ls 2>&1 | grep -iE "UNMET|invalid|peer dep" | head -30   # npm
pip check 2>&1 | head -30                                    # Python
cargo check 2>&1 | head -30                                  # Rust
```

### 8. Clean up

Remove the worktree from Step 6 **first** (git won't delete a branch that's checked out in a worktree), then the temp branch:
```bash
git worktree remove ./.dependabot-validator/pr-<PR_NUMBER> --force
git branch -D pr-<PR_NUMBER>
```
(If Step 6 was skipped, only the `git branch -D` line is needed.)

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
✅ Passed **against the PR's updated deps (worktree)** / ⚠️ Skipped (reason — tests NOT run against the update) / ❌ Failed (summary). Never mark this ✅ from a run in the current checkout.

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
