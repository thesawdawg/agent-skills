#!/usr/bin/env node
// dogfood-browser.mjs — headless browser driver for the `dogfood` QA skill.
//
// Pi has NO MCP and NO built-in browser tools, so this script gives the agent
// browser automation through the `bash` tool instead. One command per page is
// far easier for a small local model than orchestrating many separate calls.
//
// Setup (run once, from any project that has a package.json or just globally):
//   npm i -D playwright   &&   npx playwright install chromium
//
// Usage:
//   # Inspect ONE page: prints a JSON report, saves a screenshot.
//   node dogfood-browser.mjs inspect <url> --out <dir> [--name <slug>]
//
//   # Run a multi-step FLOW (login, search, checkout...): keeps one browser
//   # session, snapshots after each step. Steps come from a JSON file.
//   node dogfood-browser.mjs flow <steps.json> --out <dir>
//
// The JSON report (stdout) is what you, the agent, read and reason about.
// Screenshots are written to <dir>/screenshots/ as PNG evidence files.

import { mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { join } from "node:path";

// ---- arg parsing -----------------------------------------------------------

const argv = process.argv.slice(2);
const cmd = argv[0];
const positional = [];
const flags = {};
for (let i = 1; i < argv.length; i++) {
  const a = argv[i];
  if (a.startsWith("--")) {
    flags[a.slice(2)] = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : true;
  } else {
    positional.push(a);
  }
}
const outDir = flags.out || "dogfood-output";
const shotsDir = join(outDir, "screenshots");

function slug(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "").slice(0, 60) || "page";
}

function die(msg, code = 1) {
  console.error(msg);
  process.exit(code);
}

// ---- load playwright (clear message if missing) ----------------------------

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  die(
    "Playwright is not installed. Run:\n" +
      "  npm i -D playwright && npx playwright install chromium\n" +
      "Then re-run this command.",
    2,
  );
}

// ---- shared helpers --------------------------------------------------------

// Attach console / error / network listeners to a page and return a live log.
function watch(page) {
  const log = { console: [], pageErrors: [], failedRequests: [] };
  page.on("console", (m) => {
    const t = m.type();
    if (t === "error" || t === "warning") log.console.push({ type: t, text: m.text().slice(0, 500) });
  });
  page.on("pageerror", (e) => log.pageErrors.push(String(e.message || e).slice(0, 500)));
  page.on("requestfailed", (r) =>
    log.failedRequests.push({ url: r.url().slice(0, 200), error: r.failure()?.errorText || "failed" }),
  );
  page.on("response", (r) => {
    const s = r.status();
    if (s >= 400) log.failedRequests.push({ url: r.url().slice(0, 200), status: s });
  });
  return log;
}

// Pull a compact, accessibility-ish inventory of the page for the model.
async function snapshotPage(page) {
  return page.evaluate(() => {
    const txt = (el) => (el.innerText || el.value || el.getAttribute("aria-label") || "").trim().replace(/\s+/g, " ");
    const vis = (el) => {
      const r = el.getBoundingClientRect();
      const s = getComputedStyle(el);
      return r.width > 0 && r.height > 0 && s.visibility !== "hidden" && s.display !== "none";
    };
    const take = (sel, n, map) =>
      [...document.querySelectorAll(sel)].filter(vis).slice(0, n).map(map);
    return {
      title: document.title,
      headings: take("h1,h2,h3", 30, (e) => `${e.tagName}: ${txt(e).slice(0, 80)}`),
      links: take("a[href]", 60, (e) => ({ text: txt(e).slice(0, 60), href: e.getAttribute("href") })),
      buttons: take("button,[role=button],input[type=submit]", 40, (e) => txt(e).slice(0, 60) || "(no label)"),
      inputs: take("input,textarea,select", 40, (e) => ({
        type: e.type || e.tagName.toLowerCase(),
        name: e.name || e.id || "",
        placeholder: e.placeholder || "",
        label: (e.labels && e.labels[0] && e.labels[0].innerText.trim()) || "",
        required: !!e.required,
      })),
      images: take("img", 40, (e) => ({ src: (e.currentSrc || e.src || "").slice(0, 120), alt: e.alt, broken: !e.complete || e.naturalWidth === 0 })),
      bodyTextPreview: (document.body?.innerText || "").trim().replace(/\s+/g, " ").slice(0, 800),
    };
  });
}

