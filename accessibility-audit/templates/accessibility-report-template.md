# Accessibility Audit Report

**Target:** {target_url}
**Date:** {date}
**Scope:** {scope_description}
**Conformance target:** WCAG 2.2 Level {AA|AAA} (superset of 2.0/2.1 at the same level)
**Tester:** Claude Code (automated scan via axe-core {axe_core_version} + manual verification)

---

## Executive Summary

| Result | Count |
|--------|-------|
| 🔴 Critical | {critical_count} |
| 🟠 Serious | {serious_count} |
| 🟡 Moderate | {moderate_count} |
| 🔵 Minor | {minor_count} |
| **Total violations** | **{total_count}** |
| ⚪ Needs manual review | {manual_review_count} |

**Overall conformance verdict:** {conformance_verdict — e.g. "Does not meet Level AA: N violations across M success criteria" / "Meets Level AA automated checks; manual review items remain" / "Meets Level AA"}

---

## Success Criteria Checklist

<!-- One row per SC actually in scope for this audit — pull names/levels from references/wcag-criteria.md -->

| SC | Name | Level | Status | Notes |
|----|------|-------|--------|-------|
| {sc_number} | {sc_name} | {A/AA} | ✅ Pass / ❌ Fail / ⚪ Manual review needed / ➖ N/A | {one-line note} |

---

## Violations (Automated — axe-core)

<!-- Repeat per violation, sorted by impact: critical → serious → moderate → minor -->

### {rule_id}: {violation_description}

| Field | Value |
|-------|-------|
| **WCAG SC** | {sc_number} — {sc_name} ({level}) |
| **Impact** | {critical/serious/moderate/minor} |
| **URL** | {url_where_found} |
| **Elements affected** | {count} |

**Issue:** {axe help text}

**Affected elements:**
```
{selector_1} — {html_snippet_1}
{selector_2} — {html_snippet_2}
```

**How to fix:** {axe help + helpUrl, paraphrased}

**Screenshot:** ![violation]({screenshot_path})

---

## Manual Verification Findings

<!-- Findings from Phase 3 checks axe cannot perform: keyboard nav, focus order,
     alt-text quality, timing/motion, error message quality, cross-page consistency -->

### {finding_title}

| Field | Value |
|-------|-------|
| **WCAG SC** | {sc_number} — {sc_name} ({level}) |
| **Method** | {e.g. "Tab-only navigation through checkout flow"} |
| **Severity** | {Blocker/Major/Minor} |

**Expected:** {what WCAG requires}
**Actual:** {what was observed}
**Evidence:** {screenshot path / accessibility-tree snapshot excerpt}

---

## Not Tested / Out of Scope

- {areas_not_covered_and_why — e.g. video content requiring human caption review, third-party embedded widgets}

## Blockers

- {anything that prevented testing part of the scope}

---

## Notes

{any additional observations — e.g. patterns worth fixing systemically rather than per-instance, design-system-level recommendations}

---
