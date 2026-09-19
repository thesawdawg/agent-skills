/* D.A.V.E. ops console — vanilla JS, no build, no CDN. */
"use strict";

const TOKEN = document.querySelector('meta[name="dave-token"]').content;

/* ------------------------------------------------------------------ http */

async function apiGet(path) {
  const res = await fetch(path, { headers: { "X-Dave-Token": TOKEN } });
  const body = await res.json().catch(() => ({ status: "error", errors: [{ message: "unreadable response" }] }));
  if (body.status !== "success") {
    const msg = (body.errors && body.errors[0] && body.errors[0].message) || `HTTP ${res.status}`;
    throw new Error(msg);
  }
  return body.data;
}

async function apiPost(path, payload) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Dave-Token": TOKEN },
    body: JSON.stringify(payload || {}),
  });
  const body = await res.json().catch(() => ({ status: "error", errors: [{ message: "unreadable response" }] }));
  if (body.status !== "success") {
    const msg = (body.errors && body.errors[0] && body.errors[0].message) || `HTTP ${res.status}`;
    throw new Error(msg);
  }
  return body.data;
}

/* ------------------------------------------------------------------ util */

function esc(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function toast(msg, isError) {
  const el = document.createElement("div");
  el.className = "toast" + (isError ? " error" : "");
  el.textContent = msg;
  document.getElementById("toasts").appendChild(el);
  setTimeout(() => el.remove(), 5000);
}

/* In-page modal. confirmModal() resolves true on confirm, false on cancel —
   Esc, backdrop click, and the Cancel button all cancel; Enter confirms and
   Tab is trapped inside the dialog. */
function confirmModal({ title, body, details, confirmLabel, danger }) {
  return new Promise((resolve) => {
    const backdrop = document.createElement("div");
    backdrop.className = "modal-backdrop";
    backdrop.innerHTML = `
      <div class="modal" role="dialog" aria-modal="true" aria-label="${esc(title)}">
        <h2>${esc(title)}</h2>
        <div class="modal-body">${inline(body)}</div>
        ${details ? `<div class="modal-details">${esc(details)}</div>` : ""}
        <div class="modal-actions">
          <button class="btn" data-m="cancel">Cancel</button>
          <button class="btn ${danger ? "danger" : "primary"}" data-m="ok">${esc(confirmLabel || "Confirm")}</button>
        </div>
      </div>`;
    const dialog = backdrop.querySelector(".modal");
    const okBtn = backdrop.querySelector('[data-m="ok"]');
    const close = (result) => {
      document.removeEventListener("keydown", onKey, true);
      backdrop.remove();
      resolve(result);
    };
    const onKey = (ev) => {
      if (ev.key === "Escape") { ev.preventDefault(); close(false); }
      else if (ev.key === "Enter") { ev.preventDefault(); close(true); }
      else if (ev.key === "Tab") {
        const focusables = dialog.querySelectorAll("button, [href], input, select, textarea");
        const first = focusables[0], last = focusables[focusables.length - 1];
        if (ev.shiftKey && document.activeElement === first) { ev.preventDefault(); last.focus(); }
        else if (!ev.shiftKey && document.activeElement === last) { ev.preventDefault(); first.focus(); }
      }
    };
    backdrop.addEventListener("mousedown", (ev) => { if (ev.target === backdrop) close(false); });
    okBtn.addEventListener("click", () => close(true));
    backdrop.querySelector('[data-m="cancel"]').addEventListener("click", () => close(false));
    document.addEventListener("keydown", onKey, true);
    document.body.appendChild(backdrop);
    okBtn.focus();
  });
}

/* Info-only modal (About). Same chrome, a single Close button. */
function infoModal(title, bodyHtml) {
  return new Promise((resolve) => {
    const backdrop = document.createElement("div");
    backdrop.className = "modal-backdrop";
    backdrop.innerHTML = `
      <div class="modal" role="dialog" aria-modal="true" aria-label="${esc(title)}">
        <h2>${esc(title)}</h2>
        <div class="modal-body">${bodyHtml}</div>
        <div class="modal-actions"><button class="btn primary" data-m="ok">Close</button></div>
      </div>`;
    const okBtn = backdrop.querySelector('[data-m="ok"]');
    const close = () => {
      document.removeEventListener("keydown", onKey, true);
      backdrop.remove();
      resolve();
    };
    const onKey = (ev) => {
      if (ev.key === "Escape" || ev.key === "Enter") { ev.preventDefault(); close(); }
      else if (ev.key === "Tab") { ev.preventDefault(); okBtn.focus(); }
    };
    backdrop.addEventListener("mousedown", (ev) => { if (ev.target === backdrop) close(); });
    okBtn.addEventListener("click", close);
    document.addEventListener("keydown", onKey, true);
    document.body.appendChild(backdrop);
    okBtn.focus();
  });
}

async function act(path, payload, confirmSpec) {
  if (confirmSpec) {
    const spec = typeof confirmSpec === "string" ? { title: "Confirm", body: confirmSpec } : confirmSpec;
    if (!await confirmModal(spec)) return null;
  }
  try {
    const data = await apiPost(path, payload);
    toast((data.output || "done").trim());
    return data;
  } catch (e) {
    toast(e.message, true);
    return null;
  }
}

/* Sync actions, shared by the Overview card and the Sync & Config view. */
async function syncRemoteInfo() {
  try {
    const cfg = await apiGet("/api/config");
    const s = (cfg && cfg.sync) || {};
    return { remote: s.remote || "(none configured)", branch: s.branch || "main",
             enabled: !!s.enabled };
  } catch (e) {
    return { remote: "(unreadable)", branch: "main", enabled: false };
  }
}

function wireSyncButtons(root, rerender) {
  const pull = root.querySelector('[data-sync="pull"]');
  const push = root.querySelector('[data-sync="push"]');
  const statusBtn = root.querySelector('[data-sync="status"]');
  const out = root.querySelector("#sync-out");
  if (pull) pull.onclick = async () => {
    const ok = await act("/api/sync", { action: "pull" }, {
      title: "Sync pull",
      body: "Runs `dave.sh sync pull` — rebases local state onto the remote (autostash). A conflict aborts back to a clean tree and reports.",
      confirmLabel: "Pull",
    });
    if (ok) rerender();
  };
  if (push) push.onclick = async () => {
    const info = await syncRemoteInfo();
    const ok = await act("/api/sync", { action: "push" }, {
      title: "Sync push",
      body: "Runs `dave.sh sync push` — publishes the state tree to the remote. This is the same user-run boundary as the CLI.",
      details: `git add -A\ncommit "sync: <host> <date>"  (if dirty)\npush → ${info.remote} (branch ${info.branch})`,
      confirmLabel: "Push",
      danger: true,
    });
    if (ok) rerender();
  };
  if (statusBtn) statusBtn.onclick = async () => {
    if (out) {
      out.textContent = "fetching…";
      try { out.textContent = (await apiGet("/api/sync")).output; }
      catch (e) { out.textContent = e.message; }
    }
  };
}

function ageOf(iso) {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const days = Math.floor((Date.now() - t) / 86400000);
  return days;
}

function relAge(stamp) {
  // state stamps look like "2026-09-14T23:33:58-05:00 (source)" — the
  // parenthetical is prose, not part of the timestamp.
  const days = ageOf(String(stamp).split(" ")[0]);
  if (days == null) return { text: "unknown", days: null };
  if (days <= 0) return { text: "today", days };
  if (days === 1) return { text: "yesterday", days };
  return { text: `${days}d ago`, days };
}

function fmtMinutes(m) {
  if (m == null) return "—";
  const h = Math.floor(m / 60), mm = Math.floor(m % 60);
  return h > 0 ? `${h}h${mm}m` : `${mm}m`;
}

/* Inline markdown marks. Links only become anchors for obviously-safe hrefs —
   a brief is user content and `javascript:` must never reach the DOM. */
const SAFE_HREF = /^(https?:)?\/\/|^\/|^#|^[\w./-]+$/i;
function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\*([^*]+)\*/g, "<em>$1</em>")
    .replace(/(^|[\s(])_([^_]+)_(?=$|[\s).,;:])/g, "$1<em>$2</em>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (m, label, href) =>
      SAFE_HREF.test(href) ? `<a href="${href}" rel="noopener">${label}</a>` : label);
}

