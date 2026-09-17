# Driver Command Reference

| Command | Purpose |
|---------|---------|
| `launch` | Start the persistent headless browser (run detached; blocks until `close`) |
| `close` | Signal the running browser to shut down |
| `navigate --url <url>` | Go to a URL |
| `viewport --width N --height N` | Set viewport for responsive/reflow checks |
| `snapshot` | Print a YAML-style ARIA tree (structural evidence, not an audit) |
| `screenshot [--path <file>] [--fullpage true]` | Plain screenshot, no annotation |
| `annotate [--path <file>]` | Screenshot with numbered element badges + `refs.json` for `--ref` lookups |
| `click --ref <N> \| --selector <css>` | Click an element |
| `type --ref <N> \| --selector <css> --text <str>` | Fill a field |
| `press --key <key>` | Press a keyboard key |
| `scroll [--direction up\|down]` | Scroll the page |
| `back` | Go back in browser history |
| `console [--clear true]` | Read (and optionally clear) captured console/page errors |
| `axe [--tags <comma-list>]` | Run an automated axe-core scan of the current page; defaults to `wcag2a,wcag2aa,wcag21aa,wcag22aa` tags. Used by the `accessibility-audit` skill; also useful for a quick a11y sanity check mid-dogfood-run. |

All commands take `--state-dir ./dogfood-output/.browser` — the same directory
passed to `launch`.
