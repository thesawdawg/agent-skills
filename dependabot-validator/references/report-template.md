# Dependency update validation report

**PR:** #<number> — <title>
**Base branch:** `<branch>` | **Updated packages:** <count>

## Package Analysis

| Package | From | To | Risk | Notes |
|---------|------|----|------|-------|
| `<pkg>` | `x.y.z` | `a.b.c` | Safe / Review / Breaking | <one-line summary> |

## Findings

For each Review or Breaking package:
- **What changed** in the new version that affects this project
- **Where the project uses it** (file paths, line numbers if found)
- **What action is needed** (no action / update call sites / add adapter / block merge)

## Test Results

Passed **against the PR's updated deps (worktree)** / Skipped (reason — tests
NOT run against the update) / Failed (summary). Never mark this passed from a
run in the current checkout.

## Peer Dependency Conflicts

None detected / Conflicts found (list them)

## Recommendation

**MERGE SAFE** — No breaking changes detected. All updates are patch/minor fixes or security patches with no API-surface impact on this codebase.

— or —

**REVIEW BEFORE MERGING** — These packages need attention first: (list packages + required actions)

— or —

**DO NOT MERGE** — Breaking changes detected that will cause failures. Required fixes listed above.
