(() => {
'use strict';
const $ = (id) => document.getElementById(id);
const state = { docs: [], version: '', current: null, text: new Map(), mermaidReady: null, seq: 0 };
const THEMES = ['auto', 'light', 'dark'];
const CODE_LANG = { py: 'python', js: 'javascript', mjs: 'javascript', ts: 'typescript', tsx: 'typescript',
  jsx: 'javascript', sh: 'bash', rb: 'ruby', rs: 'rust', yml: 'yaml', patch: 'diff', html: 'xml', log: 'plaintext', txt: 'plaintext' };
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* storage unavailable */ } },
};

const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const slug = (s) => s.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '-');
const dark = () => document.documentElement.dataset.theme === 'dark';

function applyTheme() {
  const mode = THEMES.includes(store.get('lv_theme')) ? store.get('lv_theme') : 'auto';
  const resolved = mode === 'auto' ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : mode;
  document.documentElement.dataset.theme = resolved;
  $('theme').textContent = mode[0].toUpperCase() + mode.slice(1);
}

async function api(path) {
  const reply = await fetch(path, { credentials: 'same-origin' });
  if (!reply.ok) throw new Error(`${path}: ${reply.status}`);
  return reply;
}
const fetchText = async (id) => (await api(`/api/doc?id=${id}`)).text();

function highlight(code, lang) {
  if (lang && hljs.getLanguage(lang)) return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
  return esc(code);
}

function parseDelimited(text, sep) {
  const rows = []; let row = [], cell = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; } else if (c === '"') quoted = false; else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === sep) { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; row.push(cell); rows.push(row); row = []; cell = ''; }
    else cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows.filter((r) => r.some((x) => x !== ''));
}

