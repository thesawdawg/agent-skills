# Portable skill authoring

Check the capabilities actually available in the session. Filesystem access, a shell, networking, image viewing, and delegation are separate requirements; none is universal. Write explicit success and stop conditions.

- **Prefer supported native tools; document shell fallbacks.** Web fetches use `curl`. "Look up a changelog" uses a registry HTTP API via `curl`, when a native fetch tool is unavailable. TLS/DNS checks use `curl`/`openssl`/`dig`. This is the portable baseline and it's deterministic.
- **Name a capability, then give the portable command.** Where a step benefits from a richer capability some harnesses have (viewing an image, delegating to a subagent, a built-in web search), say so — then give a shell fallback when the required executable exists. Never make the happy path depend on an unavailable tool.
- Name the capability (read a file, inspect an image) without assuming a host-specific tool.

### Capability mapping (what to write instead of a Claude-Code tool name)

| Need | Portable instruction to write |
|---|---|
| View a screenshot/image | "If your harness can view images, open the PNG; otherwise rely on the text accessibility-tree snapshot and note visual-only issues weren't assessed." |
| Fetch a web page / doc / changelog | `curl -sSL <url>` (then Read the file). Mention a richer web-fetch/browser as an optional upgrade. |
| Web search | Use native search when available; otherwise use a known HTTP API (npm registry, PyPI JSON, GitHub releases API) via `curl`; fall back to asking the user for a URL. |
| Delegate to a subagent | "If your harness supports delegation, dispatch a subagent; otherwise perform self-review in the main loop and label it honestly." |
| Ask the user something | Just ask in chat and wait for the reply. No special tool. |
| Deliver a file to the user | Give the exact file path in your final message; use a file-delivery capability only if the harness has one. |
| Track a todo list | Use the harness's task list if it has one; otherwise keep a checklist in a scratch `.md` file you Edit as you go. |

## Frontmatter

Required fields are `name` and `description` ( `name` ≤64 chars, lowercase/`a-z0-9-`; `description` ≤1024 chars, "what it does and when to use it"). Keep supported optional `license`, `compatibility`, `metadata`, and `allowed-tools` when useful; remove unsupported host-specific fields; fold any useful "use when…" text from `triggers` into `description`, since that's what the harness reads to decide when to surface the skill.

## Shell state and paths (the rule that matters most for small models)

**Shell calls may be stateless: variables and exports need not survive between calls.** A skill that sets `SKILL_DIR=...` in one step and uses `$SKILL_DIR` three steps later will hit an *empty* variable and fail in a way a small model won't diagnose. So skills here follow two rules:

1. **Outputs use an explicit run path** (`./dogfood-output`, `./pentest-engagement`, …). Repeat the project working directory explicitly; reuse existing outputs only when resuming intentionally. Never truncate an existing findings file. Do **not** `cd` into these dirs — that would break the relative paths. New runs must not overwrite previous evidence.

2. **The one thing that must be absolute — the skill's own install directory (where `scripts/` lives)** — is re-declared at the top of *every* Bash block that needs it, and the value is a literal absolute path the model resolved once:

   ```bash
   # Resolve once — checks known skill locations, unambiguous and fast:
   for d in "$HOME/.pi/agent/skills/<skill>" "$HOME/.agents/skills/<skill>" ".pi/skills/<skill>" ".agents/skills/<skill>" ./<skill>; do
     [ -f "$d/scripts/<file>" ] && printf 'DIR=%s\n' "$(cd "$d" && pwd)" && break
   done
   # Then in EVERY block that runs the script, re-set the literal path:
   DIR="/absolute/path/from/above"
   node "$DIR/scripts/thing.mjs" ...
   ```

   Do **not** use `git rev-parse --show-toplevel` to find a skill's files — the skill runs inside the *user's* repo, so that returns the wrong root. For a **sibling skill's** asset (e.g. `accessibility-audit` and `web-pentest` reuse `dogfood`'s driver), resolve the sibling with the same loop pointed at `dogfood`.

**Long-lived processes** (like the browser `launch`, which blocks until `close`) must be started **detached** so the Bash call returns, then confirmed by polling a log:

```bash
mkdir -p ./out/.browser
nohup node "$DIR/scripts/browser-driver.mjs" launch --state-dir ./out/.browser > ./out/.browser/launch.log 2>&1 &
for i in $(seq 1 20); do grep -q READY ./out/.browser/launch.log 2>/dev/null && { echo up; break; }; sleep 0.5; done
```

**Findings/append files use JSONL, not a JSON array** — one object per line, appended with a `cat >> file <<'EOF'` heredoc. Small models corrupt a growing JSON array (they must re-serialize the whole thing); a JSONL line append can't break earlier lines. Validate each line afterward with a `python3 -c "json.loads(...)"` loop.

## Writing steps for small models

- Number the steps. One action per step. State what success looks like ("when `launch` prints `READY`, the browser is up").
- Make each Bash block self-contained: because variables don't persist (see above), re-declare any absolute path the block needs at its top. Never rely on a variable set in an earlier block.
- Replace `{placeholder}` / `<PLACEHOLDER>` tokens with real values inline, and give a concrete example next to the first use (e.g. "for PR 42: `pull/42/head:pr-42`") so a small model doesn't run the placeholder verbatim.
- Make decision points explicit: "if none respond, ask the user to pick (a)/(b)/(c)."
- Put mandatory guardrails in their own callouts, and add a compact "STOP — do these first" block at the very top for anything safety-critical (e.g. web-pentest's authorization gate) so a skimming model can't miss it.
- Treat long reference-style skills as lookups, not linear scripts — say so at the top and point the model to the one matching section.

## Testing expectations

Bundled scripts must be run, not just eyeballed, before shipping (standalone parsers may expose `--selftest`; integrated helpers may use the repository test suite):
- Scripts with real logic (parsing, scope enforcement, anything security-relevant) have tests covering awkward inputs, not just the happy path.
- Actually execute them against deliberately awkward input (quotes in a URL, mixed-case hostnames, multiple matches, ANSI codes) — that's the difference between "looks right" and "verified."

## Security expectations

- Credential-like output (tokens, claim URLs, session cookies) is redacted by default; revealing it requires an explicit flag used only at the one step that needs the real value.
- Skills that touch real network targets (`web-pentest`) keep their authorization/scope guardrails intact on adaptation — tighten, never loosen.
- Skills that produce sensitive output (secrets, exploit payloads) prefer writing values to files and referencing the path, rather than pasting them into chat (some harnesses replay chat history through summarization/compaction).


For security assessments, use actual network/sandbox controls where needed.
Instructions alone do not enforce redirect, subrequest, or DNS scope. A missing
control is a blocked test, not authorization to relax the boundary.