/* Minimal markdown → HTML: headings, lists, tables, fences, inline marks. */
function md(text) {
  const lines = String(text || "").replace(/<!--[\s\S]*?-->/g, "").split("\n");
  let html = "", inCode = false, inList = false, inTable = false, para = [];
  const flushPara = () => {
    if (para.length) { html += `<p>${inline(para.join(" "))}</p>`; para = []; }
  };
  const closeBlocks = () => {
    flushPara();
    if (inList) { html += "</ul>"; inList = false; }
    if (inTable) { html += "</tbody></table>"; inTable = false; }
  };
  const tableRow = (line, header) => {
    const cells = line.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim());
    const tag = header ? "th" : "td";
    return `<tr>${cells.map((c) => `<${tag}>${inline(c)}</${tag}>`).join("")}</tr>`;
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^```/.test(line.trim())) {
      if (inCode) { html += "</code></pre>"; inCode = false; }
      else { closeBlocks(); html += "<pre class=\"code\"><code>"; inCode = true; }
      continue;
    }
    if (inCode) { html += esc(line) + "\n"; continue; }
    const t = line.trim();
    if (!t) { closeBlocks(); continue; }
    if (/^\|.*\|$/.test(t) && i + 1 < lines.length && /^\|[\s:|-]+\|$/.test(lines[i + 1].trim())) {
      closeBlocks();
      html += `<table><thead>${tableRow(t, true)}</thead><tbody>`;
      inTable = true; i++;
      continue;
    }
    if (inTable && /^\|.*\|$/.test(t)) { html += tableRow(t, false); continue; }
    if (inTable) { html += "</tbody></table>"; inTable = false; }
    const h = t.match(/^(#{1,4})\s+(.*)/);
    if (h) { closeBlocks(); html += `<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`; continue; }
    const li = t.match(/^[-*]\s+(?:\[[ xX]\]\s*)?(.*)/);
    if (li) { flushPara(); if (!inList) { html += "<ul>"; inList = true; } html += `<li>${inline(li[1])}</li>`; continue; }
    const ol = t.match(/^\d+\.\s+(.*)/);
    if (ol) { flushPara(); if (!inList) { html += "<ul>"; inList = true; } html += `<li>${inline(ol[1])}</li>`; continue; }
    if (t.startsWith(">")) { closeBlocks(); html += `<blockquote>${inline(t.slice(1).trim())}</blockquote>`; continue; }
    para.push(t);
  }
  closeBlocks();
  return `<div class="md">${html}</div>`;
}

/* ------------------------------------------------------------- chrome */

let currentView = "overview";
const viewParams = {};

async function refreshHeader() {
  try {
    const o = await apiGet("/api/overview");
    const user = o.user || {};
    const addr = user.address_as || user.name || "";
    document.getElementById("hdr-user").innerHTML = addr ? `<b>${esc(user.name || addr)}</b>${user.address_as ? " · " + esc(addr) : ""}` : "";
    const f = o.focus;
    if (f) {
      const mins = f.started ? Math.max(0, Math.floor((Date.now() - Date.parse(f.started)) / 60000)) : null;
      document.getElementById("hdr-focus").innerHTML =
        `▶ <b>${esc(f.ref)}</b> — ${esc(f.label)} <span class="muted">(${fmtMinutes(mins)})</span>` +
        (o.on_list ? "" : ' <span class="badge amber">off-list</span>');
    } else {
      document.getElementById("hdr-focus").innerHTML = '<span class="muted">no focus</span>';
    }
    document.getElementById("hdr-mission").innerHTML = o.active_mission
      ? `mission: <b>${esc(o.active_mission)}</b>` : "";
    const intakeEl = document.getElementById("hdr-intake");
    if (o.last_intake) {
      const age = relAge(o.last_intake);
      const stale = age.days != null && age.days > 2;
      intakeEl.innerHTML = `last intake <span title="${esc(o.last_intake)}"${stale ? ' class="warn"' : ""}>${esc(age.text)}</span>` +
        (stale ? ' <span class="badge amber">stale</span>' : "");
    } else {
      intakeEl.innerHTML = '<span class="muted">no intake yet</span>';
    }
  } catch (e) {
    /* header stays stale rather than flashing errors */
  }
}

async function navigate(view) {
  currentView = view;
  document.querySelectorAll(".nav-btn").forEach((b) =>
    b.classList.toggle("active", b.dataset.view === view));
  await render();
}

async function render() {
  const main = document.getElementById("main");
  main.innerHTML = '<p class="muted">loading…</p>';
  try {
    await VIEWS[currentView](main);
  } catch (e) {
    main.innerHTML = `<div class="card bad">${esc(e.message)}</div>`;
  }
}

document.querySelectorAll(".nav-btn").forEach((b) =>
  b.addEventListener("click", () => navigate(b.dataset.view)));

/* SSE: refresh the open view (and header) when the state tree changes. */
(function connectEvents() {
  const dot = document.getElementById("sse-dot");
  const es = new EventSource("/api/events");
  let timer = null;
  es.onopen = () => dot.classList.add("live");
  es.onerror = () => dot.classList.remove("live");
  es.addEventListener("changed", () => {
    clearTimeout(timer);
    timer = setTimeout(() => { refreshHeader(); render(); }, 500);
  });
})();

setInterval(refreshHeader, 30000);

/* ------------------------------------------------------------- view: overview */

function prioItems(items, overCap) {
  if (!items.length) return '<p class="muted">(empty)</p>';
  return items.map((it) => `
    <div class="prio-item${overCap ? " bad" : ""}">
      <span class="rank">${it.rank}.</span>
      ${it.ref ? `<span class="ref">${esc(it.ref)}</span> — ` : ""}${inline(it.text)}
    </div>`).join("");
}

async function viewOverview(main) {
  const o = await apiGet("/api/overview");
  const secs = o.priorities.sections;
  const maxNow = o.priorities_config.max_now;
  const f = o.focus;
  const overCap = secs.now.length > maxNow;

  const syncCard = o.sync_enabled ? `
    <div class="card">
      <div class="section-title"><h2>Sync</h2>
        <span class="hdr-spacer"></span>
        <button class="btn small" data-sync="status">status</button>
        <button class="btn small" data-sync="pull">pull</button>
        <button class="btn small danger" data-sync="push">push</button>
      </div>
      <p class="help">~/.dave as a git repo on a private remote. Pull runs at session start; push is user-run only.</p>
      <pre id="sync-out" class="code muted">(fetch status to see ahead/behind/dirty)</pre>
    </div>` : "";

  const focusCard = `
    <div class="card">
      <div class="section-title"><h2>Focus</h2></div>
      <p class="help">What the session is pointed at right now; drift is measured against this. Detours stack under it.</p>
      ${f ? `
        <p class="mono"><b>${esc(f.ref)}</b> — ${esc(f.label)}
          ${f.project ? ` <span class="badge blue">${esc(f.project)}</span>` : ""}
          ${o.on_list ? ' <span class="badge green">on-list</span>' : ' <span class="badge amber">off-list</span>'}
        </p>
        <p class="muted">elapsed ${fmtMinutes(o.focus_minutes)} · started ${esc(f.started || "")}</p>
        ${o.focus_stack && o.focus_stack.length
          ? `<p class="muted">stacked under it: ${o.focus_stack.map((s) => esc(s.ref)).reverse().join(", ")}</p>` : ""}
        ${o.next_note ? `<p>next: ${esc(o.next_note)}</p>` : ""}
      ` : '<p class="muted">(nothing focused)</p>'}
      <div class="form-row">
        <button class="btn small" data-act="focus-set">set</button>
        <button class="btn small" data-act="focus-push">push</button>
        <button class="btn small" data-act="focus-pop">pop</button>
        <button class="btn small danger" data-act="focus-clear">clear</button>
        <button class="btn small" data-act="next-set">next note</button>
        <button class="btn small" data-act="log">log line</button>
      </div>
    </div>`;

  const prioCols = ["now", "next", "blocked", "someday"].map((name) => {
    const items = secs[name] || [];
    const cap = name === "now"
      ? ` <span class="badge ${overCap ? "cap-over" : ""}">${items.length}/${maxNow}</span>` : "";
    const help = {
      now: "At most max_now items — anything not here is drift until this list says otherwise.",
      next: "Ordered. The top item is what gets promoted when Now empties.",
      blocked: "What it waits on and who owes it. If nobody owes anything, it belongs in Next.",
      someday: "Real but not now — keeps Next honest without throwing things away.",
    }[name];
    return `<div class="card prio-col">
      <div class="section-title"><h2>${name}</h2>${cap}</div>
      <p class="help">${help}</p>
      ${prioItems(items, name === "now" && overCap)}
    </div>`;
  }).join("");

  const due = (o.promises_due_soon || []).map((p) => `
    <tr><td class="mono">${esc(p.id)}</td><td class="nowrap">${esc(p.due)}</td>
    <td>${esc(p.who)} — ${esc(p.what)}</td><td class="mono muted">${esc(p.ref || "")}</td></tr>`).join("");

  const logEntries = (o.today.entries || []).map((e) => `
    <div class="log-entry"><span class="time">${esc(e.time)}</span>
      ${e.ref ? `<span class="ref">${esc(e.ref)}</span>` : ""}${esc(e.text)}</div>`).join("");

  main.innerHTML = `
    <h1>Overview</h1>
    ${focusCard}
    ${syncCard}
    <div class="grid cols-4">${prioCols}</div>
    <div class="grid cols-2">
      <div class="card">
        <h2>Promised, due soon</h2>
        <p class="help">Open commitments due within review.promise_horizon_days — the first ranking factor is a promise made to someone.</p>
        ${due ? `<table>${due}</table>` : '<p class="muted">(nothing due soon)</p>'}
      </div>
      <div class="card">
        <h2>Today — ${esc(o.today.date)}</h2>
        <p class="help">Today's log, stamped with the focus ref at write time.</p>
        ${logEntries || '<p class="muted">(nothing logged yet)</p>'}
        <h2 style="margin-top:12px">Parked</h2>
        <p class="help">Captured detours — written down so they stop pulling focus.</p>
        <p><span class="badge ${o.parked_open_count ? "blue" : ""}">${o.parked_open_count} open</span>
           <span class="muted">· ${o.open_charges_count} charge(s) outstanding</span></p>
      </div>
    </div>`;

  wireSyncButtons(main, () => { refreshHeader(); render(); });

  main.querySelector('[data-act="focus-set"]').onclick = async () => {
    const ref = window.prompt("Focus ref (e.g. RM-4471):"); if (!ref) return;
    const label = window.prompt("Label:", ref) || ref;
    if (await act("/api/focus", { action: "set", ref, label })) { refreshHeader(); render(); }
  };
  main.querySelector('[data-act="focus-push"]').onclick = async () => {
    const ref = window.prompt("Detour ref:"); if (!ref) return;
    const label = window.prompt("Label:", ref) || ref;
    if (await act("/api/focus", { action: "push", ref, label })) { refreshHeader(); render(); }
  };
  main.querySelector('[data-act="focus-pop"]').onclick = async () => {
    if (await act("/api/focus", { action: "pop" }, {
      title: "Pop focus",
      body: "Runs `dave.sh focus pop` — banks this segment, closes the detour, and returns to the focus stacked under it with its clock restarted.",
      confirmLabel: "Pop",
    })) { refreshHeader(); render(); }
  };
  main.querySelector('[data-act="focus-clear"]').onclick = async () => {
    if (await act("/api/focus", { action: "clear" }, {
      title: "Clear focus",
      body: "Runs `dave.sh focus clear` — banks the open segment, then clears the focus and anything stacked under it.",
      confirmLabel: "Clear",
      danger: true,
    })) { refreshHeader(); render(); }
  };
  main.querySelector('[data-act="next-set"]').onclick = async () => {
    const ref = window.prompt("Ref for the next note:", f ? f.ref : ""); if (!ref) return;
    const text = window.prompt("Where you left off:"); if (!text) return;
    if (await act("/api/next", { action: "set", ref, text })) render();
  };
  main.querySelector('[data-act="log"]').onclick = async () => {
    const text = window.prompt("Log line:"); if (!text) return;
    if (await act("/api/log", { text })) render();
  };
}

/* ---------------------------------------------------------- view: priorities */

async function viewPriorities(main) {
  const p = await apiGet("/api/priorities");
  const secs = p.sections;
  const cols = ["now", "next", "blocked", "someday"].map((name) => `
    <div class="card prio-col"><h2>${name}</h2>${prioItems(secs[name] || [])}</div>`).join("");
  main.innerHTML = `
    <h1>Priorities</h1>
    <div class="grid cols-4">${cols}</div>
    <div class="card">
      <div class="section-title">
        <h2>Edit priorities.md</h2>
        <span class="muted">last reconciled: ${esc(p.reconciled || "never")}</span>
      </div>
      <p class="help">The single ranked list, hand-editable. Refs join focus, logs, missions, and drift — renaming one breaks the join.</p>
      <textarea id="prio-editor" rows="22">${esc(p.raw)}</textarea>
      <div class="form-row"><button id="prio-save" class="btn primary">Save</button></div>
    </div>`;
  main.querySelector("#prio-save").onclick = async () => {
    const markdown = main.querySelector("#prio-editor").value;
    if (await act("/api/priorities", { markdown }, {
      title: "Replace priorities.md",
      body: "Runs `dave.sh priorities set` — atomically replaces the whole file with the editor contents. There is no undo; the old list is overwritten.",
      confirmLabel: "Replace",
      danger: true,
    })) render();
  };
}

/* ------------------------------------------------------------ view: missions */

const VERDICT_BADGE = { trust: "green", partial: "amber", rerun: "purple", discard: "red" };

async function viewMissions(main) {
  const [m, a] = await Promise.all([apiGet("/api/missions"), apiGet("/api/assignments")]);
  const slug = viewParams.mission || null;
  const rows = (m.missions || []).slice().sort((x, y) =>
    (x.status === "open" ? 0 : 1) - (y.status === "open" ? 0 : 1) || x.slug.localeCompare(y.slug));
  const o = await apiGet("/api/overview");
  const active = o.active_mission;

  const listRows = rows.map((mi) => `
    <tr class="mission-row${mi.slug === slug ? " selected" : ""}" data-slug="${esc(mi.slug)}">
      <td class="mono">${mi.slug === active ? "★ " : ""}${esc(mi.slug)}${mi.brief_missing ? ' <span class="badge amber">no brief</span>' : ""}</td>
      <td><span class="badge ${mi.status === "open" ? "green" : ""}">${esc(mi.status)}</span></td>
      <td>${esc(mi.project || "-")}</td><td class="mono">${esc(mi.ref || "-")}</td>
      <td>${mi.open_count || 0} open</td><td class="muted">${(mi.assignments || []).length} charges</td>
    </tr>`).join("");

  const roster = Object.entries(a.roster || {}).map(([agent, s]) => {
    const total = Math.max(1, s.total);
    const segs = Object.entries(s.by_verdict).map(([v, n]) =>
      `<span style="width:${(n / total) * 100}%;background:var(--${VERDICT_BADGE[v] === "green" ? "green" : VERDICT_BADGE[v] === "amber" ? "amber" : VERDICT_BADGE[v] === "purple" ? "purple" : "red"})" title="${esc(v)}: ${n}"></span>`).join("");
    return `<div class="card roster-card"${s.enabled === false ? ' style="opacity:.45" title="disabled in config roster"' : ""}>
      <b class="mono">${esc(agent)}</b>${s.default_model ? ` <span class="badge">${esc(s.default_model)}</span>` : ""}
      <div class="muted">${s.total} charge(s) · ${s.open} open</div>
      <div class="bar stacked verdict-bar">${segs || '<span style="width:100%;background:var(--bg3)"></span>'}</div>
      <div class="muted">verdicts: ${Object.entries(s.by_verdict).map(([v, n]) => `${v} ×${n}`).join(", ") || "—"}</div>
      <div class="muted">models used: ${s.models.join(", ") || "—"}</div>
    </div>`;
  }).join("");

  main.innerHTML = `
    <h1>Missions &amp; Agents</h1>
    <div class="card">
      <h2>Missions</h2>
      <p class="help">Delegations with a brief. Open first, ★ is the active mission — assign defaults to it. "no brief" means registered in missions.json without a brief file.</p>
      <table><thead><tr><th>slug</th><th>status</th><th>project</th><th>ref</th><th></th><th></th></tr></thead>
      <tbody>${listRows || '<tr><td colspan="6" class="muted">(no missions)</td></tr>'}</tbody></table>
      <div class="form-row">
        <div><label for="m-new-name">new mission</label><input id="m-new-name" type="text" placeholder="name"></div>
        <div><label for="m-new-ref">ref</label><input id="m-new-ref" type="text" placeholder="RM-…"></div>
        <div><label for="m-new-proj">project</label><input id="m-new-proj" type="text" placeholder="slug"></div>
        <button id="m-new-btn" class="btn small">create</button>
      </div>
    </div>
    <div id="mission-detail"></div>
    <div class="card"><h2>Roster</h2>
      <p class="help">Agents from config.roster with their default model; charges and verdicts come from assignments.jsonl.</p></div>
    <div class="grid cols-4">${roster}</div>`;

  main.querySelectorAll(".mission-row").forEach((tr) => tr.addEventListener("click", () => {
    viewParams.mission = tr.dataset.slug;
    render();
  }));
  main.querySelector("#m-new-btn").onclick = async () => {
    const name = main.querySelector("#m-new-name").value.trim();
    if (!name) { toast("name required", true); return; }
    const payload = { action: "new", name };
    const ref = main.querySelector("#m-new-ref").value.trim();
    const proj = main.querySelector("#m-new-proj").value.trim();
    if (ref) payload.ref = ref;
    if (proj) payload.project = proj;
    if (await act("/api/missions", payload)) { viewParams.mission = null; render(); }
  };

  if (slug) await renderMissionDetail(main.querySelector("#mission-detail"), slug);
}

async function renderMissionDetail(el, slug) {
  const data = await apiGet(`/api/missions?slug=${encodeURIComponent(slug)}`);
  const mi = (data.missions || []).find((x) => x.slug === slug) || {};
  const assigns = (mi.assignments || []).map((r) => `
    <tr>
      <td class="mono">${esc(r.id)}</td><td>${esc(r.agent)}${r.model ? ` <span class="muted">(${esc(r.model)})</span>` : ""}</td>
      <td>${esc(r.charge)}</td>
      <td class="nowrap muted">${r.returned ? esc(String(r.returned).slice(0, 10)) : "—"}</td>
      <td>${r.verdict ? `<span class="badge ${VERDICT_BADGE[r.verdict] || ""}">${esc(r.verdict)}</span>` : '<span class="badge blue">open</span>'}</td>
      <td class="muted">${esc(r.summary || "")}</td>
    </tr>`).join("");

  const openRows = (mi.assignments || []).filter((r) => r.verdict == null);
  el.innerHTML = `
    <div class="card">
      <div class="section-title">
        <h2>${esc(slug)}</h2>
        <span class="badge ${mi.status === "open" ? "green" : ""}">${esc(mi.status || "")}</span>
        <span class="hdr-spacer"></span>
        <button id="md-open" class="btn small">make active</button>
        <button id="md-close" class="btn small danger">close</button>
      </div>
      ${data.brief_missing
        ? '<p class="muted">(no brief file on disk — registered in missions.json only)</p>'
        : md(data.brief || "")}
      <h3>Assignments</h3>
      <table><thead><tr><th>id</th><th>agent</th><th>charge</th><th>returned</th><th>verdict</th><th>summary</th></tr></thead>
      <tbody>${assigns || '<tr><td colspan="6" class="muted">(nothing delegated yet)</td></tr>'}</tbody></table>
      ${openRows.length ? `
        <h3>Record verdict</h3>
        <div class="form-row">
          <div><label for="md-rec-id">charge</label>
            <select id="md-rec-id">${openRows.map((r) => `<option>${esc(r.id)}</option>`).join("")}</select></div>
          <div><label for="md-rec-verdict">verdict</label>
            <select id="md-rec-verdict"><option>trust</option><option>partial</option><option>rerun</option><option>discard</option></select></div>
          <div><label for="md-rec-summary">summary</label><input id="md-rec-summary" type="text"></div>
          <button id="md-rec-btn" class="btn small">record</button>
        </div>` : ""}
      <h3>Assign</h3>
      <div class="form-row">
        <div><label for="md-as-agent">agent</label><input id="md-as-agent" type="text" placeholder="scout"></div>
        <div><label for="md-as-charge">charge</label><input id="md-as-charge" type="text" size="50"></div>
        <div><label for="md-as-model">model</label><input id="md-as-model" type="text" placeholder="optional"></div>
        <button id="md-as-btn" class="btn small">assign</button>
      </div>
    </div>`;

  el.querySelector("#md-open").onclick = async () => {
    if (await act("/api/missions", { action: "open", slug })) { refreshHeader(); render(); }
  };
  el.querySelector("#md-close").onclick = async () => {
    const outcome = window.prompt("Outcome (optional):") || "";
    if (await act("/api/missions", { action: "close", slug, outcome }, {
      title: `Close mission ${slug}`,
      body: `Runs \`dave.sh mission close ${slug}\` — marks the mission closed. Any charge still open is noted as closed without a recorded verdict.`,
      confirmLabel: "Close mission",
      danger: true,
    })) { refreshHeader(); render(); }
  };
  const recBtn = el.querySelector("#md-rec-btn");
  if (recBtn) recBtn.onclick = async () => {
    const payload = {
      action: "record",
      id: el.querySelector("#md-rec-id").value,
      verdict: el.querySelector("#md-rec-verdict").value,
      summary: el.querySelector("#md-rec-summary").value.trim(),
    };
    if (await act("/api/missions", payload)) render();
  };
  el.querySelector("#md-as-btn").onclick = async () => {
    const agent = el.querySelector("#md-as-agent").value.trim();
    const charge = el.querySelector("#md-as-charge").value.trim();
    if (!agent || !charge) { toast("agent and charge required", true); return; }
    const model = el.querySelector("#md-as-model").value.trim();
    const payload = { action: "assign", slug, agent, charge };
    if (model) payload.model = model;
    if (await act("/api/missions", payload)) render();
  };
}

