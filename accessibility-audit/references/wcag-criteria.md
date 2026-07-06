# WCAG 2.2 Success Criteria Reference

> Referenced from [SKILL.md](../SKILL.md).

Human-readable companion to axe-core's machine tags (axe is the actual
up-to-date rule engine — see [SKILL.md](../SKILL.md) — this table is for
citing criteria by number/name in reports and for the manual checks axe
can't perform). WCAG 2.2 is a strict superset of 2.1 and 2.0 at the same
level: nothing was weakened, a handful of criteria were added (marked
**2.2**), and one (4.1.1) was removed as obsolete. Testing against 2.2
tags therefore also satisfies "2.0 AA and above."

**Default audit scope: Level A + AA.** WCAG's own conformance guidance
recommends against blanket-requiring AAA for an entire site — treat the AAA
table as opt-in, applied per-criterion where the user specifically wants a
stricter bar, not a default target.

axe-core tag convention: `wcag2a`/`wcag2aa` = WCAG 2.0 criteria at that
level; `wcag21a`/`wcag21aa` = criteria added in 2.1; `wcag22aa` = criteria
added in 2.2. A criterion's own tag (e.g. `wcag111`) maps 1:1 to its SC
number with dots removed.

## Level A (must-have baseline)

| SC | Name | axe tag | What it means |
|----|------|---------|---------------|
| 1.1.1 | Non-text Content | wcag2a | Images/icons/controls have text alternatives |
| 1.2.1 | Audio-only/Video-only (Prerecorded) | wcag2a | Alternative provided for non-interactive media |
| 1.2.2 | Captions (Prerecorded) | wcag2a | Captions on recorded video with audio |
| 1.2.3 | Audio Description or Media Alternative (Prerecorded) | wcag2a | Visual-only info in video is also available as audio/text |
| 1.3.1 | Info and Relationships | wcag2a | Structure (headings, lists, labels) is programmatic, not just visual |
| 1.3.2 | Meaningful Sequence | wcag2a | Reading/navigation order matches visual order |
| 1.3.3 | Sensory Characteristics | wcag2a | Instructions don't rely solely on shape/color/position ("click the round button") |
| 1.4.1 | Use of Color | wcag2a | Color is never the *only* way information is conveyed |
| 1.4.2 | Audio Control | wcag2a | Auto-playing audio can be paused/stopped/muted |
| 2.1.1 | Keyboard | wcag2a | All functionality is operable via keyboard alone |
| 2.1.2 | No Keyboard Trap | wcag2a | Keyboard focus can always move away from any component |
| 2.1.4 | Character Key Shortcuts | wcag21a | Single-key shortcuts can be turned off/remapped/require focus |
| 2.2.1 | Timing Adjustable | wcag2a | Time limits can be turned off, adjusted, or extended |
| 2.2.2 | Pause, Stop, Hide | wcag2a | Moving/auto-updating content can be paused |
| 2.3.1 | Three Flashes or Below Threshold | wcag2a | Nothing flashes more than 3 times/second |
| 2.4.1 | Bypass Blocks | wcag2a | A skip-link or landmark lets users jump past repeated nav |
| 2.4.2 | Page Titled | wcag2a | Every page has a descriptive `<title>` |
| 2.4.3 | Focus Order | wcag2a | Tab order is logical and matches meaning/sequence |
| 2.4.4 | Link Purpose (In Context) | wcag2a | A link's purpose is clear from its text (+ context) |
| 2.5.1 | Pointer Gestures | wcag21a | Multi-point/path gestures have a single-pointer alternative |
| 2.5.2 | Pointer Cancellation | wcag21a | Actions trigger on up-event, are abortable, or can be undone |
| 2.5.3 | Label in Name | wcag21a | Visible label text is contained in the accessible name |
| 2.5.4 | Motion Actuation | wcag21a | Motion-triggered actions have a UI alternative and can be disabled |
| 3.1.1 | Language of Page | wcag2a | `<html lang="...">` is set and correct |
| 3.2.1 | On Focus | wcag2a | Focusing an element never triggers an unexpected context change |
| 3.2.2 | On Input | wcag2a | Changing a form field never triggers an unexpected context change |
| 3.2.6 | Consistent Help | wcag22aa | Help mechanisms appear in the same relative order across pages **(2.2)** |
| 3.3.1 | Error Identification | wcag2a | Input errors are identified and described in text |
| 3.3.2 | Labels or Instructions | wcag2a | Form fields have labels or instructions |
| 3.3.7 | Redundant Entry | wcag22aa | Previously-entered info isn't required again in the same process **(2.2)** |
| 4.1.2 | Name, Role, Value | wcag2a | Custom/ARIA controls expose a correct accessible name, role, and state |

## Level AA (common legal/compliance baseline — default target)

