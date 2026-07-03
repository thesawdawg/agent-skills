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

## Shell state and paths (the rule that matters most for small models)

**On stock pi, each Bash command may run in a fresh shell — shell variables and `export`s do NOT survive between calls.** (A persistent shell is an optional extension, `pi-persistent-term` — see below — not the default.) A skill that sets `SKILL_DIR=...` in one step and uses `$SKILL_DIR` three steps later will hit an *empty* variable and fail in a way a small model won't diagnose. So skills here follow two rules:

1. **Outputs use a fixed relative path** (`./dogfood-output`, `./pentest-engagement`, …). The working directory (the user's project root) is stable between calls, so the same relative path always resolves to the same place. Do **not** `cd` into these dirs — that would break the relative paths. No variable needed.

2. **The one thing that must be absolute — the skill's own install directory (where `scripts/` lives)** — is re-declared at the top of *every* Bash block that needs it, and the value is a literal absolute path the model resolved once:

   ```bash
   # Resolve once — checks pi's standard skill locations, unambiguous and fast:
   for d in "$HOME/.pi/agent/skills/<skill>" "$HOME/.agents/skills/<skill>" ".pi/skills/<skill>" ".agents/skills/<skill>" ./pi-skills/<skill> ./<skill>; do
     [ -f "$d/scripts/<file>" ] && printf 'DIR=%s\n' "$(cd "$d" && pwd)" && break
   done
   # Then in EVERY block that runs the script, re-set the literal path:
   DIR="/absolute/path/from/above"
   node "$DIR/scripts/thing.mjs" ...
   ```

   Do **not** use `git rev-parse --show-toplevel` to find a skill's files — the skill runs inside the *user's* repo, so that returns the wrong root. For a **sibling skill's** asset (e.g. `adversarial-ux-test` and `web-pentest` reuse `dogfood`'s driver), resolve the sibling with the same loop pointed at `dogfood`.

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

Bundled scripts must be run, not just eyeballed, before shipping:
- Scripts with real logic (parsing, scope enforcement, anything security-relevant) ship with a `--selftest` mode covering awkward inputs, not just the happy path.
- Actually execute them against deliberately awkward input (quotes in a URL, mixed-case hostnames, multiple matches, ANSI codes) — that's the difference between "looks right" and "verified."

## Security expectations

- Credential-like output (tokens, claim URLs, session cookies) is redacted by default; revealing it requires an explicit flag used only at the one step that needs the real value.
- Skills that touch real network targets (`web-pentest`) keep their authorization/scope guardrails intact on adaptation — tighten, never loosen.
- Skills that produce sensitive output (secrets, exploit payloads) prefer writing values to files and referencing the path, rather than pasting them into chat (some harnesses replay chat history through summarization/compaction).

## Optional pi extensions (enhancements, NOT requirements)

Every skill here is written to run on **bare pi core** (Read/Write/Edit/Bash) with a small model — that's the design contract, and nothing below is required. But if you're running a small model and want a smoother ride, these pi extensions address the exact failure modes the skills work around. **Read this first:** a pi extension is arbitrary TypeScript running with your full user permissions — installing one *is* granting code execution. So prefer **official** extensions (shipped in the [`earendil-works/pi`](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions) repo, same maintainers as the core); for community ones, read the (small) source, pin a version, and ideally run under the official `sandbox/` or `permission-gate.ts`.

Extensions fix **mechanical** problems (lost shell state, tracking, structured output). They do **not** make a small model reason better — the judgment-heavy steps (pragmatism filter, exploit classification, risk ranking) still depend on model capability.

| Extension | Source | Fixes / helps | Which skills |
|---|---|---|---|
| **`pi-persistent-term`** | community ([vahidkowsari](https://github.com/vahidkowsari/pi-persistent-term)) | Persistent shell — cwd, venvs, **env vars survive between calls**. Removes the whole "re-declare paths every block" dance and makes backgrounded `launch` behave. | dogfood, adversarial-ux-test, web-pentest, cloudflare-temporary-deploy |
| **`todo.ts`** | official | Persistent task list with UI → counters **step-drift** on the long multi-phase skills. | all multi-phase; esp. web-pentest, dogfood |
| **`plan-mode/`** | official | Read-only exploration + step tracking → good for the recon/analysis phases. | web-pentest, dependabot-validator |
| **`question.ts` / `questionnaire.ts`** | official | Structured user prompts instead of free-text → the "(a)/(b)/(c)" branches and the authorization gate. | dogfood, adversarial-ux-test, web-pentest |
| **`structured-output.ts`** | official | Terminating tool for a clean final report/verdict. | pr-grill-me, dependabot-validator, dogfood |
| **`subagent/`** | official | Real task delegation → the "if your harness supports delegation" steps become concrete. | subagent-driven-development, web-pentest, adversarial-ux-test |
| **`sandbox/` (`@anthropic-ai/sandbox-runtime`), `gondolin/` (micro-VM), `permission-gate.ts`, `confirm-destructive.ts`** | official | OS-level isolation + per-command approval → the right way to run **destructive/active testing** safely rather than trusting a small model to self-restrain. | **web-pentest** (strongly recommended), cloudflare-temporary-deploy |
| **`pi-permissions`** | community ([bu5hm4nn](https://github.com/bu5hm4nn/pi-permissions)) | Per-command approval, fail-closed SSH blocking. | web-pentest |

Guidance: for a small model doing QA/browser work, `pi-persistent-term` + `todo.ts` remove the most friction. For **web-pentest specifically, run it under `sandbox/` + `permission-gate.ts`** regardless of model size. There's also a third-party [Agent Safehouse sandbox analysis of pi](https://agent-safehouse.dev/docs/agent-investigations/pi) if you want an outside read on the runtime.

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
