# dogfood: Practical Use Cases

This guide shows **when to invoke `dogfood`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full five-phase workflow and the `scripts/browser-driver.mjs` command reference. This file is examples only. See also the [top-level skills index](../USE_CASES.md).

## Use it when

Use `dogfood` when the user wants the model to actually **drive a real browser session** against a live web app — navigate it, click things, fill forms, and report back bugs backed by screenshots and console output, not a guess from reading source code.

Good uses include:

- A pre-ship QA pass on a local dev server or a PR preview deployment
- Exploring a staging build to find whatever breaks
- Checking a specific flow (signup, checkout, settings) end-to-end
- A visual/console sanity check after a UI change

Do not use it for a static code review with nothing running — that's a normal code review or `pr-grill-me`. Do not use it if there's no reachable URL at all. Do not use it when the user specifically wants a WCAG conformance check with citations to success criteria — that's [`accessibility-audit`](../accessibility-audit/USE_CASES.md), which shares this skill's browser driver.

## User examples

> Dogfood my app at `http://localhost:5173`. Try creating, editing, and deleting a project.

> Test the staging signup flow. Use a fake account and don't submit any real payment.

> Explore the mobile nav and tell me anything confusing or broken.

> Check whether this dashboard works with just the keyboard.

> Run a QA pass on the PR preview URL before we merge.

## Model selection cues

Select this skill when the user asks to:

- "test the app" / "click through the site" / "find UX bugs"
- "explore the staging build" / "see what breaks"
- "dogfood this" / "dogfood the preview"
- QA a specific flow on a running app

Do not select it for:

- A diff-only review with no running app (use `pr-grill-me`)
- A task where the user hasn't given, and none can be found for, a reachable URL
- Pure API/backend debugging with no UI involved (there's no browser to drive)

## Inputs the model should establish

Before starting:

- **Target URL** — if not given, check `package.json` for a dev script, then probe common local ports (`3000`, `5173`, `8080`, `4200`, `5000`, `8000`) and use the first that responds. If none respond, ask the user to choose a local port, a staging URL, or a public URL.
- **Scope** — which flows/areas matter most. Default to full site from `/` if unspecified, and say so explicitly rather than silently guessing.
- **Output directory** (optional, defaults to `./dogfood-output`)
- **Anything destructive to avoid** — real purchases, real account deletion, real emails sent, etc. — confirm boundaries before testing flows that could trigger them.
- One-time setup check: has `dogfood/scripts && npm install` been run in this environment yet?

## Example model plan

1. Create the output directory (`screenshots/`, `issues.json`, `report.md`).
2. Sketch a sitemap: home, nav, key flows, forms, edge cases (404s, empty states).
3. Launch the browser driver in the background (`launch --state-dir ...`) — it blocks until `close`.
4. For each page/flow: `navigate` → `snapshot` → `console` (check for JS errors) → `annotate` + Read the screenshot → `click`/`type`/`press` to exercise it → `console` again to check for regressions.
5. For every issue found: `screenshot`, append to `issues.json` with severity/category from [references/issue-taxonomy.md](references/issue-taxonomy.md).
6. De-duplicate and sort findings by severity.
7. Fill `templates/dogfood-report-template.md` into `report.md`.
8. `close` the browser session.
9. Send the report and the Critical/High screenshots to the user, not just a text summary.

## Expected output

A useful run leaves:

- `dogfood-output/report.md` — executive summary, per-issue sections with screenshots, severity/category breakdown, what was and wasn't tested
- `dogfood-output/issues.json` — the raw findings log
- `dogfood-output/screenshots/*.png` — evidence for every issue
- A running browser session that was cleanly `close`d, not left orphaned

## Example result shape

```markdown
## Finding: Save button remains disabled after editing a project name

**Severity:** High | **Category:** Functional
**URL:** /projects/42/edit
**Steps:** Clear the name field, type a new name, tab away from the field.
**Expected:** Save button becomes enabled once the field is valid.
**Actual:** Save stays disabled; console shows `Cannot read properties of
undefined (reading 'trim')` in `validateName()`.
**Evidence:** screenshots/issue-3.png
```

Report verdict: total issues by severity, and whether the flow tested is ready to ship or needs fixes first.