| SC | Name | axe tag | What it means |
|----|------|---------|---------------|
| 1.2.4 | Captions (Live) | wcag2aa | Live audio content has real-time captions |
| 1.2.5 | Audio Description (Prerecorded) | wcag2aa | Prerecorded video has audio description |
| 1.3.4 | Orientation | wcag21aa | Content isn't locked to portrait or landscape only |
| 1.3.5 | Identify Input Purpose | wcag21aa | Common input fields (name, email, etc.) are programmatically identifiable (`autocomplete`) |
| 1.4.3 | Contrast (Minimum) | wcag2aa | Text contrast ratio ≥ 4.5:1 (3:1 for large text) |
| 1.4.4 | Resize Text | wcag2aa | Text can be resized to 200% without loss of content/function |
| 1.4.5 | Images of Text | wcag2aa | Real text is used instead of images of text (with exceptions) |
| 1.4.10 | Reflow | wcag21aa | Content reflows at 400% zoom / 320px width with no 2D scrolling |
| 1.4.11 | Non-text Contrast | wcag21aa | UI components/graphics have ≥ 3:1 contrast against adjacent colors |
| 1.4.12 | Text Spacing | wcag21aa | No loss of content when line/paragraph/letter/word spacing is increased |
| 1.4.13 | Content on Hover or Focus | wcag21aa | Hover/focus-triggered content is dismissible, hoverable, and persistent |
| 2.4.5 | Multiple Ways | wcag2aa | More than one way to locate a page (search, sitemap, nav) |
| 2.4.6 | Headings and Labels | wcag2aa | Headings and labels describe topic or purpose |
| 2.4.7 | Focus Visible | wcag2aa | Keyboard focus indicator is visible |
| 2.4.11 | Focus Not Obscured (Minimum) | wcag22aa | Focused element is not entirely hidden by other content **(2.2)** |
| 2.5.7 | Dragging Movements | wcag22aa | Drag actions have a single-pointer alternative that doesn't require dragging **(2.2)** |
| 2.5.8 | Target Size (Minimum) | wcag22aa | Pointer targets are at least 24×24 CSS px (with exceptions) **(2.2)** |
| 3.1.2 | Language of Parts | wcag2aa | Passages in a different language have the correct `lang` attribute |
| 3.2.3 | Consistent Navigation | wcag2aa | Repeated navigation is in the same relative order across pages |
| 3.2.4 | Consistent Identification | wcag2aa | Components with the same function are labeled consistently |
| 3.3.3 | Error Suggestion | wcag2aa | Input errors include a suggested fix, when known and safe to show |
| 3.3.4 | Error Prevention (Legal, Financial, Data) | wcag2aa | Submissions with legal/financial/data consequences are reversible, checked, or confirmed |
| 3.3.8 | Accessible Authentication (Minimum) | wcag22aa | Login doesn't require a cognitive test unless an alternative exists **(2.2)** |
| 4.1.3 | Status Messages | wcag21aa | Status messages are programmatically announced without moving focus |

## Level AAA (opt-in, apply per-criterion — not a default target)

1.2.6 Sign Language · 1.2.7 Extended Audio Description · 1.2.8 Media Alternative · 1.2.9 Audio-only (Live) · 1.3.6 Identify Purpose · 1.4.6 Contrast (Enhanced) · 1.4.7 Low/No Background Audio · 1.4.8 Visual Presentation · 1.4.9 Images of Text (No Exception) · 2.1.3 Keyboard (No Exception) · 2.2.3 No Timing · 2.2.4 Interruptions · 2.2.5 Re-authenticating · 2.2.6 Timeouts · 2.3.2 Three Flashes · 2.3.3 Animation from Interactions · 2.4.8 Location · 2.4.9 Link Purpose (Link Only) · 2.4.10 Section Headings · 2.4.12 Focus Not Obscured (Enhanced) **(2.2)** · 2.4.13 Focus Appearance **(2.2)** · 2.5.5 Target Size (Enhanced) · 2.5.6 Concurrent Input Mechanisms · 3.1.3 Unusual Words · 3.1.4 Abbreviations · 3.1.5 Reading Level · 3.1.6 Pronunciation · 3.2.5 Change on Request · 3.3.5 Help · 3.3.6 Error Prevention (All) · 3.3.9 Accessible Authentication (Enhanced) **(2.2)**

## Removed / obsolete

**4.1.1 Parsing** — part of WCAG 2.0/2.1, formally dropped in 2.2 because
modern browsers' HTML parsing makes it redundant. Don't cite it in a 2.2-scoped
report; axe-core has already dropped its corresponding rule for `wcag22aa`
tag runs.

## What axe-core cannot verify (manual-only, see SKILL.md Phase 3)

Automated tools cover an estimated 30-50% of WCAG failures by nature — these
require a human judgment call every time, regardless of tooling maturity:

- Alt text *quality* (vs. presence): 1.1.1
- Meaningful reading/focus order: 1.3.2, 2.4.3
- Real keyboard-only operability and trap-freedom: 2.1.1, 2.1.2
- Sensory-only instructions: 1.3.3
- Captions/audio-description content accuracy: 1.2.2, 1.2.3, 1.2.4, 1.2.5
- Timing, motion, and flashing behavior over time: 2.2.1, 2.2.2, 2.3.1
- Whether an unexpected context change happens on focus/input: 3.2.1, 3.2.2
- Error message clarity and suggestion quality: 3.3.1, 3.3.3
- Consistency of navigation/labeling *across* pages: 3.2.3, 3.2.4, 3.2.6
