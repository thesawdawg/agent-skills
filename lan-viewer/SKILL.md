---
name: lan-viewer
description: Serve markdown docs, code, diffs, JSON/CSV, and Mermaid diagrams as one themed, searchable web page with live reload, on localhost or (opt-in) the local network. Use when the user wants to view, browse, present, or share documents or session output in a browser or on another LAN device. Not for public hosting or deployment to the internet.
---

# LAN document viewer

Turn files into a navigable page: sidebar, table of contents, content search,
light/dark/auto theme, syntax highlighting, sortable CSV tables, Mermaid
diagrams, callouts (`> [!NOTE]`), copy buttons, print styles, phone layout, and
live reload when files change. Python 3 stdlib only; libraries are vendored in
`assets/vendor/`, so viewing needs no internet.

## Workflow

1. Decide the content. For session output (a plan, findings, a diff, a table),
   write it to a file in a scratch directory first; the viewer serves files only.
   Reuse existing user files in place; do not copy or edit them.
2. Choose exposure. **Default is loopback only.** Pass `--lan` only when the user
   wants another device to view it, and say so: anyone on that network who gets
   the URL (it carries the token) can read every served file.
3. Start it in the background from the loaded skill path, never the user's cwd:

   ```bash
   VIEWER="/absolute/path/to/lan-viewer/scripts/viewer.py"
   python3 "$VIEWER" ./docs plan.md --title "Project docs" [--lan] [--port N]
   ```

   Stdout is one JSON line: `url` (with `?t=` token), `pid`, `files`, `warnings`.
   Give the user the `url`; keep the token out of logs, commits, and shared chat.
4. Edit the served files to update the page; it reloads itself within ~2 seconds.
5. Stop it with `kill <pid>` when finished. It also exits after `--idle-timeout`
   minutes without requests (default 120; `0` disables). Stop only a server you
   started.

## Boundaries

- Serves only files named at startup (directories expand once, recursively,
  skipping dot-entries, `node_modules`, `.git`, builds); request paths never
  select files. Credential-like files (`.env*`, `*.pem`, `*.key`, SSH keys) and
  files over 5 MB are refused with a warning, even when named explicitly.
- Do not serve a directory the user has not agreed to share, especially with `--lan`.
- Markdown raw HTML is shown as text, scripts are blocked by CSP, and diagrams use
  Mermaid strict mode. This is for trusted-network viewing, not the public internet;
  there is no TLS. For public sharing, use a separate, explicitly authorized deploy.
- Formats: `.md`, `.json`, `.csv/.tsv`, `.diff/.patch`, `.mmd`, and common source
  or config files (highlighted). Other explicitly named files render as plain text.

Verify with `bash scripts/preflight.sh` from this skill directory (no network,
no server left running) or `python3 scripts/viewer.py --selftest`.
