#!/usr/bin/env node
// Bridges a persistent headless Chromium instance to stateless CLI invocations.
// `launch` owns the actual Playwright browser/context/page for the whole session
// and polls a request/response file queue; every other command just drops a
// request file and waits for the matching response — it never touches
// Playwright itself. (Playwright's connect() does not share contexts across
// separate client connections, so re-connecting per command doesn't work here.)
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

const [, , cmd, ...rest] = process.argv;
const args = {};
for (let i = 0; i < rest.length; i += 2) {
  args[rest[i].replace(/^--/, '')] = rest[i + 1];
}

const stateDir = args['state-dir'] || '.dogfood-state';
fs.mkdirSync(stateDir, { recursive: true });
const readyFile = path.join(stateDir, 'READY');
const stopFile = path.join(stateDir, 'STOP');
const refsFile = path.join(stateDir, 'refs.json');
const consoleLog = path.join(stateDir, 'console.log');
const requestsDir = path.join(stateDir, 'requests');
const responsesDir = path.join(stateDir, 'responses');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function resolveSelector() {
  if (args.selector) return args.selector;
  if (args.ref) {
    if (!fs.existsSync(refsFile)) throw new Error('No refs.json yet — run `annotate` first.');
    const refs = JSON.parse(fs.readFileSync(refsFile, 'utf8'));
    const entry = refs[args.ref];
    if (!entry) throw new Error(`Unknown ref @e${args.ref} — re-run \`annotate\`.`);
    return entry.selector;
  }
  throw new Error('Pass --selector <css> or --ref <N> (from the last `annotate` call).');
}

async function rpc(rpcCmd, rpcArgs) {
  const readyDeadline = Date.now() + 15000;
  while (!fs.existsSync(readyFile)) {
    if (Date.now() > readyDeadline) {
      throw new Error('Browser not ready — run `launch` first and wait for it to print READY.');
    }
    await sleep(300);
  }
  const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  fs.writeFileSync(path.join(requestsDir, `${id}.json`), JSON.stringify({ cmd: rpcCmd, args: rpcArgs }));
  const respPath = path.join(responsesDir, `${id}.json`);
  const deadline = Date.now() + 30000;
  while (!fs.existsSync(respPath)) {
    if (Date.now() > deadline) throw new Error(`Timed out waiting for browser to handle "${rpcCmd}".`);
    await sleep(150);
  }
  const raw = fs.readFileSync(respPath, 'utf8');
  fs.rmSync(respPath, { force: true });
  const resp = JSON.parse(raw);
  if (!resp.ok) throw new Error(resp.error);
  return resp.result;
}