/* ------------------------------------------------------------ view: projects */

async function viewProjects(main) {
  const data = await apiGet("/api/projects");
  const rows = (data.projects || []).map((p) => {
    const s = p.scan || {};
    return `<tr>
      <td class="mono">${esc(p.slug)}</td>
      <td><span class="badge ${p.status === "active" ? "green" : p.status === "archived" ? "" : "amber"}">${esc(p.status)}</span></td>
      <td>${esc(p.cadence)}</td>
      <td class="mono">${s.repo ? esc(s.branch) : '<span class="muted">—</span>'}</td>
      <td>${s.repo ? `${s.dirty}/${s.untracked}` : '<span class="muted">—</span>'}</td>
      <td>${s.days_since_commit == null ? '<span class="muted">—</span>' : `${s.days_since_commit}d`}</td>
      <td>${s.ahead || 0}</td>
      <td>${s.stale_branches || 0}</td>
      <td class="mono muted">${esc((p.refs || []).join(", "))}</td>
      <td class="muted">${esc(p.goal || "")}</td>
      <td class="nowrap muted">${esc((p.last_touched || "").slice(0, 10) || "—")}</td>
      <td class="nowrap">
        <select class="p-status" data-slug="${esc(p.slug)}">
          ${["active", "paused", "maintenance", "archived"].map((st) => `<option${st === p.status ? " selected" : ""}>${st}</option>`).join("")}
        </select>
        <button class="btn small p-link" data-slug="${esc(p.slug)}">link</button>
        <button class="btn small p-unlink" data-slug="${esc(p.slug)}">unlink</button>
        <button class="btn small p-touch" data-slug="${esc(p.slug)}">touch</button>
      </td>
    </tr>`;
  }).join("");

  main.innerHTML = `
    <h1>Projects</h1>
    <div class="card">
      <div class="section-title"><h2>Registered</h2>
        <span class="muted">scanned ${esc(data.scanned_at || "never")}</span>
        <span class="hdr-spacer"></span>
        <button id="p-rescan" class="btn small">rescan (fresh)</button></div>
      <p class="help">Durable containers the ranked list has no room for — a directory, a goal, a cadence, and the refs that serve it. Git state comes from scan-cache.json.</p>
      <table><thead><tr><th>slug</th><th>status</th><th title="how often it should move before the weekly sweep calls it slipping">cadence</th><th>branch</th><th title="uncommitted changed files / untracked files">dirty/untr</th><th title="days since the last commit">commit</th><th title="unpushed commits, measured without a fetch">ahead</th><th title="local branches with no commit in 30 days">stale br</th><th>refs</th><th>goal</th><th title="last explicit touch or banked focus segment">touched</th><th>actions</th></tr></thead>
      <tbody>${rows || '<tr><td colspan="12" class="muted">(no projects registered)</td></tr>'}</tbody></table>
    </div>
    <div class="card">
      <h2>Register project</h2>
      <p class="help">Registration is not activity — last_touched stays empty until real work banks against it.</p>
      <div class="form-row">
        <div><label for="p-add-path">path</label><input id="p-add-path" type="text" size="34"></div>
        <div><label for="p-add-name">name</label><input id="p-add-name" type="text"></div>
        <div><label for="p-add-cad">cadence</label>
          <select id="p-add-cad"><option>daily</option><option selected>weekly</option><option>monthly</option><option>dormant</option></select></div>
        <div><label for="p-add-goal">goal</label><input id="p-add-goal" type="text"></div>
        <button id="p-add-btn" class="btn small primary">register</button>
      </div>
    </div>`;

  main.querySelector("#p-rescan").onclick = async () => {
    if (await act("/api/scan", {})) render();
  };
  main.querySelectorAll(".p-status").forEach((sel) => sel.addEventListener("change", async () => {
    if (await act("/api/projects", { action: "status", slug: sel.dataset.slug, status: sel.value })) render();
  }));
  main.querySelectorAll(".p-link").forEach((b) => b.addEventListener("click", async () => {
    const ref = window.prompt(`Link which ref to ${b.dataset.slug}?`); if (!ref) return;
    if (await act("/api/projects", { action: "link", slug: b.dataset.slug, ref })) render();
  }));
  main.querySelectorAll(".p-unlink").forEach((b) => b.addEventListener("click", async () => {
    const ref = window.prompt(`Unlink which ref from ${b.dataset.slug}?`); if (!ref) return;
    if (await act("/api/projects", { action: "unlink", slug: b.dataset.slug, ref })) render();
  }));
  main.querySelectorAll(".p-touch").forEach((b) => b.addEventListener("click", async () => {
    if (await act("/api/projects", { action: "touch", slug: b.dataset.slug })) render();
  }));
  main.querySelector("#p-add-btn").onclick = async () => {
    const path = main.querySelector("#p-add-path").value.trim();
    if (!path) { toast("path required", true); return; }
    const payload = { action: "add", path, cadence: main.querySelector("#p-add-cad").value };
    const name = main.querySelector("#p-add-name").value.trim();
    const goal = main.querySelector("#p-add-goal").value.trim();
    if (name) payload.name = name;
    if (goal) payload.goal = goal;
    if (await act("/api/projects", payload)) render();
  };
}