async function shoot(page, name) {
  mkdirSync(shotsDir, { recursive: true });
  const file = join(shotsDir, `${slug(name)}.png`);
  await page.screenshot({ path: file, fullPage: true }).catch(() => page.screenshot({ path: file }));
  return file;
}

// ---- commands --------------------------------------------------------------

async function runInspect() {
  const url = positional[0];
  if (!url) die("Usage: node dogfood-browser.mjs inspect <url> --out <dir> [--name <slug>]");
  const name = flags.name || slug(url.replace(/^https?:\/\//, ""));

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const log = watch(page);
  let navError = null;
  try {
    await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
  } catch (e) {
    try {
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
    } catch (e2) {
      navError = String(e2.message || e2);
    }
  }
  await page.waitForTimeout(500);
  const snap = navError ? {} : await snapshotPage(page);
  const screenshot = await shoot(page, name);
  await browser.close();

  console.log(JSON.stringify({ requestedUrl: url, finalUrl: navError ? null : page.url(), navError, screenshot, ...snap, ...log }, null, 2));
}

async function runFlow() {
  const stepsFile = positional[0];
  if (!stepsFile) die("Usage: node dogfood-browser.mjs flow <steps.json> --out <dir>");
  let steps;
  try {
    steps = JSON.parse(readFileSync(stepsFile, "utf8"));
  } catch (e) {
    die(`Could not read/parse ${stepsFile}: ${e.message}`);
  }
  if (!Array.isArray(steps)) die("steps.json must be a JSON array of step objects.");

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const log = watch(page);
  const results = [];

  const loc = (step) =>
    step.text ? page.getByText(step.text, { exact: false }).first() : page.locator(step.selector).first();

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    const rec = { step: i + 1, action: step.action, target: step.selector || step.text || step.url || step.key };
    try {
      switch (step.action) {
        case "goto": await page.goto(step.url, { waitUntil: "domcontentloaded", timeout: 30000 }); break;
        case "click": await loc(step).click({ timeout: 8000 }); break;
        case "fill": await loc(step).fill(step.text ?? step.value ?? "", { timeout: 8000 }); break;
        case "press": await page.keyboard.press(step.key || "Enter"); break;
        case "wait": step.selector ? await page.locator(step.selector).first().waitFor({ timeout: 8000 }) : await page.waitForTimeout(step.ms || 1000); break;
        case "snapshot": break; // just record state below
        default: rec.error = `unknown action "${step.action}"`;
      }
      await page.waitForTimeout(400);
      rec.finalUrl = page.url();
      if (step.snapshot || step.action === "snapshot") {
        rec.snapshot = await snapshotPage(page);
        rec.screenshot = await shoot(page, step.name || `step-${i + 1}-${step.action}`);
      }
    } catch (e) {
      rec.error = String(e.message || e).slice(0, 300);
      rec.screenshot = await shoot(page, `step-${i + 1}-error`).catch(() => null);
    }
    results.push(rec);
  }
  await browser.close();
  console.log(JSON.stringify({ steps: results, console: log.console, pageErrors: log.pageErrors, failedRequests: log.failedRequests }, null, 2));
}

// ---- dispatch --------------------------------------------------------------

mkdirSync(outDir, { recursive: true });
if (cmd === "inspect") await runInspect();
else if (cmd === "flow") await runFlow();
else die("Usage:\n  node dogfood-browser.mjs inspect <url> --out <dir> [--name <slug>]\n  node dogfood-browser.mjs flow <steps.json> --out <dir>");
