# Applicability Rules

How `commit-documentor` decides whether a commit warrants a documentation update.
[SKILL.md](../SKILL.md) is the workflow; this file is the decision logic behind
step 3.

## Precedence

Evaluate in this order and stop at the first match:

1. **Run-time user instruction.** Whatever the user said when invoking the skill
   this run. Overrides everything below, including `always_document_paths`.
2. **`rules.exclude_paths`.** If *every* file in the commit matches an excluded
   glob, the commit is excluded. If only some do, drop those files and keep
   evaluating the rest.
3. **`rules.always_document_paths`.** If any remaining file matches, the commit
   needs docs — even if its type is in `exclude_commit_types`. This is the escape
   hatch for a `chore:`-typed commit that changes real behavior.
4. **`rules.exclude_commit_types`.** Conventional-commit type parsed from the
   subject (`type(scope): subject`). Typical exclusions: `chore`, `build`, `ci`,
   `style`, `test`.
5. **`rules.instructions`.** Free-form prose. Apply as written; where an
   instruction conflicts with an earlier numbered rule, the earlier rule wins, and
   say so in the report rather than silently resolving it.
6. **Default judgment** (below) when no rule matched.

## Default judgment

With no rule matching, a commit needs docs when it changes something a reader of
the docs would otherwise be told incorrectly:

**Needs docs**
- Public API surface: endpoints, request/response shapes, status codes.
- CLI commands, flags, or their defaults.
- Config keys, env vars, or their default values.
- Installation, setup, or upgrade steps.
- User-visible behavior, error messages users act on, or removed features.
- A new capability that has no page at all.

**Does not need docs**
- Internal refactors with identical external behavior.
- Test-only changes, formatting, lint fixes.
- Dependency bumps — *unless* a documented minimum version changes.
- Performance work that changes no documented contract.
- Comments, typos in code.

**The commit message is evidence, not proof.** Classify on the diff. A `chore:`
commit that changes a default is a behavior change; a `feat:` commit that only adds
an internal helper is not documentable.

## Reporting

Always report every commit in the range with its classification and the rule that
produced it, including the excluded ones. The user needs to see what was skipped to
trust what was kept — a silently skipped commit is the failure mode this skill
exists to prevent.

## Glob matching

`exclude_paths` and `always_document_paths` use `**`-style globs relative to the
project repo root. Match with `git diff --name-only <range>` piped through the
patterns; when in doubt about whether a path matches, treat it as *not* matching an
exclusion and *not* matching an always-rule, and fall through to default judgment.