/* ---------------------------------------------------------------- view: time */

async function viewTime(main) {
  const q = viewParams.time || {};
  const params = new URLSearchParams();
  if (q.ref) params.set("ref", q.ref);
  if (q.project) params.set("project", q.project);
  if (q.since) params.set("since", q.since);
  const data = await apiGet(`/api/time?${params}`);
  const segs = data.segments || [];
  const byRef = {};
  segs.forEach((s) => {
    const g = byRef[s.ref] = byRef[s.ref] || { total: 0, verified: 0, unverified: 0, n: 0, label: s.label };
    g.total += s.minutes || 0; g.n += 1;
    if (s.log_lines > 0) g.verified += s.minutes || 0; else g.unverified += s.minutes || 0;
  });
  const maxTotal = Math.max(1, ...Object.values(byRef).map((g) => g.total), data.open ? data.open.minutes : 0);
  const rows = Object.entries(byRef).sort((a, b) => b[1].total - a[1].total).map(([ref, g]) => `
    <tr><td class="mono">${esc(ref)}</td><td class="muted">${esc(g.label || "")}</td>
      <td class="nowrap">${fmtMinutes(g.total)}</td><td>${g.n}</td>
      <td>${fmtMinutes(g.verified)} / ${fmtMinutes(g.unverified)}</td>
      <td><div class="bar"><span style="width:${(g.total / maxTotal) * 100}%"></span></div></td></tr>`).join("");
  const openRow = data.open ? `
    <tr><td class="mono">${esc(data.open.ref)}</td><td class="muted">open now</td>
      <td class="nowrap">${fmtMinutes(data.open.minutes)}${data.open.capped ? ' <span class="badge amber">capped</span>' : ""}</td>
      <td>—</td><td>—</td>
      <td><div class="bar"><span style="width:${(data.open.minutes / maxTotal) * 100}%;background:var(--amber)"></span></div></td></tr>` : "";

  main.innerHTML = `
    <h1>Time</h1>
    <div class="card">
      <p class="help">Segments banked each time focus changes. "Unverified" = elapsed minutes with no log line inside them — reported, never folded into the total. An open segment held overnight is capped and flagged, not asserted.</p>
      <div class="form-row">
        <div><label for="t-ref">ref</label><input id="t-ref" type="text" value="${esc(q.ref || "")}"></div>
        <div><label for="t-proj">project</label><input id="t-proj" type="text" value="${esc(q.project || "")}"></div>
        <div><label for="t-since">since</label><input id="t-since" type="date" value="${esc(q.since || "")}"></div>
        <button id="t-apply" class="btn small">apply</button>
      </div>
    </div>
    <div class="card">
      <table><thead><tr><th>ref</th><th>label</th><th>total</th><th>segs</th><th>verified/unverified</th><th></th></tr></thead>
      <tbody>${openRow}${rows || '<tr><td colspan="6" class="muted">(nothing recorded)</td></tr>'}</tbody></table>
    </div>`;
  main.querySelector("#t-apply").onclick = () => {
    viewParams.time = {
      ref: main.querySelector("#t-ref").value.trim(),
      project: main.querySelector("#t-proj").value.trim(),
      since: main.querySelector("#t-since").value,
    };
    render();
  };
}

