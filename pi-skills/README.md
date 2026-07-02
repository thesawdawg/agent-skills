# pi-skills

Harness-portable skills, written **pi-first** — for the [pi coding agent](https://github.com/earendil-works/pi) (`@mariozechner/pi-coding-agent`) and any harness whose core is just **Read / Write / Edit / Bash**. They also run under richer harnesses (Claude Code, Codex CLI, Amp, Droid), which have everything pi has plus more.

Some skills here are pi-adapted copies of skills that live at this repo's root (`dogfood`, `dependabot-validator`, `pr-grill-me`); the root copies are left as-is for their original environment. Others are adapted from [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)'s `optional-skills` tree. This file records the conventions all of them follow.

## Design target: the four core tools

pi's core is exactly four tools — **Read, Write, Edit, Bash** — and it self-extends from there. Skills here are written so that a small model, with only those four tools, can execute them start to finish. Concretely that means:

- **Prefer Bash for anything external.** Web fetches use `curl`. "Look up a changelog" uses a registry HTTP API via `curl`, not a search tool. TLS/DNS checks use `curl`/`openssl`/`dig`. This is the portable baseline and it's deterministic.
- **Name a capability, then give the portable command.** Where a step benefits from a richer capability some harnesses have (viewing an image, delegating to a subagent, a built-in web search), say so — then give the Bash/core-tool fallback that always works. Never make the happy path depend on a tool pi doesn't have.
- **`Read` is a core tool**, so "read the file with Read" / "open it" is fine everywhere. Only *image* viewing needs a fallback — see below.

### Capability mapping (what to write instead of a Claude-Code tool name)

| Need | Portable instruction to write |
|---|---|
| View a screenshot/image | "If your harness can view images, open the PNG; otherwise rely on the text accessibility-tree snapshot and note visual-only issues weren't assessed." |
| Fetch a web page / doc / changelog | `curl -sSL <url>` (then Read the file). Mention a richer web-fetch/browser as an optional upgrade. |
| Web search | Avoid it. Hit a known HTTP API instead (npm registry, PyPI JSON, GitHub releases API) via `curl`; fall back to asking the user for a URL. |
| Delegate to a subagent | "If your harness supports delegation, dispatch a subagent; otherwise run it as a fresh focused pass in the main loop." |
| Ask the user something | Just ask in chat and wait for the reply. No special tool. |
| Deliver a file to the user | Give the exact file path in your final message; use a file-delivery capability only if the harness has one. |
| Track a todo list | Use the harness's task list if it has one; otherwise keep a checklist in a scratch `.md` file you Edit as you go. |

## Frontmatter

Only `name` and `description` (pi's required fields: `name` ≤64 chars, lowercase/`a-z0-9-`; `description` ≤1024 chars, "what it does and when to use it"). Drop upstream extras (`version`, `platforms`, `metadata.*`, `triggers`, `toolsets`) on import; fold any useful "use when…" text from `triggers` into `description`, since that's what the harness reads to decide when to surface the skill.

## Referencing bundled scripts and sibling skills

Never assume the shell's current working directory: a skill runs from inside the **user's** project, not from where the skill is installed. Resolve bundled files from the skill's own directory. At the top of any script-using workflow, set:

```bash
# SKILL_DIR = the directory containing THIS SKILL.md — the path the agent loaded it from.
SKILL_DIR="/abs/path/to/this/skill"
node "$SKILL_DIR/scripts/thing.mjs" ...
```

Do **not** use `git rev-parse --show-toplevel` to find a skill's files — the skill runs inside the user's repo, so that returns the *wrong* root. For a **sibling skill's** asset (e.g. `adversarial-ux-test` and `web-pentest` reuse `dogfood`'s browser driver), reference it relative to `SKILL_DIR` and check it exists:

```bash
DOGFOOD_DRIVER="$SKILL_DIR/../dogfood/scripts/browser-driver.mjs"
[ -f "$DOGFOOD_DRIVER" ] || echo "install the dogfood skill as a sibling first" >&2
```

For a skill's own multi-step workflow that creates a working directory, keep it as a variable (`OUT=...`, `ENGAGEMENT=...`) and reference `$VAR/subpath` throughout — do **not** `cd` into it, or later `$VAR/foo` paths silently break.

## Writing steps for small models

- Number the steps. One action per step. State what success looks like ("when `launch` prints `READY`, the browser is up").
- Give exact, copy-pasteable commands with the variables already defined earlier in the skill — don't leave `{placeholder}` tokens for the model to fill from imagination.
- Make decision points explicit: "if none respond, ask the user to pick (a)/(b)/(c)."
- Put mandatory guardrails in their own callouts (e.g. web-pentest's authorization gate) so they can't be skimmed past.

## Testing expectations

Bundled scripts must be run, not just eyeballed, before shipping:
- Scripts with real logic (parsing, scope enforcement, anything security-relevant) ship with a `--selftest` mode covering awkward inputs, not just the happy path.
- Actually execute them against deliberately awkward input (quotes in a URL, mixed-case hostnames, multiple matches, ANSI codes) — that's the difference between "looks right" and "verified."

## Security expectations

- Credential-like output (tokens, claim URLs, session cookies) is redacted by default; revealing it requires an explicit flag used only at the one step that needs the real value.
- Skills that touch real network targets (`web-pentest`) keep their authorization/scope guardrails intact on adaptation — tighten, never loosen.
- Skills that produce sensitive output (secrets, exploit payloads) prefer writing values to files and referencing the path, rather than pasting them into chat (some harnesses replay chat history through summarization/compaction).

## Skills in this directory

| Skill | Origin | Notes |
|---|---|---|
| `dogfood` | pi-adapted copy of root `../dogfood` | Bundles the Playwright `browser-driver.mjs`; anchor skill the two below depend on. |
| `dependabot-validator` | pi-adapted copy of root `../dependabot-validator` | Changelog lookups via `curl` to registry APIs instead of a search tool. |
| `pr-grill-me` | pi-adapted copy of root `../pr-grill-me` | git-only; handles non-GitHub remotes. |
| `adversarial-ux-test` | hermes-agent `optional-skills/dogfood/adversarial-ux-test` | Reuses the sibling `dogfood` driver. |
| `rest-graphql-debug` | hermes-agent `optional-skills/software-development/rest-graphql-debug` | Pure `curl` + Python via Bash. |
| `web-pentest` | hermes-agent `optional-skills/security/web-pentest` | Authorization/scope guardrails; reuses sibling `dogfood` driver. |
| `cloudflare-temporary-deploy` | hermes-agent `optional-skills/web-development/cloudflare-temporary-deploy` | Redacts claim token by default. |
| `subagent-driven-development` | hermes-agent `optional-skills/software-development/subagent-driven-development` | Harness-agnostic delegation pattern with explicit pi mapping. |

## Attribution

The three pi-adapted copies (`dogfood`, `dependabot-validator`, `pr-grill-me`) are copied from this repository's own root skills — same authorship, no external license involved.

The other five are adapted from `NousResearch/hermes-agent`, which is MIT-licensed (Copyright (c) 2025 Nous Research). Individual files with additional upstream attribution:

| Skill | Adapted from | License basis |
|---|---|---|
| `adversarial-ux-test` | `optional-skills/dogfood/adversarial-ux-test` | MIT (hermes-agent repo license); upstream frontmatter also credited `Omni @ Comelse`. |
| `rest-graphql-debug` | `optional-skills/software-development/rest-graphql-debug` | MIT (hermes-agent repo license); upstream frontmatter also credited `eren-karakus0`. |
| `web-pentest` | `optional-skills/security/web-pentest` | MIT (hermes-agent repo license). Adapted from Shannon's pipeline (Keygraph, AGPL) — **concepts only, no code borrowed**, per the upstream skill's own disclaimer, carried forward in this skill's intro. |
| `cloudflare-temporary-deploy` | `optional-skills/web-development/cloudflare-temporary-deploy` | MIT (hermes-agent repo license and upstream frontmatter). |
| `subagent-driven-development` | `optional-skills/software-development/subagent-driven-development` | MIT (hermes-agent repo license). Its two `references/*.md` files are further adapted from `gsd-build/get-shit-done`, MIT © 2025 Lex Christopherson — attribution kept inline in those files. |

Note: this repository (`agent-skills`) does not declare a top-level `LICENSE` file. That's the repo owner's call, not something to set during a skill import — flagged here rather than resolved. Everything above is MIT-sourced (or first-party), permissive enough to be compatible with essentially any license the repo eventually adopts.