function tableHtml(rows) {
  if (!rows.length) return '<p class="meta">Empty table.</p>';
  const head = rows[0].map((h, i) => `<th data-sort="${i}" tabindex="0" title="Sort">${esc(h)}</th>`).join('');
  const body = rows.slice(1).map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join('')}</tr>`).join('');
  return `<table class="sortable"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table><p class="meta">${rows.length - 1} rows</p>`;
}

function enableSorting(root) {
  root.querySelectorAll('table.sortable th').forEach((th) => {
    const sort = () => {
      const tbody = th.closest('table').tBodies[0], col = +th.dataset.sort;
      const dir = th.dataset.dir === 'asc' ? -1 : 1; th.dataset.dir = dir === 1 ? 'asc' : 'desc';
      const cmp = (a, b) => {
        const x = a.cells[col].textContent, y = b.cells[col].textContent;
        const nx = parseFloat(x), ny = parseFloat(y);
        return (isNaN(nx) || isNaN(ny) ? x.localeCompare(y) : nx - ny) * dir;
      };
      [...tbody.rows].sort(cmp).forEach((r) => tbody.appendChild(r));
    };
    th.addEventListener('click', sort);
    th.addEventListener('keydown', (e) => { if (e.key === 'Enter') sort(); });
  });
}

function markdownHtml(text) {
  const renderer = new marked.Renderer();
  renderer.html = (token) => esc(token.text || token.raw || '');
  renderer.code = ({ text: code, lang }) => {
    const name = (lang || '').split(/\s/)[0];
    if (name === 'mermaid') return `<div class="mermaid-box" data-src="${esc(code)}"></div>`;
    return `<pre><code class="hljs">${highlight(code, name)}</code></pre>`;
  };
  renderer.heading = function ({ tokens, depth }) {
    const inner = this.parser.parseInline(tokens);
    return `<h${depth} id="${esc(slug(inner))}">${inner}</h${depth}>`;
  };
  return marked.parse(text, { renderer, gfm: true, breaks: false });
}

function upgradeCallouts(root) {
  root.querySelectorAll('blockquote').forEach((bq) => {
    const first = bq.firstElementChild;
    const hit = first && /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*/i.exec(first.textContent);
    if (!hit) return;
    const kind = hit[1].toLowerCase();
    first.innerHTML = first.innerHTML.replace(/^\s*\[!\w+\]\s*(<br>)?\s*/i, '');
    const box = document.createElement('div');
    box.className = `callout ${kind}`;
    box.innerHTML = `<div class="ct">${kind}</div>`;
    while (bq.firstChild) box.appendChild(bq.firstChild);
    bq.replaceWith(box);
  });
}

function sanitizeLinks(root) {
  root.querySelectorAll('[href],[src]').forEach((el) => {
    for (const attr of ['href', 'src']) {
      const value = el.getAttribute(attr);
      if (value && /^\s*(javascript|vbscript|data:text\/html)/i.test(value)) el.removeAttribute(attr);
    }
  });
  root.querySelectorAll('a[href^="http"]').forEach((a) => { a.target = '_blank'; a.rel = 'noopener noreferrer'; });
}

function loadMermaid() {
  state.mermaidReady ||= new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = '/vendor/mermaid.min.js';
    script.onload = () => resolve(window.mermaid);
    script.onerror = () => reject(new Error('mermaid failed to load'));
    document.head.appendChild(script);
  });
  return state.mermaidReady;
}

async function renderMermaid(root) {
  const boxes = [...root.querySelectorAll('.mermaid-box')];
  if (!boxes.length) return;
  let mermaid;
  try { mermaid = await loadMermaid(); } catch (e) { boxes.forEach((b) => { b.innerHTML = `<p class="err">${esc(e.message)}</p>`; }); return; }
  mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark() ? 'dark' : 'default' });
  for (const [i, box] of boxes.entries()) {
    try {
      const { svg } = await mermaid.render(`mmd-${++state.seq}-${i}`, box.dataset.src);
      box.innerHTML = svg;
    } catch (e) {
      box.innerHTML = `<p class="err">Diagram error: ${esc(String(e.message || e).split('\n')[0])}</p><pre><code>${esc(box.dataset.src)}</code></pre>`;
      document.querySelectorAll('body > [id^="dmmd-"]').forEach((n) => n.remove());
    }
  }
}

function addCopyButtons(root) {
  root.querySelectorAll('pre').forEach((pre) => {
    const button = document.createElement('button');
    button.className = 'copy'; button.textContent = 'Copy';
    button.addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(pre.querySelector('code').innerText); button.textContent = 'Copied'; }
      catch { button.textContent = 'Press Ctrl+C'; }
      setTimeout(() => { button.textContent = 'Copy'; }, 1500);
    });
    pre.appendChild(button);
  });
}

function buildToc(root) {
  const toc = $('toc'); toc.textContent = '';
  const heads = [...root.querySelectorAll('h2, h3, h4')];
  heads.forEach((h) => {
    const a = document.createElement('a');
    a.href = `#${state.current}/${h.id}`; a.textContent = h.textContent; a.className = `l${h.tagName[1]}`;
    a.addEventListener('click', (e) => { e.preventDefault(); h.scrollIntoView(); });
    toc.appendChild(a);
  });
  if (!('IntersectionObserver' in window) || !heads.length) return;
  const links = new Map(heads.map((h, i) => [h, toc.children[i]]));
  const observer = new IntersectionObserver((entries) => {
    entries.filter((e) => e.isIntersecting).forEach((e) => {
      toc.querySelectorAll('.on').forEach((n) => n.classList.remove('on'));
      links.get(e.target).classList.add('on');
    });
  }, { rootMargin: '-60px 0px -75% 0px' });
  heads.forEach((h) => observer.observe(h));
}

async function renderDoc(meta, text) {
  const root = $('doc'), ext = meta.ext;
  let html;
  if (['md', 'markdown'].includes(ext)) html = markdownHtml(text);
  else if (['mmd', 'mermaid'].includes(ext)) html = `<div class="mermaid-box" data-src="${esc(text)}"></div>`;
  else if (ext === 'csv' || ext === 'tsv') html = tableHtml(parseDelimited(text, ext === 'tsv' ? '\t' : ','));
  else {
    let body = text, lang = CODE_LANG[ext] || ext;
    if (ext === 'json') { try { body = JSON.stringify(JSON.parse(text), null, 2); } catch { /* show raw */ } }
    html = `<pre><code class="hljs">${highlight(body, lang)}</code></pre>`;
  }
  const heading = ['md', 'markdown'].includes(ext) ? '' : `<h1>${esc(meta.name)}</h1>`;
  root.innerHTML = heading + html;
  upgradeCallouts(root); sanitizeLinks(root); addCopyButtons(root); enableSorting(root); buildToc(root);
  await renderMermaid(root);
}