/* ------------------------------------------------------------ view: timeline */

async function viewTimeline(main) {
  const days = viewParams.days || 7;
  const [logs, promises, parked, drift, intake] = await Promise.all([
    apiGet(`/api/log?days=${days}`),
    apiGet("/api/promises"),
    apiGet("/api/parked"),
    apiGet(`/api/drift?days=${days}`),
    apiGet("/api/intake"),
  ]);
  const today = new Date().toISOString().slice(0, 10);

  const dayGroups = (logs || []).map((d) => `
    <div class="day-group"><div class="day-head">${esc(d.date)}</div>
      ${(d.entries || []).map((e) => `
        <div class="log-entry"><span class="time">${esc(e.time)}</span>
          ${e.ref ? `<span class="ref">${esc(e.ref)}</span>` : ""}${esc(e.text)}</div>`).join("")
        || '<p class="muted">(no entries)</p>'}
    </div>`).join("");

  const promiseRows = (promises || []).map((p) => {
    const overdue = p.status === "open" && p.due < today;
    return `<tr>
      <td class="mono">${esc(p.id)}</td><td class="nowrap">${esc(p.due)}${overdue ? ' <span class="badge red">overdue</span>' : ""}</td>
      <td>${esc(p.who)} — ${esc(p.what)}</td>
      <td><span class="badge ${p.status === "kept" ? "green" : p.status === "missed" ? "red" : "blue"}">${esc(p.status)}</span></td>
      <td class="nowrap">${p.status === "open" ? `
        <button class="btn small pr-keep" data-id="${esc(p.id)}">keep</button>
        <button class="btn small pr-miss" data-id="${esc(p.id)}">miss</button>
        <button class="btn small pr-move" data-id="${esc(p.id)}">move</button>` : ""}</td>
    </tr>`;
  }).join("");

  const parkedRows = (parked.open || []).map((p) => `
    <tr><td>${esc(p.index)}</td><td>${esc(p.text)}</td>
      <td class="nowrap muted">${esc(p.parked || "")}${p.while_on ? ` · ${esc(p.while_on)}` : ""}</td>
      <td><button class="btn small pk-done" data-index="${p.index}">retire</button></td></tr>`).join("");
  const retiredRows = (parked.retired || []).map((p) => `
    <tr class="muted"><td></td><td><s>${esc(p.text)}</s></td>
      <td class="nowrap">${esc(p.retired || "")}</td><td></td></tr>`).join("");

  const driftRows = (drift || []).map((e) => `
    <tr><td class="nowrap muted">${esc((e.at || "").slice(0, 16).replace("T", " "))}</td>
      <td>${esc(e.kind)}</td><td>→ ${esc(e.outcome)}</td>
      <td class="mono muted">${esc(e.ref || "")} ${esc(e.project || "")}</td></tr>`).join("");

  const intakeRows = (intake.files || []).map((f) =>
    `<tr><td class="mono"><a href="#" class="in-file" data-file="${esc(f)}">${esc(f)}</a></td></tr>`).join("");

  main.innerHTML = `
    <h1>Timeline</h1>
    <div class="card"><div class="form-row">
      <div><label for="tl-days">days</label>
        <select id="tl-days">${[3, 7, 14, 30].map((d) => `<option${d === days ? " selected" : ""}>${d}</option>`).join("")}</select></div>
    </div></div>
    <div class="grid cols-2">
      <div class="card"><h2>Log</h2>
        <p class="help">The append-only record, grouped by day; entries carry the focus ref at write time.</p>
        ${dayGroups || '<p class="muted">(nothing logged)</p>'}</div>
      <div>
        <div class="card"><h2>Promises</h2>
          <p class="help">Commitments made to someone — outranks deadlines in the priority model. Overdue is flagged, not hidden.</p>
          <table>${promiseRows || '<tr><td class="muted">(no commitments)</td></tr>'}</table>
          <div class="form-row">
            <div><label for="pr-who">who</label><input id="pr-who" type="text"></div>
            <div><label for="pr-what">what</label><input id="pr-what" type="text"></div>
            <div><label for="pr-due">due</label><input id="pr-due" type="text" placeholder="friday / 2026-…"></div>
            <div><label for="pr-ref">ref</label><input id="pr-ref" type="text"></div>
            <button id="pr-add" class="btn small">add</button>
          </div>
        </div>
        <div class="card"><h2>Parking lot</h2>
          <p class="help">Detours captured without acting on them. Retire marks one done; old open items rot into the weekly review.</p>
          <table>${parkedRows || '<tr><td class="muted">(nothing parked)</td></tr>'}${retiredRows}</table>
          <div class="form-row">
            <div><label for="pk-text">park something</label><input id="pk-text" type="text" size="40"></div>
            <button id="pk-add" class="btn small">park</button>
          </div>
        </div>
        <div class="card"><h2>Drift</h2>
          <p class="help">Resolved drift episodes — a single nudge is noise, six into the same project is a pattern.</p>
          <table>${driftRows || '<tr><td class="muted">(no drift in the window)</td></tr>'}</table>
          <div class="form-row">
            <div><label for="dr-kind">kind</label>
              <select id="dr-kind"><option>unlisted</option><option>third-repo</option><option>parked-resurfaced</option><option>no-focus</option></select></div>
            <div><label for="dr-out">outcome</label>
              <select id="dr-out"><option>parked</option><option>promoted</option><option>continued</option></select></div>
            <div><label for="dr-ref">ref</label><input id="dr-ref" type="text"></div>
            <div><label for="dr-proj">project</label><input id="dr-proj" type="text"></div>
            <button id="dr-add" class="btn small">record</button>
          </div>
        </div>
        <div class="card"><h2>Intake archive</h2>
          <p class="help">Raw boards pasted in by hand, archived verbatim so intake stays auditable.</p>
          <table>${intakeRows || '<tr><td class="muted">(nothing archived)</td></tr>'}</table>
          <div id="in-view"></div>
          <div class="form-row">
            <div><label for="in-src">archive a board — source</label><input id="in-src" type="text"></div>
            <div><label for="in-text">text</label><input id="in-text" type="text" size="40"></div>
            <button id="in-add" class="btn small">archive</button>
          </div>
        </div>
      </div>
    </div>`;

  main.querySelector("#tl-days").onchange = () => { viewParams.days = Number(main.querySelector("#tl-days").value); render(); };
  main.querySelectorAll(".pr-keep").forEach((b) => b.onclick = async () => {
    if (await act("/api/promise", { action: "keep", id: b.dataset.id })) render();
  });
  main.querySelectorAll(".pr-miss").forEach((b) => b.onclick = async () => {
    if (await act("/api/promise", { action: "miss", id: b.dataset.id }, {
      title: `Mark ${b.dataset.id} missed`,
      body: `Runs \`dave.sh promise miss ${b.dataset.id}\` — closes the commitment as missed. It stays in the record; a miss is data, not deletion.`,
      confirmLabel: "Mark missed",
      danger: true,
    })) render();
  });
  main.querySelectorAll(".pr-move").forEach((b) => b.onclick = async () => {
    const due = window.prompt(`New due date for ${b.dataset.id}:`); if (!due) return;
    if (await act("/api/promise", { action: "move", id: b.dataset.id, due })) render();
  });
  main.querySelector("#pr-add").onclick = async () => {
    const payload = {
      action: "add",
      who: main.querySelector("#pr-who").value.trim(),
      what: main.querySelector("#pr-what").value.trim(),
      due: main.querySelector("#pr-due").value.trim(),
    };
    const ref = main.querySelector("#pr-ref").value.trim();
    if (ref) payload.ref = ref;
    if (!payload.who || !payload.what || !payload.due) { toast("who/what/due required", true); return; }
    if (await act("/api/promise", payload)) render();
  };
  main.querySelectorAll(".pk-done").forEach((b) => b.onclick = async () => {
    if (await act("/api/parked/done", { index: Number(b.dataset.index) })) render();
  });
  main.querySelector("#pk-add").onclick = async () => {
    const text = main.querySelector("#pk-text").value.trim();
    if (!text) { toast("text required", true); return; }
    if (await act("/api/park", { text })) render();
  };
  main.querySelector("#dr-add").onclick = async () => {
    const payload = {
      kind: main.querySelector("#dr-kind").value,
      outcome: main.querySelector("#dr-out").value,
    };
    const ref = main.querySelector("#dr-ref").value.trim();
    const proj = main.querySelector("#dr-proj").value.trim();
    if (ref) payload.ref = ref;
    if (proj) payload.project = proj;
    if (await act("/api/drift/record", payload)) render();
  };
  main.querySelectorAll(".in-file").forEach((a) => a.onclick = async (ev) => {
    ev.preventDefault();
    try {
      const d = await apiGet(`/api/intake?file=${encodeURIComponent(a.dataset.file)}`);
      main.querySelector("#in-view").innerHTML = `<h3>${esc(d.file)}</h3><pre class="code">${esc(d.content)}</pre>`;
    } catch (e) { toast(e.message, true); }
  });
  main.querySelector("#in-add").onclick = async () => {
    const source = main.querySelector("#in-src").value.trim();
    const text = main.querySelector("#in-text").value;
    if (!source || !text.trim()) { toast("source and text required", true); return; }
    if (await act("/api/intake", { source, text })) render();
  };
}

