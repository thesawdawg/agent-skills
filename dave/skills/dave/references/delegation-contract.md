# Delegation contract

Direct execution is the default for small tasks. Delegate only when requested or
permitted and the bounded task benefits from another context. Provider skills
(`codex-delegate`, `ollama-delegate`) own invocation/session mechanics; this
contract owns optional coordination. Text-only Ollama calls cannot edit files.

## Roster

| Role | Purpose | Legacy lookup aliases |
|---|---|---|
| quartermaster | Intake and reconciliation | — |
| cartographer | Structural maps; reuse existing dossiers | — |
| scout | Focused research, optionally dependency selection | module-finder |
| options | Compare problem framings or solution approaches | brainstormer, ideator |
| implementer | Implement the agreed plan | constructor |
| critic | Evidence-backed, read-only review | — |
| scribe | Draft work summaries and outward updates | — |

Canonical contracts are in `roles/<name>.md` beside this file. Legacy identifiers
resolve only at lookup; stored assignments are never rewritten. Honor disabled
roles and model choices in user config, including legacy entries. If old and new
settings conflict, ask which should apply. Model mappings are host configuration;
do not assume any particular provider/model is available.

## Brief and verify

Every delegated task includes objective, checkable acceptance criteria, scope and
constraints, undiscoverable context, and the role's return format. The worker
must read its canonical role contract in addition to the brief.

Use a fresh context for independent tasks; reuse the same worker for follow-up.
One review covers specification and quality by default. Separate reviewers need
a concrete risk justification. Without actual delegation, label the result
self-review. Never present a main-session focused pass as independent evidence.

For persistent work, reuse `mission new`, `mission pack --agent <role>`,
`mission assign`, and `mission record`. A pack flags incomplete briefs and adds
prior verdicts; fill missing requirements before dispatch. Existing dossiers can
supply repository context without repeated exploration.

Grade against acceptance criteria: `trust`, `partial`, `rerun`, or `discard`.
Record gaps and evidence. A failed grade calls for a corrected brief or appropriate
worker, not automatically a more expensive model. Respect user model preferences.
Parallelize only independent work when delegation is authorized. Continue already
approved stages without manufacturing a user gate at every handoff.

External messages and changes to priorities still require their explicit approval.
No role may push git changes. For an existing plan without priority setup, read
[execution](execution.md).
