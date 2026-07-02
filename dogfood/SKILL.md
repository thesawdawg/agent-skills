---
name: dogfood
description: Run systematic, evidence-backed exploratory QA on a live web app — navigate its pages, exercise interactive elements, capture console errors and screenshots, then produce a categorized bug report. Use when the user wants to find bugs in a web application before shipping, wants a QA pass on a deployed app or PR preview, or asks to "dogfood" a URL.
---

# Dogfood Skill

Systematic exploratory QA of a web application: navigate it, interact with it, capture evidence of anything broken, and produce a structured bug report with screenshots and console errors attached.

This skill drives a real headless Chromium instance via a small bundled Playwright script (`scripts/browser-driver.mjs`) — there's no built-in browser tool in this environment, so the script fills that gap. It keeps one browser session alive across the whole testing pass so pages, cookies, and console history persist between commands.

## Prerequisites

- One-time setup: `cd dogfood/scripts && npm install` (pulls in the `playwright` npm package only — the Chromium *binary* is already pre-installed in this environment and `npm install` will not re-download it).
- A target URL and testing scope from the user, or the defaults below if they don't give one.

## Inputs

The user provides:

1. **Target URL** — the entry point for testing. If they don't give one, don't just ask an open-ended question — offer concrete options:
   - Check `package.json` for a `dev`/`start` script and try its declared port, or probe common local defaults in order: `http://localhost:3000`, `http://localhost:5173`, `http://localhost:8080`, `http://localhost:4200`, `http://localhost:5000`, `http://127.0.0.1:8000`. Use the first one that responds.
   - If none respond, ask the user to pick: **(a)** a local dev server on a different port, **(b)** a staging/preview URL, or **(c)** a public URL — and have them paste it.
2. **Scope** — what areas/features to focus on. If not given, default to **full site**, starting from the target's base root path (`/`), and say explicitly that's what you're doing rather than silently guessing.
3. **Output directory** (optional) — where to save screenshots and the report (default: `./dogfood-output`)

## Workflow

Work through five phases. Track each as a task.

### Phase 1: Plan

1. Create the output directory structure:
   ```
   {output_dir}/
   ├── screenshots/       # Evidence screenshots
   ├── issues.json        # Running list of findings (build this as you go)
   └── report.md          # Final report (generated in Phase 5)
   ```
2. Identify the testing scope based on user input.
3. Sketch a rough sitemap of what to test:
   - Landing/home page
   - Navigation links (header, footer, sidebar)
   - Key user flows (sign up, login, search, checkout, etc.)
   - Forms and interactive elements
   - Edge cases (empty states, error pages, 404s)
4. Start the browser session in the background and leave it running for the rest of the session:
   ```bash
   node dogfood/scripts/browser-driver.mjs launch --state-dir {output_dir}/.browser
   ```
   Run this with `run_in_background: true` — it blocks intentionally until you call `close` in Phase 5. Every other command below reads `--state-dir {output_dir}/.browser` and will wait for the browser to be ready, so you don't need to sleep before using it.

### Phase 2: Explore

For each page or feature in your plan:

1. **Navigate:**
   ```bash
   node dogfood/scripts/browser-driver.mjs navigate --state-dir {output_dir}/.browser --url "https://example.com/page"
   ```

2. **Snapshot the accessibility tree** to understand page structure:
   ```bash
   node dogfood/scripts/browser-driver.mjs snapshot --state-dir {output_dir}/.browser
   ```

3. **Check the console** for JavaScript errors:
   ```bash
   node dogfood/scripts/browser-driver.mjs console --state-dir {output_dir}/.browser --clear true
   ```
   Do this after every navigation and after every significant interaction. Silent JS errors are high-value findings.