/* -------------------------------------------------------------- view: review */

async function viewReview(main) {
  const days = viewParams.reviewDays || 7;
  const r = await apiGet(`/api/review?days=${days}`);
  const today = r.today || new Date().toISOString().slice(0, 10);
  const slipping = (r.projects || []).filter((p) => p.slipping).sort((a, b) => (b.days_quiet || 0) - (a.days_quiet || 0));
  const overdue = (r.promises || []).filter((p) => p.due < today).sort((a, b) => a.due.localeCompare(b.due));
  const dueSoon = (r.promises || []).filter((p) => p.due >= today).sort((a, b) => a.due.localeCompare(b.due));
  const owed = (r.missions || []).filter((m) => ((m.oldest_open_days || 0) >= 2) || ((m.days || 0) > 7))
    .sort((a, b) => (b.oldest_open_days || 0) - (a.oldest_open_days || 0));
  const fine = (r.projects || []).filter((p) => !p.slipping);
  const driftBy = {};
  (r.drift || []).forEach((e) => { driftBy[e.kind] = (driftBy[e.kind] || 0) + 1; });
  const driftInto = {};
  (r.drift || []).forEach((e) => { if (e.project) driftInto[e.project] = (driftInto[e.project] || 0) + 1; });
  const topInto = Object.entries(driftInto).sort((a, b) => b[1] - a[1])[0];

  let html = `<h1>Review</h1>
    <div class="card">
      <p class="help">Computed facts only — cadence vs. real activity, overdue promises, ungraded charges. Judgment stays yours.</p>
      <div class="form-row">
      <div><label for="rv-days">days</label>
        <select id="rv-days">${[7, 14, 30].map((d) => `<option${d === days ? " selected" : ""}>${d}</option>`).join("")}</select></div>
      <span class="muted">Since ${esc(r.window.since)}: ${fmtMinutes(r.time.total)} recorded${r.time.unverified ? ` (${fmtMinutes(r.time.unverified)} unverified)` : ""}.</span>
    </div></div>`;

  if (slipping.length || overdue.length) {
    html += `<div class="card"><h2 class="bad">Slipping</h2>
      <p class="help">Worst first: overdue commitments, then projects quieter than their cadence allows.</p><ul>`;
    overdue.forEach((p) => { html += `<li><b>${esc(p.who)}</b> — ${esc(p.what)}, due ${esc(p.due)} <span class="badge red">OVERDUE</span></li>`; });
    slipping.forEach((p) => {
      html += `<li><b class="mono">${esc(p.slug)}</b> — ${esc(p.cadence)} cadence, nothing for ${p.days_quiet}d${p.dirty ? `, ${p.dirty} uncommitted file(s)` : ""}</li>`;
    });
    html += "</ul></div>";
  }
  if (owed.length) {
    html += `<div class="card"><h2 class="warn">Owed</h2>
      <p class="help">Charges sent out and never graded, or missions that went quiet.</p><ul>`;
    owed.forEach((m) => {
      html += m.open_charges > 0
        ? `<li><b class="mono">${esc(m.slug)}</b> — ${m.open_charges} charge(s) outstanding, oldest sent ${m.oldest_open_days}d ago</li>`
        : `<li><b class="mono">${esc(m.slug)}</b> — open, but nothing has moved in ${m.days}d</li>`;
    });
    html += "</ul></div>";
  }
  if ((r.parked || []).length || (r.adhoc || []).length) {
    html += `<div class="card"><h2 class="warn">Rotting</h2>
      <p class="help">Parked items past the review threshold and ad-hoc items that should have become tickets.</p><ul>`;
    if ((r.parked || []).length) {
      const oldest = (r.parked || []).slice().sort((a, b) => a.parked.localeCompare(b.parked))[0];
      html += `<li>${r.parked.length} parked item(s) older than the review threshold — oldest: ${esc(oldest.text)}</li>`;
    }
    (r.adhoc || []).forEach((a) => { html += `<li><b class="mono">${esc(a.ref)}</b> first logged ${a.days}d ago and still has no ticket</li>`; });
    html += "</ul></div>";
  }
  if (fine.length) {
    html += `<div class="card"><h2 class="ok">Quiet and fine</h2>
      <p class="help">A sweep that only lists problems stops being read — this section is load-bearing.</p><p>${
      fine.map((p) => `<span class="mono">${esc(p.slug)}</span> (${esc(p.status === "active" ? p.cadence : p.status)})`).join(", ")
    }</p></div>`;
  }
  if ((r.drift || []).length) {
    html += `<div class="card"><h2>Drift</h2>
      <p class="help">Reported as a pattern, not a scolding.</p><p>${r.drift.length} drift call(s): ${
      Object.entries(driftBy).map(([k, n]) => `${esc(k)} ×${n}`).join(", ")
    }${topInto && topInto[1] >= 2 ? ` — ${topInto[1]} of them into <span class="mono">${esc(topInto[0])}</span>` : ""}</p></div>`;
  }
  html += `<div class="card"><h2>Needs your judgment</h2>
    <p class="help">What the script cannot decide — it hands this over rather than guessing.</p>`;
  if (r.blocked && r.blocked.trim()) {
    html += `<p>Blocked items — which of these has nobody chased?</p><pre class="code">${esc(r.blocked)}</pre>`;
  } else {
    html += `<p class="muted">Nothing is marked Blocked.</p>`;
  }
  if (dueSoon.length) {
    html += `<p>Coming due:</p><ul>${dueSoon.map((p) => `<li>${esc(p.who)} — ${esc(p.what)}, due ${esc(p.due)}</li>`).join("")}</ul>`;
  }
  html += `<p class="muted">What actually closed this week is not recorded anywhere — read the log and the list rather than trusting a summary of it.</p></div>`;

  main.innerHTML = html;
  main.querySelector("#rv-days").onchange = () => { viewParams.reviewDays = Number(main.querySelector("#rv-days").value); render(); };
}

