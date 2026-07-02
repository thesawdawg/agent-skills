---
name: dogfood
description: Run systematic, evidence-backed exploratory QA on a live web app — navigate its pages, exercise interactive elements, capture console errors and screenshots, then produce a categorized bug report. Use when the user wants to find bugs in a web application before shipping, wants a QA pass on a deployed app or PR preview, or asks to "dogfood" a URL.
---

# Dogfood Skill (pi-adapted)

Systematic exploratory QA of a web application: navigate it, interact with it, capture evidence of anything broken, and produce a structured bug report with screenshots and console errors attached.

This skill drives a real headless Chromium instance through a small bundled Node script (`scripts/browser-driver.mjs`). It keeps one browser session alive across the whole testing pass, so pages, cookies, and console history persist between commands. It needs only the four core tools every harness has — **Read, Write, Edit, Bash** — plus Node. No harness-specific browser tool is required.

## Skill files & paths (read first)

Every command in this skill calls the bundled driver script. So the model doesn't lose track of where that script lives, **set one variable at the start and reuse it**:

```bash
# SKILL_DIR = the directory that contains THIS SKILL.md file.
# You (the agent) loaded this file from a known path — use that path's directory.
# Example if it was loaded from /home/me/.pi/agent/skills/dogfood/SKILL.md:
SKILL_DIR="/home/me/.pi/agent/skills/dogfood"
```

If you are unsure of the path, find it once:

```bash
SKILL_DIR="$(dirname "$(find "$HOME" /workspace . -name SKILL.md -path '*dogfood*' 2>/dev/null | head -n1)")"
echo "$SKILL_DIR"   # sanity-check: should end in /dogfood and contain scripts/browser-driver.mjs
```

Every driver call below is written as `node "$SKILL_DIR/scripts/browser-driver.mjs" ...`.

## Prerequisites

One-time setup (installs the Node Playwright package and a Chromium binary):

```bash
cd "$SKILL_DIR/scripts"
npm install
# If no Chromium is already present on the machine, fetch one (safe to run twice):
npx playwright install chromium
cd -   # return to the project directory
```

Notes:
- If a Chromium binary is already installed (some environments pre-provision one and set `PLAYWRIGHT_BROWSERS_PATH`), the driver auto-detects it and `npx playwright install` is a no-op — running it anyway is harmless.
- The driver needs Node 18+. Check with `node --version` if `launch` fails.

## Inputs

1. **Target URL** — the entry point for testing. If the user didn't give one, don't just ask an open-ended question — offer concrete options:
   - Check `package.json` for a `dev`/`start` script and try its declared port, or probe common local defaults in order and use the first that responds:
     ```bash
     for u in http://localhost:3000 http://localhost:5173 http://localhost:8080 http://localhost:4200 http://localhost:5000 http://127.0.0.1:8000; do
       curl -sf -o /dev/null "$u" && echo "responds: $u" && break
     done
     ```
   - If none respond, ask the user to pick: **(a)** a local dev server on a different port, **(b)** a staging/preview URL, or **(c)** a public URL — and have them paste it.
2. **Scope** — what areas/features to focus on. If not given, default to **full site**, starting from the base root path (`/`), and say explicitly that's what you're doing rather than silently guessing.
3. **Output directory** — where to save screenshots and the report. Default: `./dogfood-output`. Set it once so later steps are unambiguous:
   ```bash
   OUT="./dogfood-output"
   ```

## Workflow

Five phases. If your harness has a task/todo list, track each phase on it.

### Phase 1: Plan

1. Create the output directory structure:
   ```bash
   mkdir -p "$OUT/screenshots"
   : > "$OUT/issues.json"   # start an empty findings file
   ```
   Target layout:
   ```
   $OUT/
   ├── screenshots/     # evidence screenshots
   ├── issues.json      # running list of findings (append as you go)
   └── report.md        # final report (written in Phase 5)
   ```
2. Confirm the testing scope (from Inputs above).
3. Sketch a rough sitemap of what to test:
   - Landing/home page
   - Navigation links (header, footer, sidebar)
   - Key user flows (sign up, login, search, checkout, etc.)
   - Forms and interactive elements
   - Edge cases (empty states, error pages, 404s)
4. Start the browser session in the background and leave it running until Phase 5:
   ```bash
   node "$SKILL_DIR/scripts/browser-driver.mjs" launch --state-dir "$OUT/.browser"
   ```
   Run this **in the background** (it blocks on purpose until you call `close` in Phase 5). In pi/Bash: append ` &` or use your harness's background-run option. Every other command reads `--state-dir "$OUT/.browser"` and waits for the browser to be ready, so you do not need to sleep before using it. When `launch` prints `READY`, the browser is up.

### Phase 2: Explore

For each page or feature in your plan, do these in order:

1. **Navigate:**
   ```bash
   node "$SKILL_DIR/scripts/browser-driver.mjs" navigate --state-dir "$OUT/.browser" --url "https://example.com/page"
   ```

2. **Snapshot the accessibility tree** (text structure of the page — labels, roles, headings):
   ```bash
   node "$SKILL_DIR/scripts/browser-driver.mjs" snapshot --state-dir "$OUT/.browser"
   ```

3. **Check the console** for JavaScript errors, and clear it for the next step:
   ```bash
   node "$SKILL_DIR/scripts/browser-driver.mjs" console --state-dir "$OUT/.browser" --clear true
   ```
   Do this **after every navigation and after every significant interaction**. Silent JS errors are among the most valuable findings.

