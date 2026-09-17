---
name: app-design
description: Audit an existing application or repository, identify verified defects, and prioritize improvements. Supports assessment-only review of web apps, services, libraries, scripts, and skill repositories.
---

# Existing application assessment

Understand the repository and produce evidence-backed findings appropriate to
the requested scope. Keep the public name `app-design` for compatibility.
For new-project scope use ideator; for architecture/specifications/milestones use
constructor. Neither is a prerequisite for assessing existing code.

1. Read repository instructions and supplied context. Determine assessment-only,
   runtime QA, or authorized implementation scope. Reuse the user's stated intent.
2. Map entry points, dependencies, data/state, build/test commands, and ownership.
   Use `rg` and focused reads rather than an exhaustive file dump.
3. State the inferred purpose and material uncertainties. Ask only when an answer
   changes findings or safety; continue independent static checks meanwhile.
4. Verify suspected defects with code paths, existing tests, or focused repros.
   For assessment-only requests, do not automatically install dependencies,
   launch servers, run browsers, or delegate work. Label untested claims.
5. When runtime QA is authorized and relevant, consult
   [the test battery](references/test-battery.md). Web UI exploration may use
   separately installed dogfood. A missing browser does not block static or CLI
   assessment; report the coverage limit.
6. Rank findings by impact, evidence, effort, and dependencies. Distinguish bugs,
   intended behavior, and suggested improvements. Implement only within scope
   already authorized by the user; otherwise present the proposed work.

Default artifact: `app-design-output/recommendations.md`, including the app model,
findings, tested/untested areas, and next steps. Existing `app-model.md` and
runtime reports remain valid inputs; additional documents are optional.

[Question bank](references/question-bank.md): consult only for unresolved intent.