/* ---------------------------------------------------------- view: sync/config */

async function viewSync(main) {
  const health = await apiGet("/api/health");
  const cfg = await apiGet("/api/config");
  const syncCfg = (cfg && cfg.sync) || {};
  const enabled = !!syncCfg.enabled;
  const noSyncTip = "Sync not configured — run `dave.sh sync setup <remote-url>` first";
  main.innerHTML = `
    <h1>Sync &amp; Config</h1>
    <div class="card">
      <div class="section-title"><h2>Sync</h2>
        <span class="badge ${enabled ? "green" : ""}">${enabled ? "enabled" : "not configured"}</span>
        <span class="hdr-spacer"></span>
        <button class="btn small" data-sync="status">status</button>
        <button class="btn small" data-sync="pull"${enabled ? "" : ` disabled title="${esc(noSyncTip)}"`}>pull</button>
        <button class="btn small danger" data-sync="push"${enabled ? "" : ` disabled title="${esc(noSyncTip)}"`}>push</button>
      </div>
      <p class="help">~/.dave as a git repo on a private remote: ${esc(syncCfg.remote || "(none configured)")}${syncCfg.branch ? ` (branch ${esc(syncCfg.branch)})` : ""}. Pull runs at session start; push is user-run only — the button is the boundary.</p>
      <pre id="sync-out" class="code muted">(fetch status to see ahead/behind/dirty)</pre>
    </div>
    <div class="card"><h2>Config (redacted)</h2>
      <p class="help">config.json verbatim, with anything named like a secret redacted before it leaves the server.</p>
      <pre class="code">${esc(JSON.stringify(cfg, null, 2))}</pre></div>
    <div class="card"><h2>Health</h2>
      <p class="help">What the dashboard is reading — the state root it serves and whether init has run.</p>
      <p class="mono">dave_home: ${esc(health.dave_home)}</p>
      <p class="mono">schema_version: ${esc(health.schema_version)} · setup: ${health.setup}</p>
    </div>`;
  wireSyncButtons(main, render);
}

