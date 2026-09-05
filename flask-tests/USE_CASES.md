# flask-tests: Practical Use Cases

This guide shows **when to invoke `flask-tests`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full framework reference. See also the [top-level skills index](../USE_CASES.md).

**This skill is project-specific.** It describes one Flask project's established two-tier pytest setup — fast SQLite unit tests plus MySQL integration tests, with `importlib` import mode and path-based auto-marking. It is a house-rules reference, not general Flask testing advice, and it is only useful inside a repo that already has that framework.

## Use it when

Use `flask-tests` when writing or running tests in that project, so new tests match the existing framework instead of starting a parallel one.

Good uses:

- Adding tests for a controller, model, worker, or route
- Scaffolding tests for a new module and needing to know where they go
- Deciding whether something belongs in the unit or integration tier
- Working out why a test passes locally and skips in CI, or vice versa
- Being asked "how do I test this here?"

Do not use it in an unrelated project — the layout, fixtures, and commands are specific to this one. Do not use it to design a test framework from scratch; it documents one that already exists. Do not use it for browser-level QA of a running app — that's [`dogfood`](../dogfood/USE_CASES.md).

## User examples

> Add tests for the SOAP classification worker.

> Where do tests for this new module go?

> Should this be a unit test or an integration test?

> How do I run just the fast tests?

## Model selection cues

Select this skill when the user asks to add, scaffold, or run tests inside this Flask project, or asks how something is tested here.

Do not select it for a general "how do I test Flask" question outside this repo, for a test-framework decision in a new project (that's `constructor`), or for QA of a running UI (`dogfood`).

## Inputs the model should establish

Confirm before scaffolding anything new — the skill's own Step 0 is mandatory:

| Input | Why |
|---|---|
| Which tier the test belongs in | Unit (SQLite, fast) vs integration (real MySQL) changes everything about how it's written |
| The source path being covered | Test files mirror the source tree; the path determines the location |
| Whether `TEST_DATABASE_URI` is set | Integration tests auto-skip without it — a "pass" may be a skip |
| That the framework decisions still hold | Ask rather than assume; the skill says to confirm every invocation |

## Example model plan

1. **Confirm the framework decisions** with the user (Step 0 — always, every invocation).
2. **Pick the tier.** Anything needing real MySQL behaviour is integration; everything else is unit and should stay fast.
3. **Mirror the source path** — `unit/lus/pac/test_soap_classification.py` covers `lus/pac/soap_classification.py`. Never add `__init__.py` under `tests/`; import mode is `importlib`.
4. **Never hand-apply `unit`/`integration` markers** — the root conftest applies them from the directory.
5. **Run the fast loop** and report the real result:
   ```bash
   .venv/bin/python -m pytest -m unit
   ```
6. **If integration tests were in scope**, say explicitly whether they ran or skipped. A skip reported as a pass is a false green.

## Expected output

Test files in the mirrored path under `tests/unit/` or `tests/integration/`, using the existing fixtures, plus the exact command run and its actual result — including whether integration tests skipped for a missing `TEST_DATABASE_URI`.

## Example result shape

```
Added tests/unit/lus/pac/test_soap_classification.py — 4 cases covering the
empty-input guard, the multi-match branch, and two real fixtures from the
existing conftest. Unit tier: no DB needed.

$ .venv/bin/python -m pytest -m unit
  ..........................................  42 passed in 3.1s

Integration tier not run — TEST_DATABASE_URI is unset, so those tests would
skip rather than pass. Set it if you want them exercised.
```
