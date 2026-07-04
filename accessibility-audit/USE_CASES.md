# accessibility-audit: Practical Use Cases

This guide shows **when to invoke `accessibility-audit`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full five-phase workflow, [references/wcag-criteria.md](references/wcag-criteria.md) for the WCAG 2.2 success-criteria table, and the `axe` command this skill adds to the shared [dogfood browser driver](../dogfood/SKILL.md). This file is examples only. See also the [top-level skills index](../USE_CASES.md).

## Use it when

Use `accessibility-audit` when the user wants to know whether a live web app **conforms to WCAG** — specifically citing success criteria and levels, not just a general "does this look accessible" impression.

Good uses include:

- A pre-ship WCAG 2.2 AA compliance check
- Verifying a specific flow (checkout, signup, a form) against accessibility standards
- A legal/procurement-driven accessibility audit (ADA, Section 508, EN 301 549 all reference WCAG AA)
- Checking whether a recent UI change introduced a regression against a specific success criterion

Do not use it for a general bug-hunting QA pass with no accessibility focus — that's [`dogfood`](../dogfood/USE_CASES.md) (which this skill's driver is shared with; run `dogfood` first if the goal is broad QA and accessibility is just one category among several). Don't use it as a substitute for a real assistive-technology test with actual screen-reader users when the stakes are high — automated + manual-by-a-sighted-tester coverage is strong but not a replacement for testing with disabled users themselves on critical paths.

## User examples

> Run a WCAG AA audit on our checkout flow before we ship.

> Is this site accessible? Check it against WCAG 2.2.

> Audit `http://localhost:3000` for accessibility issues and tell me if we meet AA.

> We got a legal complaint about accessibility — check the signup form against WCAG and tell me exactly what's failing.

> Check this page for keyboard accessibility and color contrast.

## Model selection cues

Select this skill when the user asks to:

- "accessibility audit" / "a11y audit" / "WCAG audit" / "WCAG compliance"
- "is this accessible" / "check accessibility" / "AA compliant"
- "keyboard accessible" / "screen reader" / "color contrast" specifically as the testing goal
- cites WCAG, Section 508, ADA, or EN 301 549 by name

Do not select it when:

- The user wants general QA/bug-hunting with no specific accessibility framing — use [`dogfood`](../dogfood/USE_CASES.md)
- There's no running app to test against — this skill drives a real browser, same as dogfood
- The user wants a code-level a11y lint (e.g. `eslint-plugin-jsx-a11y` on source, not a running page) — that's a static analysis task, not this skill

## Inputs the model should establish

- **Target URL** — same discovery pattern as dogfood (check `package.json`, probe common local ports, or ask).
- **Scope** — which pages/flows matter. Default to key pages, not the entire site, unless told otherwise.
- **Conformance target** — default **WCAG 2.2 Level AA** (superset of 2.0/2.1 AA). Ask only if the user wants AAA on specific criteria or wants to scope down.
- **Output directory** (optional, default `./accessibility-audit-output`).

## Example model plan

1. Confirm scope and conformance target with the user.
2. Launch the shared browser driver (`../dogfood/scripts/browser-driver.mjs launch`) in the background.
3. For each page: `navigate`, run `axe --tags wcag2a,wcag2aa,wcag21a,wcag21aa,wcag22aa`, record every violation with its WCAG SC (via the criteria table), impact, affected elements, and a screenshot.
4. Run the manual checks axe can't do: keyboard-only navigation, accessibility-tree review, alt-text quality judgment, reflow at 400% zoom, timing/motion observation, error-message quality, cross-page consistency.
5. De-duplicate findings (a shared header failing once often means every page "fails" the same way — report it once with all affected URLs).
6. Assign a Pass/Fail/Needs-manual-review/N/A status per success criterion actually in scope.
7. Fill the report template, state the overall conformance verdict plainly, close the browser, and surface the report plus Critical/Serious screenshots.

## Expected output

A useful run leaves:

- `accessibility-audit-output/report.md` — executive summary, a full per-SC checklist, detailed violations with WCAG citations and screenshots, manual findings, not-tested notes
- `accessibility-audit-output/violations.json` — the raw automated findings log
- `accessibility-audit-output/screenshots/*.png` — evidence for every violation and manual finding
- An explicit conformance verdict — not just a pile of findings with no bottom line

## Example result shape

```markdown
### color-contrast: Elements must meet minimum color contrast ratio thresholds

| Field | Value |
|-------|-------|
| **WCAG SC** | 1.4.3 — Contrast (Minimum) (AA) |
| **Impact** | serious |
| **URL** | /checkout |
| **Elements affected** | 3 |

**Issue:** Text color #999999 on background #ffffff has a contrast ratio of
2.85:1, below the required 4.5:1 for normal text.

**Affected elements:**
```
.checkout-summary .subtotal-label — <span class="subtotal-label">Subtotal</span>
```

**How to fix:** Darken the text to at least #767676 on white, or darken the
background, to reach 4.5:1.

**Screenshot:** screenshots/violation-2.png

---

**Overall conformance verdict:** Does not meet Level AA — 4 violations across
3 success criteria (1.4.3, 2.4.7, 4.1.2), plus 2 manual-review items pending
(alt-text quality on product images, cross-page nav consistency).
```