4. **Annotate interactive elements** and look at the page yourself:
   ```bash
   node dogfood/scripts/browser-driver.mjs annotate --state-dir {output_dir}/.browser --path {output_dir}/screenshots/page-N.png
   ```
   This overlays numbered `[N]` badges on every visible interactive element, screenshots the page, and writes a `refs.json` mapping each number to a CSS selector. Then use the **Read tool** on the PNG directly — you're multimodal, so you can assess layout, visual bugs, and accessibility concerns yourself without a separate analysis step.

5. **Test interactive elements** systematically, referencing elements by number from the last `annotate` call:
   ```bash
   node dogfood/scripts/browser-driver.mjs click --state-dir {output_dir}/.browser --ref 3
   node dogfood/scripts/browser-driver.mjs type --state-dir {output_dir}/.browser --ref 5 --text "test input"
   node dogfood/scripts/browser-driver.mjs press --state-dir {output_dir}/.browser --key Tab
   node dogfood/scripts/browser-driver.mjs press --state-dir {output_dir}/.browser --key Enter
   node dogfood/scripts/browser-driver.mjs scroll --state-dir {output_dir}/.browser --direction down
   node dogfood/scripts/browser-driver.mjs back --state-dir {output_dir}/.browser
   ```
   You can also pass `--selector "<css>"` directly instead of `--ref` when you already know the selector. Cover keyboard navigation, form validation with invalid inputs, and empty submissions.

6. **After each interaction**, check for regressions:
   - Console: `node dogfood/scripts/browser-driver.mjs console --state-dir {output_dir}/.browser`
   - Visual: re-run `annotate` or `screenshot` and Read the image to see what changed
   - Compare expected vs. actual behavior

### Phase 3: Collect Evidence

For every issue found:

1. Capture it:
   ```bash
   node dogfood/scripts/browser-driver.mjs screenshot --state-dir {output_dir}/.browser --path {output_dir}/screenshots/issue-N.png
   ```
2. Append an entry to `{output_dir}/issues.json` (a plain JSON array) so findings survive a long session:
   ```json
   { "url": "...", "steps": ["..."], "expected": "...", "actual": "...", "console": "...", "screenshot": "screenshots/issue-N.png" }
   ```
3. Classify severity (Critical/High/Medium/Low) and category (Functional/Visual/Accessibility/Console/UX/Content) against `references/issue-taxonomy.md`.

### Phase 4: Categorize

1. Read back `{output_dir}/issues.json` in full.
2. De-duplicate — merge issues that are the same bug manifesting in different places.
3. Assign final severity and category to each issue.
4. Sort by severity (Critical first, then High, Medium, Low).
5. Count issues by severity and category for the executive summary.

### Phase 5: Report

1. Generate the final report using `templates/dogfood-report-template.md`, filling in the executive summary, per-issue sections (screenshots as relative markdown image links to `screenshots/*.png`), the summary table, and testing notes (what was tested, what wasn't, any blockers). Save it to `{output_dir}/report.md`.
2. Shut down the browser session:
   ```bash
   node dogfood/scripts/browser-driver.mjs close --state-dir {output_dir}/.browser
   ```
3. Surface the report and the most important screenshots (Critical/High issues) to the user with `SendUserFile`, not just a text summary — the evidence is the point.

## Driver Command Reference

| Command | Purpose |
|---------|---------|
| `launch` | Start the persistent headless browser (run in background, blocks until `close`) |
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

- **Always check the console after navigating and after significant interactions.** Silent JS errors are among the most valuable findings.
- **Use `annotate`** whenever you need to click something precisely or reason about element positions — `snapshot` alone gives you structure but not visual layout.
- **Test with both valid and invalid inputs** — form validation bugs are common.
- **Scroll through long pages** — content below the fold may have rendering issues.
- **Test navigation flows end-to-end**, not just individual pages.
- **Note responsive/layout issues** visible in screenshots.
- **Don't forget edge cases**: empty states, very long text, special characters, rapid clicking.
- **Always run `close` when done** — it's the only thing that stops the background browser process.
