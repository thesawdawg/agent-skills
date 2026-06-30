---
name: dependabot-validator
description: Validate a Dependabot PR's package updates against the current project to find compatibility issues before merging. Use when the user wants to check whether a Dependabot pull request is safe to merge, or when they want to understand the impact of a dependency upgrade.
---

# Dependabot Validator Skill

Analyzes a Dependabot PR's dependency changes against the current project to surface breaking changes, deprecated APIs, and compatibility issues before merging.

## Workflow

Work through these steps in order, tracking each as a task.

### 1. Identify the PR and Fetch Dependency Changes

If the user provided a PR number or URL, use `mcp__github__pull_request_read` to fetch it. Otherwise ask the user for the PR number.

Extract the list of updated packages from the PR:
- Read the PR title and body — Dependabot always lists the package name and version range (e.g. `Bump lodash from 4.17.20 to 4.17.21`)
- Use `mcp__github__get_file_contents` to read the diff of the lockfile or manifest (e.g. `package.json`, `package-lock.json`, `requirements.txt`, `Pipfile.lock`, `Cargo.toml`, `go.mod`, `pom.xml`, `build.gradle`, `Gemfile.lock`) from the PR branch vs the base branch

Build a list of:
```
{ package, ecosystem, from_version, to_version }
```

### 2. Detect the Project Ecosystem

Identify the package ecosystem from files present in the repo root. Check for:
- `package.json` → npm/Node.js
- `requirements.txt` / `pyproject.toml` / `Pipfile` → Python/pip
- `Cargo.toml` → Rust/cargo
- `go.mod` → Go modules
- `pom.xml` / `build.gradle` → Java/Maven/Gradle
- `Gemfile` → Ruby/Bundler
- `composer.json` → PHP/Composer

### 3. Scan the Codebase for Usage

For each updated package, find how the project actually uses it:

**npm/Node.js:**
```bash
grep -r "require(['\"]<pkg>" --include="*.js" --include="*.ts" --include="*.mjs" -l .
grep -r "from ['\"]<pkg>" --include="*.js" --include="*.ts" --include="*.mjs" -l .
```

**Python:**
```bash
grep -r "import <pkg>\|from <pkg>" --include="*.py" -l .
```

**Rust:**
```bash
grep -r "use <pkg>::\|extern crate <pkg>" --include="*.rs" -l .
```

**Go:**
```bash
grep -r '"<module-path>"' --include="*.go" -l .
```

Collect the specific symbols, functions, and APIs imported or called from each package.

### 4. Research Breaking Changes

For each updated package, use `WebSearch` to find the changelog or release notes between the old and new version. Search for:
- `"<package> <to_version> changelog"`
- `"<package> breaking changes <from_version> to <to_version>"`
- The package's GitHub releases page or official docs

Focus on:
- **Breaking API changes** — removed or renamed exports, changed function signatures
- **Deprecated features** that the project uses
- **Peer dependency requirement changes** — e.g. now requires Node 18+, Python 3.10+
- **Behavior changes** that could cause silent failures or test failures
- **Security advisories** included in the update (Dependabot often patches CVEs)

### 5. Cross-Reference Usage vs. Changes

Compare what the project imports/uses (Step 3) against what changed (Step 4).

For each package, determine:
- **Safe** — update is patch/minor with no breaking changes affecting project usage
- **Review needed** — update touches APIs the project uses; manual check or code change required
- **Breaking** — update removes or renames something the project calls; code changes mandatory before merging

### 6. Check Test Coverage

Run the project's test suite (or a relevant subset) to detect regressions:

**npm:**
```bash
npm test 2>&1 | tail -50
```

**Python:**
```bash
pytest --tb=short -q 2>&1 | tail -50
```

**Rust:**
```bash
cargo test 2>&1 | tail -50
```

**Go:**
```bash
go test ./... 2>&1 | tail -50
```

**Java (Maven):**
```bash
mvn test -q 2>&1 | tail -50
```

If tests can't run (missing environment, secrets, DB), note this and rely on static analysis.

### 7. Check for Peer / Transitive Dependency Conflicts

Look for version conflicts introduced by the update:

**npm:**
```bash
npm ls 2>&1 | grep -i "UNMET\|invalid\|peer dep" | head -30
```

**Python:**
```bash
pip check 2>&1 | head -30
```

**Rust:**
```bash
cargo check 2>&1 | head -30
```

### 8. Summarize and Report

Produce a clear report for the user with the following sections:

---

## Dependabot PR Validation Report

**PR:** #<number> — <title>
**Base branch:** `<branch>` | **Updated packages:** <count>

### Package Analysis

| Package | From | To | Risk | Notes |
|---------|------|----|------|-------|
| `<pkg>` | `x.y.z` | `a.b.c` | ✅ Safe / ⚠️ Review / ❌ Breaking | <one-line summary> |

### Findings

For each package with risk level ⚠️ or ❌, detail:
- **What changed** in the new version that affects this project
- **Where the project uses it** (file paths, line numbers if found)
- **What action is needed** (no action / update call sites / add adapter / block merge)

### Test Results
- ✅ Tests passed / ⚠️ Tests skipped (reason) / ❌ Tests failed (summary)

### Peer Dependency Conflicts
- ✅ None detected / ⚠️ Conflicts found (list them)

### Recommendation

**MERGE SAFE** — No breaking changes detected. All updates are patch/minor fixes or security patches with no API surface impact on this codebase.

— or —

**REVIEW BEFORE MERGING** — The following packages require attention before this PR can be safely merged: (list packages and required actions)

— or —

**DO NOT MERGE** — Breaking changes detected that will cause failures. Required fixes listed above.

---

## Tips for Common Ecosystems

### npm / Node.js
- Semver major bumps (1.x → 2.x) almost always have breaking changes
- Check `peerDependencies` changes in `package.json` of the updated lib
- Look for renamed exports or CommonJS → ESM transitions

### Python
- Check if the package dropped Python version support
- Watch for `import` path renames (e.g. `from pkg import OldClass` → `from pkg.new import OldClass`)
- Review type annotation changes if the project uses mypy/pyright

### Rust
- Check if public trait implementations changed (method signatures, added required methods)
- Feature flag changes can silently remove functionality

### Go
- Module path changes mean all imports must be updated
- Interface changes break any code that implements or accepts the interface

### Java
- Check for removed annotations or changed annotation parameters
- Spring Boot / Jakarta EE namespace migrations are common breaking points