4. **Annotate interactive elements** and inspect the page:
   ```bash
   node "$SKILL_DIR/scripts/browser-driver.mjs" annotate --state-dir "$OUT/.browser" --path "$OUT/screenshots/page-1.png"
   ```
   This overlays numbered `[N]` badges on every visible interactive element, saves the screenshot, and writes a `refs.json` mapping each number to a CSS selector.
   - **If your harness can view images** (it can Read/open a PNG): open the screenshot and assess layout, visual bugs, and accessibility concerns directly.
   - **If it cannot view images**: rely on the accessibility-tree `snapshot` from step 2 — it captures structure, labels, headings, and most functional/accessibility issues in text form. Note in the report that visual-only issues weren't assessed.

5. **Test interactive elements**, referencing elements by the number from the last `annotate` call:
   ```bash
   node "$SKILL_DIR/scripts/browser-driver.mjs" click  --state-dir "$OUT/.browser" --ref 3
   node "$SKILL_DIR/scripts/browser-driver.mjs" type   --state-dir "$OUT/.browser" --ref 5 --text "test input"
   node "$SKILL_DIR/scripts/browser-driver.mjs" press  --state-dir "$OUT/.browser" --key Tab
   node "$SKILL_DIR/scripts/browser-driver.mjs" press  --state-dir "$OUT/.browser" --key Enter
   node "$SKILL_DIR/scripts/browser-driver.mjs" scroll --state-dir "$OUT/.browser" --direction down
   node "$SKILL_DIR/scripts/browser-driver.mjs" back   --state-dir "$OUT/.browser"
   ```
   You can also pass `--selector "<css>"` instead of `--ref` when you already know the selector. Cover keyboard navigation, form validation with invalid inputs, and empty submissions.

6. **After each interaction**, re-check for regressions:
   - Console: `node "$SKILL_DIR/scripts/browser-driver.mjs" console --state-dir "$OUT/.browser"`
   - Visual/structure: re-run `annotate` (or `snapshot`) and compare to before.
   - Ask: did the expected thing happen? If not, that's a finding.

### Phase 3: Collect Evidence

For every issue found:

1. Capture a screenshot:
   ```bash
   node "$SKILL_DIR/scripts/browser-driver.mjs" screenshot --state-dir "$OUT/.browser" --path "$OUT/screenshots/issue-1.png"
   ```
2. Append one entry to `$OUT/issues.json` (keep it a JSON array so findings survive a long session). Each entry:
   ```json
   { "url": "...", "steps": ["..."], "expected": "...", "actual": "...", "console": "...", "screenshot": "screenshots/issue-1.png", "severity": "", "category": "" }
   ```
3. Classify **severity** (Critical / High / Medium / Low) and **category** (Functional / Visual / Accessibility / Console / UX / Content) using `references/issue-taxonomy.md` (read it with the Read tool: `$SKILL_DIR/references/issue-taxonomy.md`).

### Phase 4: Categorize

1. Read `$OUT/issues.json` back in full.
2. De-duplicate — merge entries that are the same bug appearing in different places.
3. Assign each issue a final severity and category.
4. Sort by severity: Critical first, then High, Medium, Low.
5. Count issues by severity and by category (for the summary table).

### Phase 5: Report

1. Write the final report to `$OUT/report.md` using the template at `$SKILL_DIR/templates/dogfood-report-template.md` (read it first). Fill in: executive summary, per-issue sections (link screenshots as relative markdown images, e.g. `![](screenshots/issue-1.png)`), the summary table, and testing notes (what was tested, what wasn't, any blockers — including "visual issues not assessed" if the harness couldn't view images).
2. Shut down the browser session:
   ```bash
   node "$SKILL_DIR/scripts/browser-driver.mjs" close --state-dir "$OUT/.browser"
   ```
3. Tell the user where the report and the Critical/High screenshots are (give the exact paths, e.g. `$OUT/report.md`). If your harness has a file-delivery capability, use it to surface the report and top screenshots; otherwise the paths in your final message are enough.

## Driver Command Reference

| Command | Purpose |
|---------|---------|
| `launch` | Start the persistent headless browser (run in background; blocks until `close`) |
| `close` | Signal the running browser to shut down |
| `navigate --url <url>` | Go to a URL |
| `snapshot` | Dump the accessibility tree as JSON |
| `screenshot [--path <file>] [--fullpage true]` | Plain screenshot, no annotation |
| `annotate [--path <file>]` | Screenshot with numbered element badges + `refs.json` for `--ref` lookups |
| `click --ref <N> \| --selector <css>` | Click an element |
| `type --ref <N> \| --selector <css> --text <str>` | Fill a field |
| `press --key <key>` | Press a keyboard key |
| `scroll [--direction up\|down]` | Scroll the page |
| `back` | Go back in browser history |
| `console [--clear true]` | Read (and optionally clear) captured console/page errors |

All commands take `--state-dir <dir>` pointing at the same directory passed to `launch`.

## Tips

- **Always check the console after navigating and after significant interactions.** Silent JS errors are high value.
- **Use `annotate`** whenever you need to click something precisely or reason about element positions — `snapshot` gives structure but not visual layout.
- **Test with both valid and invalid inputs** — form-validation bugs are common.
- **Scroll through long pages** — content below the fold may have rendering issues.
- **Test navigation flows end-to-end**, not just individual pages.
- **Don't forget edge cases**: empty states, very long text, special characters, rapid clicking.
- **Always run `close` when done** — it is the only thing that stops the background browser process.
