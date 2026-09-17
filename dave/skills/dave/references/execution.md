# Execute an existing plan

Accept the user's existing plan directly. No Redmine, board, project registration,
priority intake, or personality interview is required. Small tasks execute in the
main session. Persistent missions are optional; if wanted, `dave.sh init` and
`mission new` suffice without registering a project. Reuse existing state.

Break the plan into bounded tasks with explicit acceptance criteria. For each:

1. Read the relevant source and constraints; identify the expected observable change.
2. Implement directly, or delegate when requested/authorized and worthwhile.
3. Verify acceptance and code quality in one review by default. Separate reviewers
   are justified by specific risk, not a fixed ceremony.
4. Record evidence, limitations, and deviations in the supplied plan. Continue
   already authorized work; ask only for material missing decisions.

For independent delegated tasks, use a fresh context with a self-contained brief:
objective, acceptance criteria, allowed files, non-goals, prior decisions, and
required return format. Reuse the worker for follow-up on that same task.
A focused main-session pass is self-review, never independent review.

If using missions, record charges and verdicts with the existing assignment
ledger. Do not introduce another task ledger. Complete only when acceptance
criteria are met or clearly report the concrete blocker and remaining work.
Deployment, external writes, destructive actions, and no-push policy keep their
existing authorization boundaries.