async function show(id, anchor, keepScroll) {
  const meta = state.docs.find((d) => d.id === id) || state.docs[0];
  if (!meta) { $('doc').textContent = 'No documents.'; return; }
  state.current = meta.id;
  document.title = `${meta.name} · ${state.title}`;
  document.querySelectorAll('#docs a').forEach((a) => a.toggleAttribute('aria-current', +a.dataset.id === meta.id));
  document.querySelectorAll('#docs a[aria-current]').forEach((a) => a.setAttribute('aria-current', 'page'));
  const y = window.scrollY;
  try {
    const text = await fetchText(meta.id); state.text.set(meta.id, text.toLowerCase());
    await renderDoc(meta, text);
  } catch (e) { $('doc').innerHTML = `<p class="err">${esc(e.message)}</p>`; }
  document.body.classList.remove('nav-open');
  if (keepScroll) window.scrollTo(0, y);
  else if (anchor) document.getElementById(anchor)?.scrollIntoView();
  else window.scrollTo(0, 0);
}

function route(keepScroll = false) {
  const [id, anchor] = location.hash.slice(1).split('/');
  return show(id === '' || id === undefined ? (state.current ?? 0) : +id, anchor ? decodeURIComponent(anchor) : '', keepScroll);
}

function renderList() {
  const q = $('filter').value.trim().toLowerCase();
  const list = $('docs'); list.textContent = '';
  for (const d of state.docs) {
    const nameHit = d.name.toLowerCase().includes(q);
    const bodyHit = q && state.text.get(d.id)?.includes(q);
    if (q && !nameHit && !bodyHit) continue;
    const li = document.createElement('li'), a = document.createElement('a');
    a.href = `#${d.id}`; a.dataset.id = d.id; a.textContent = d.name;
    if (bodyHit && !nameHit) { const s = document.createElement('small'); s.textContent = 'content match'; a.appendChild(s); }
    if (d.id === state.current) a.setAttribute('aria-current', 'page');
    li.appendChild(a); list.appendChild(li);
  }
}

let loadedAll = false;
async function searchAll() {
  if (loadedAll) return;
  loadedAll = true;
  await Promise.all(state.docs.filter((d) => !state.text.has(d.id)).map(async (d) => {
    try { state.text.set(d.id, (await fetchText(d.id)).toLowerCase()); } catch { /* skip */ }
  }));
}

async function loadListing() {
  const data = await (await api('/api/docs')).json();
  state.docs = data.docs; state.version = data.version; state.title = data.title;
  $('title').textContent = data.title;
  renderList();
}

async function poll() {
  try {
    const { version } = await (await api('/api/version')).json();
    $('live').classList.remove('off');
    if (version !== state.version) {
      await loadListing(); state.text.clear(); loadedAll = false;
      await route(true);
    }
  } catch { $('live').classList.add('off'); }
}

async function init() {
  applyTheme();
  $('theme').addEventListener('click', () => {
    const now = store.get('lv_theme') || 'auto';
    store.set('lv_theme', THEMES[(THEMES.indexOf(now) + 1) % THEMES.length]);
    applyTheme(); route(true);
  });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { applyTheme(); route(true); });
  $('menu').addEventListener('click', () => document.body.classList.toggle('nav-open'));
  $('filter').addEventListener('focus', searchAll);
  $('filter').addEventListener('input', async () => { await searchAll(); renderList(); });
  addEventListener('hashchange', () => route());
  try { await loadListing(); } catch (e) { $('doc').innerHTML = `<p class="err">${esc(e.message)}. Open the full URL, including ?t=…, printed by viewer.py.</p>`; return; }
  await route();
  setInterval(poll, 2000);
}
init();
})();