/* -------------------------------------------------------------------- boot */

const VIEWS = {
  overview: viewOverview,
  priorities: viewPriorities,
  missions: viewMissions,
  projects: viewProjects,
  time: viewTime,
  timeline: viewTimeline,
  review: viewReview,
  sync: viewSync,
};

document.getElementById("hdr-about-btn").addEventListener("click", () => {
  infoModal("About this dashboard", `
    <p>A loopback-only view of <span class="mono">~/.dave</span> — the server binds 127.0.0.1 and nothing leaves the machine.</p>
    <p>Reads come straight from the state files; <strong>every write runs <span class="mono">dave.sh</span></strong>, the same commands you'd type, so the state layer stays the only writer.</p>
    <p>Views refresh themselves when the state tree changes (server-sent events); the dot in the header is the connection.</p>
    <h3>Verdict colors</h3>
    <table class="legend">
      <tr><td><span class="badge green">trust</span></td><td>correct, complete, verified — folded in</td></tr>
      <tr><td><span class="badge amber">partial</span></td><td>right direction, incomplete — a human finishes it</td></tr>
      <tr><td><span class="badge red">rerun</span></td><td>wrong approach — redo with feedback</td></tr>
      <tr><td><span class="badge">discard</span></td><td>useless — start over</td></tr>
    </table>
    <h3>Status badges</h3>
    <p><span class="badge green">enabled/active</span> <span class="badge red">closed/overdue</span> <span class="badge amber">paused/stale</span> <span class="badge">open/neutral</span> — badges carry text so status never rides on color alone.</p>`);
});

refreshHeader();
render();
