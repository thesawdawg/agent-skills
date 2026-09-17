---
name: code-review
description: Review a local diff, pull request, or implementation plan for concrete bugs, regressions, and missing cases. Use for ordinary review without the author interview of pr-grill-me or the dependency-specific workflow of dependabot-validator.
---

# Code review

Review read-only; do not implement fixes unless separately requested. Read
[the canonical review method](references/method.md).

1. Establish the requested scope, repository rules, and intended behavior.
2. For a PR, resolve the actual base/head OIDs and compare their merge-base;
   never assume the current checkout is its base. For local changes, include
   staged and unstaged diffs and relevant untracked files. State exact inputs.
3. Trace changed behavior through callers and data contracts. Verify concrete
   failure paths with focused read-only checks or isolated tests where useful.
4. Report prioritized findings with path/line, trigger, actual vs expected
   behavior, consequence, and evidence. Mark unverified hypotheses explicitly.
5. State checked-clean areas and what could not be checked. No findings is a
   valid result; do not invent style complaints or claim independent review
   when this is self-review.

No mandatory interview, second reviewer, mission, or D.A.V.E. installation is
required. D.A.V.E.'s Critic consumes this method when that role is requested.
