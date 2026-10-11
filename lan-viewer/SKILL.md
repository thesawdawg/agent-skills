---
name: lan-viewer
description: Serve markdown docs, code, diffs, JSON/CSV, and Mermaid diagrams as one themed, searchable web page with live reload, on localhost or (opt-in) the local network. Use when the user wants to view, browse, present, or share documents or session output in a browser or on another LAN device. Not for public hosting or deployment to the internet.
---

# LAN document viewer

Turn files into a navigable page: sidebar, table of contents, content search,
light/dark/auto theme, syntax highlighting, sortable CSV tables, Mermaid
diagrams, callouts (`> [!NOTE]`), copy buttons, print styles, phone layout, and
live reload when files change. Python 3.9+ stdlib only; libraries are vendored in
`assets/vendor/`, so viewing needs no internet.

## Workflow

1. Decide the content. For session output (a plan, findings, a diff, a table),
   write it to a file in a scratch directory first; the viewer serves files only.
   Reuse existing user files in place; do not copy or edit them.
2. Choose exposure. **Default is loopback only.** Pass `--lan` only when the user
   wants another device to view it, and say so: anyone on that network who gets
   the URL (it carries the token) can read every served file.
3. Start it detached from the loaded skill path (never the user's cwd), keeping
   the token in a private file rather than chat or logs. Set `FILES` to the paths
   to serve (space-separated, no spaces inside names; for example `./docs plan.md`); add `--lan` only if step 2 chose it:

   ```bash
   for d in "$HOME/.pi/agent/skills/lan-viewer" "$HOME/.agents/skills/lan-viewer" ".pi/skills/lan-viewer" ".agents/skills/lan-viewer" ./lan-viewer; do
     [ -f "$d/scripts/viewer.py" ] && printf 'DIR=%s\n' "$(cd "$d" && pwd)" && break
   done
   DIR="/absolute/path/from/above"
   FILES="./docs plan.md"
   mkdir -p -m 700 ./.lan-viewer
   # shellcheck disable=SC2086
   nohup python3 "$DIR/scripts/viewer.py" $FILES --title "Project docs" \
     > ./.lan-viewer/record.json 2> ./.lan-viewer/err.log &
   for i in $(seq 1 20); do [ -s ./.lan-viewer/record.json ] && break; sleep 0.5; done
   cat ./.lan-viewer/record.json ./.lan-viewer/err.log
   ```

   Success is one JSON line with `url` (carries the `?t=` token), `pid`, `files`
   and `warnings`; otherwise `err.log` explains. Give the user the `url`; do not
   paste it into commits, shared logs, or other channels, and do not commit
   `./.lan-viewer`.
4. Edit the served files to update the page; it reloads itself within ~2 seconds.
5. Stop it with `kill <pid>` (from `record.json`) when finished, then delete
   `./.lan-viewer`. It also exits after `--idle-timeout`
   minutes without requests (default 120; `0` disables). Stop only a server you
   started.

## Boundaries

- Serves only files named at startup (directories expand once, recursively,
  skipping dot-entries, `node_modules`, `.git`, builds); request paths never
  select files. Symlinks inside a directory that leave it are skipped.
  Credential-like files (`.env*`, keys, `*credential*`/`*secret*`/`*token*` data
  files, kubeconfig, tfstate, SSH private keys) and files over 5 MB are refused
  with a warning, even when named explicitly. Do not rename around the filter.
- Do not serve a directory the user has not agreed to share, especially with `--lan`.
- Markdown raw HTML is shown as text, scripts are blocked by CSP, and diagrams use
  Mermaid strict mode. This is for trusted-network viewing, not the public internet;
  there is no TLS. For public sharing, use a separate, explicitly authorized deploy.
- Markdown images are not served (the page loads nothing but its own assets);
  inline diagrams as Mermaid or link to the file instead.
- Formats: `.md`, `.json`, `.csv/.tsv`, `.diff/.patch`, `.mmd`, and common source
  or config files (highlighted). Other explicitly named files render as plain text.

Verify with `bash scripts/preflight.sh` from this skill directory (no network,
no server left running) or `python3 scripts/viewer.py --selftest`.