async function runLaunch() {
  fs.rmSync(stopFile, { force: true });
  fs.rmSync(readyFile, { force: true });
  fs.writeFileSync(consoleLog, '');
  fs.rmSync(requestsDir, { recursive: true, force: true });
  fs.rmSync(responsesDir, { recursive: true, force: true });
  fs.mkdirSync(requestsDir, { recursive: true });
  fs.mkdirSync(responsesDir, { recursive: true });

  // Fall back to a pre-installed Chromium binary if the local `playwright` package
  // version doesn't match the cached browser revision (common in sandboxed setups
  // that pin a specific browser build outside npm's control).
  const fallbackChromium = '/opt/pw-browsers/chromium';
  const executablePath =
    args['executable-path'] ||
    process.env.PLAYWRIGHT_CHROMIUM_PATH ||
    (fs.existsSync(fallbackChromium) ? fallbackChromium : undefined);

  const browser = await chromium.launch({
    headless: args.headed === 'true' ? false : true,
    executablePath,
  });
  const context = await browser.newContext();
  const page = await context.newPage();
  page.on('framenavigated', () => fs.rmSync(refsFile, { force: true }));
  const log = (line) => fs.appendFileSync(consoleLog, `${line}\n`);
  page.on('console', (msg) => log(`[console.${msg.type()}] ${msg.text()}`));
  page.on('pageerror', (err) => log(`[pageerror] ${err.message}`));
  page.on('requestfailed', (req) => log(`[requestfailed] ${req.url()} ${req.failure()?.errorText || ''}`));

  async function handle(command, cargs) {
    if (['click', 'type', 'press', 'back', 'navigate', 'viewport'].includes(command)) {
      fs.rmSync(refsFile, { force: true });
    }
    switch (command) {
      case 'viewport': {
        const width = Number(cargs.width);
        const height = Number(cargs.height);
        if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1) {
          throw new Error('Viewport requires positive integer width and height');
        }
        await page.setViewportSize({ width, height });
        return { width, height };
      }
      case 'navigate': {
        await page.goto(cargs.url, { waitUntil: 'load', timeout: 30000 });
        return { url: page.url(), title: await page.title() };
      }
      case 'snapshot': {
        return await page.locator('body').ariaSnapshot();
      }
      case 'screenshot': {
        const file = cargs.path || path.join(stateDir, `shot-${Date.now()}.png`);
        await page.screenshot({ path: file, fullPage: cargs.fullpage === 'true' });
        return { file };
      }
      case 'annotate': {
        const refs = await page.evaluate(() => {
          const nodes = Array.from(
            document.querySelectorAll(
              'a, button, input, select, textarea, [role="button"], [role="link"], [onclick], [tabindex]:not([tabindex="-1"])'
            )
          ).filter((el) => {
            const r = el.getBoundingClientRect();
            const style = getComputedStyle(el);
            return r.width > 0 && r.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
          });
          document.querySelectorAll('[data-dogfood-badge]').forEach((n) => n.remove());
          const map = {};
          const generation = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
          nodes.forEach((el, i) => {
            const n = i + 1;
            const r = el.getBoundingClientRect();
            const badge = document.createElement('div');
            badge.setAttribute('data-dogfood-badge', '');
            badge.textContent = String(n);
            Object.assign(badge.style, {
              position: 'fixed',
              left: `${r.left}px`,
              top: `${Math.max(r.top - 14, 0)}px`,
              background: '#ff3b30',
              color: '#fff',
              font: 'bold 11px monospace',
              padding: '1px 4px',
              borderRadius: '3px',
              zIndex: 2147483647,
              pointerEvents: 'none',
            });
            document.body.appendChild(badge);
            el.setAttribute('data-dogfood-ref', `${generation}-${n}`);
            map[n] = {
              selector: `[data-dogfood-ref="${generation}-${n}"]`,
              tag: el.tagName.toLowerCase(),
              text: (el.innerText || el.value || el.placeholder || '').trim().slice(0, 80),
            };
          });
          return map;
        });
        const shot = cargs.path || path.join(stateDir, `annotated-${Date.now()}.png`);
        await page.screenshot({ path: shot });
        await page.evaluate(() => document.querySelectorAll('[data-dogfood-badge]').forEach((n) => n.remove()));
        fs.writeFileSync(refsFile, JSON.stringify(refs, null, 2));
        return { screenshot: shot, refs };
      }
      case 'click': {
        await page.locator(cargs.selector).first().click({ timeout: 10000 });
        return { selector: cargs.selector };
      }
      case 'type': {
        await page.locator(cargs.selector).first().fill(cargs.text ?? '');
        return { selector: cargs.selector };
      }
      case 'press': {
        await page.keyboard.press(cargs.key);
        return { key: cargs.key };
      }
      case 'scroll': {
        const dy = cargs.direction === 'up' ? -800 : 800;
        await page.mouse.wheel(0, dy);
        return { direction: cargs.direction || 'down' };
      }
      case 'back': {
        await page.goBack({ waitUntil: 'load' });
        return { url: page.url() };
      }
      case 'axe': {
        // Re-inject on every call rather than caching an "already injected" flag —
        // a `navigate` in between calls loads a fresh document with no axe global.
        const axeSource = fs.readFileSync(require.resolve('axe-core'), 'utf8');
        await page.evaluate(axeSource);
        const tags = cargs.tags
          ? cargs.tags.split(',')
          : ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'];
        return await page.evaluate(
          async (runTags) => window.axe.run(document, { runOnly: { type: 'tag', values: runTags } }),
          tags
        );
      }
      default:
        throw new Error(`Unknown command: ${command}`);
    }
  }

  fs.writeFileSync(readyFile, '1');
  console.log('READY');

  while (!fs.existsSync(stopFile)) {
    const files = fs.readdirSync(requestsDir).sort();
    for (const f of files) {
      const reqPath = path.join(requestsDir, f);
      let req;
      try {
        req = JSON.parse(fs.readFileSync(reqPath, 'utf8'));
      } catch {
        continue; // still being written, pick it up next tick
      }
      fs.rmSync(reqPath, { force: true });
      const id = f.replace(/\.json$/, '');
      try {
        const result = await handle(req.cmd, req.args);
        fs.writeFileSync(path.join(responsesDir, `${id}.json`), JSON.stringify({ ok: true, result }));
      } catch (err) {
        fs.writeFileSync(path.join(responsesDir, `${id}.json`), JSON.stringify({ ok: false, error: err.message }));
      }
    }
    await sleep(200);
  }
  await browser.close();
  fs.rmSync(readyFile, { force: true });
}

