# Test Battery (Phase 3 — Test)

> Referenced from [SKILL.md](../SKILL.md) and [existing-project.md](existing-project.md).

Run against the verified intent in `app-design-output/app-model.md`. A
"discrepancy" is any behavior that differs from that model. Adapt to the app
type — not every step applies. Use the `bash` tool to run commands. **Do not fix
anything during testing** — collect everything first.

## 1. Static & build health

Run each, with `bash`, and note errors/warnings:

- Install dependencies cleanly (`npm ci`, `pip install -r requirements.txt`, …).
- Build / compile. A broken build is a **Critical** finding.
- Run the linter / formatter check.
- Run the type checker (`tsc --noEmit`, `mypy`, …).
- Check for dependency security advisories (`npm audit`, `pip-audit`, …).

## 2. Automated tests

- Run the existing suites: unit, integration, e2e (`npm test`, `pytest`, …).
- Record pass/fail and any flaky tests.
- Compare coverage against the core flows in `app-model.md`. Gaps are findings
  (**Medium**), not bugs.

## 3. Runtime exploratory QA

**Web apps:** run [`/skill:dogfood`](../../dogfood/SKILL.md). Give it the running app's URL and a scope
from the core flows in `app-model.md`. It will navigate, interact, check the
console, screenshot, and write `dogfood-output/report.md`. Pull its findings
into triage.

- Start the app first. For a local app, [dogfood's local-app-setup.md](../../dogfood/references/local-app-setup.md)
  shows the safe pattern: throwaway DB, background server, readiness check,
  route smoke pass, then stop the server.

**APIs / backends:** probe with `curl` — happy path, auth failures, malformed
input, missing fields, boundary values. Check status codes, error shapes, side
effects. Example:

```sh
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/api/health
curl -s -X POST http://127.0.0.1:8000/api/items -d '{}' -H 'content-type: application/json'
```

**CLIs:** run each command with valid args, invalid args, `--help`, empty input,
and edge-case input. Check exit codes and stderr.

**Libraries:** exercise the public API with normal and edge-case inputs; verify
documented behavior matches actual.

## 4. Discrepancy collection

For every issue record (reuse [dogfood's issue taxonomy](../../dogfood/references/issue-taxonomy.md) — severity
Critical/High/Medium/Low; category Functional/Visual/Accessibility/Console/UX/
Content, plus Build/Security/Performance for non-UI):

- What happened
- Where (URL / endpoint / command / file)
- Steps to reproduce
- Expected (per `app-model.md`) vs actual
- Evidence (screenshot path, console/error output, response body)

Carry the full list into Phase 4 (Triage). Finish the sweep before fixing
anything, so triage sees the whole picture.
