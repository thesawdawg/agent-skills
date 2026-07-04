# dependabot-validator: Practical Use Cases

This guide shows **when to invoke `dependabot-validator`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full workflow (SSH-based PR fetch, ecosystem detection, usage scan, changelog research, test run, peer-dependency check). This file is examples only. See also the [top-level skills index](../USE_CASES.md).

## Use it when

Use `dependabot-validator` when the user wants to know whether a **Dependabot PR is safe to merge in the context of this specific project** — not a generic "is this library good" question, but whether *this codebase's* actual usage of the updated package(s) is affected.

Good uses include:

- A single-package Dependabot bump (patch, minor, or major)
- A batch of GitHub Actions version bumps in one PR
- A major-version upgrade that might have breaking changes
- Any Dependabot PR the user is hesitant to merge without a compatibility check

Do not use it for a Dependabot PR that's already been reviewed and just needs a general code-quality look — that's `pr-grill-me`. Don't use it for a hand-written dependency bump with no Dependabot commit message to parse (the skill leans on Dependabot's `Bump X from A to B` message format).

## User examples

> Validate Dependabot PR 42 before I merge it.

> Check whether the React 19 upgrade PR breaks anything we use.

> Review the GitHub Actions bumps in PR 118 — are any of them major version jumps?

> Is this lodash patch update actually low-risk, or should I look closer?

## Model selection cues

Select this skill when the user provides or refers to:

- a Dependabot PR number
- "dependency update" / "package bump" / "lockfile update" specifically from Dependabot
- "is this upgrade safe to merge"

Use [`pr-grill-me`](../pr-grill-me/USE_CASES.md) instead for a general PR review that isn't specifically about dependency-update compatibility.

## Inputs the model should establish

Required:

- PR number
- Confirm SSH access works (`git ls-remote origin HEAD`)

Useful:

- Test command for this project, if not obvious from ecosystem detection
- Whether tests can actually run in this environment (missing secrets, no DB, etc.)
- Any known compatibility constraints the user already knows about

## Example model plan

1. `git fetch origin pull/<PR>/head:pr-<PR>`, read the Dependabot commit message(s) to get the package list (`Bump X from A to B`).
2. Diff manifest/lockfiles between `HEAD` and the PR branch to confirm exact version changes.
3. Detect the project's ecosystem (`package.json`, `requirements.txt`, `Cargo.toml`, `go.mod`, etc.).
4. For each updated package, grep the codebase for actual imports/usage and the specific symbols called.
5. `WebSearch` each package's changelog/release notes between old and new version for breaking changes, deprecations, peer-dependency shifts.
6. Cross-reference: does the project's actual usage touch anything that changed? Classify each package Safe / Review needed / Breaking.
7. Run the project's test suite (or note why it couldn't run).
8. Check for peer/transitive dependency conflicts (`npm ls`, `pip check`, etc.).
9. Delete the temporary PR branch.
10. Produce the merge verdict.

## Expected output

The report should contain:

- A package/version/risk table
- For each Review/Breaking package: what changed, where the project uses it, what action is needed
- Test results (or an explicit note that tests couldn't run and why)
- Peer/transitive conflict findings
- A final recommendation: **MERGE SAFE** / **REVIEW BEFORE MERGING** / **DO NOT MERGE**

## Example result shape

```markdown
| Package | From | To | Risk | Notes |
|---|---|---|---|---|
| `example-lib` | 2.4.1 | 3.0.0 | ❌ Breaking | Removed `legacyParse`, used in `src/import.ts:44` |

### Findings
**example-lib** — v3 dropped `legacyParse` in favor of `parse()`. This project
calls `legacyParse` directly in `src/import.ts:44`. Tests in
`import.test.ts` fail against the PR branch.

**Recommendation:** DO NOT MERGE until `src/import.ts` is updated to use
`parse()` and the import tests pass against the PR's dependency versions.
```