async function main() {
  switch (cmd) {
    case 'launch': {
      const lock = path.join(stateDir, 'OWNER');
      const descriptor = fs.openSync(lock, 'wx');
      fs.closeSync(descriptor);
      const stop = () => fs.writeFileSync(stopFile, '');
      process.on('SIGTERM', stop);
      process.on('SIGINT', stop);
      try {
        await runLaunch();
      } finally {
        fs.rmSync(readyFile, { force: true });
        fs.rmSync(lock, { force: true });
      }
      return;
    }

    case 'viewport':
      console.log(JSON.stringify(await rpc('viewport', { width: args.width, height: args.height })));
      return;

    case 'close':
      fs.writeFileSync(stopFile, '');
      return;

    case 'navigate':
      console.log(JSON.stringify(await rpc('navigate', { url: args.url })));
      return;

    case 'snapshot':
      console.log(await rpc('snapshot', {}));
      return;

    case 'screenshot':
      console.log(JSON.stringify(await rpc('screenshot', { path: args.path, fullpage: args.fullpage })));
      return;

    case 'annotate':
      console.log(JSON.stringify(await rpc('annotate', { path: args.path }), null, 2));
      return;

    case 'click':
      console.log(JSON.stringify(await rpc('click', { selector: resolveSelector() })));
      return;

    case 'type':
      console.log(JSON.stringify(await rpc('type', { selector: resolveSelector(), text: args.text })));
      return;

    case 'press':
      console.log(JSON.stringify(await rpc('press', { key: args.key })));
      return;

    case 'scroll':
      console.log(JSON.stringify(await rpc('scroll', { direction: args.direction })));
      return;

    case 'back':
      console.log(JSON.stringify(await rpc('back', {})));
      return;

    case 'axe':
      console.log(JSON.stringify(await rpc('axe', { tags: args.tags }), null, 2));
      return;

    case 'console': {
      const text = fs.existsSync(consoleLog) ? fs.readFileSync(consoleLog, 'utf8') : '';
      console.log(text.trim() || '(no console output captured)');
      if (args.clear === 'true') fs.writeFileSync(consoleLog, '');
      return;
    }

    default:
      console.error(`Unknown command: ${cmd}`);
      process.exit(1);
  }
}

main()
  .then(() => {
    if (cmd !== 'launch') process.exit(0);
  })
  .catch((err) => {
    console.error(err.stack || err.message);
    process.exit(1);
  });
