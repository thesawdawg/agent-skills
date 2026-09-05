# Installing D.A.V.E. in the pi harness

For [pi](https://pi.dev) (`@earendil-works/pi-coding-agent`) — a minimal agent
harness whose core is just **Read / Write / Edit / Bash**. See
[README.md](README.md) for what D.A.V.E. is and
[../pi-skills/README.md](../pi-skills/README.md) for this repo's general
pi-portability conventions.

Verified against **pi 0.82.0**.

## Read this first: what does and doesn't port

D.A.V.E. is built as a Claude Code **plugin**, and pi has no plugin system. The
skill itself ports cleanly; the rest has to be mapped onto pi's own mechanisms, and
two capabilities are genuinely absent rather than merely different.

| Piece | Claude Code | pi |
|---|---|---|
| Orchestrator skill | `skills/dave/SKILL.md` | ✅ direct — `/skill:dave` |
| State layer (`dave.sh`) | bash + `jq` | ✅ direct — no harness features used |
| 7 commands | `/dave:brief`, … | ✅ mapped to prompt templates — `/dave-brief`, … |
| 6 agents | real subagents | ⚠️ **role reference docs**, run as focused passes — unless the official `subagent/` extension is installed |
| Redmine | MCP server | ⚠️ **REST over `curl`** — pi has no MCP at all |
| SessionStart hook | injects focus automatically | ❌ **no hooks in pi** — run `/dave-brief` yourself, or use the `AGENTS.md` stanza |

The two ⚠️ rows still work; they take a different route. The ❌ row does not exist
on pi, so the drift watch is only active once something has actually read the list
in that session. Plan around it rather than assuming it fires.

## Prerequisites

```bash
curl -fsSL https://pi.dev/install.sh | sh    # or: npm i -g --ignore-scripts @earendil-works/pi-coding-agent
```

`jq` is required — `dave.sh` uses it for all state reads and writes.

## Route A — native `pi install` (lightweight)

pi discovers a `SKILL.md` at any depth inside an installed package, so installing
this repo picks D.A.V.E. up along with every other skill in it:

```bash
pi install ./                          # from a local clone
```

`pi install git:github.com/thesawdawg/agent-skills` and
`pi install https://github.com/thesawdawg/agent-skills` work the same way. The
package is **copied** into `~/.pi/skills/<package>/`, not symlinked — a clone you
keep editing will drift from what pi runs until you `pi update`.

Then enable it. `pi config` opens a TUI listing every skill in every installed
package; entries are stored in `~/.pi/agent/settings.json` as `+`-enabled or
`-`-disabled paths:

```bash
pi config          # Tab switches scope; enable skills/dave/skills/dave/SKILL.md
```

**What this route does not do:** no prompt templates (no `/dave-brief`), agent
files keep Claude-only frontmatter, and the skill's relative `scripts/dave.sh`
references don't resolve — pi's working directory is your *project*, not the skill
directory. Under this route, resolve the path once per session and then use the
literal result, since **pi shell variables do not survive between Bash calls**:

```bash
for d in "$HOME/.pi/agent/skills/dave" "$HOME/.agents/skills/dave" \
         ".pi/skills/dave" ".agents/skills/dave" \
         "$HOME"/.pi/skills/*/dave/skills/dave; do
  [ -f "$d/scripts/dave.sh" ] && printf 'DIR=%s\n' "$(cd "$d" && pwd)" && break
done
```

## Route B — `install-pi.sh` (recommended)

Takes the plugin apart and puts each piece where pi actually looks for it,
rewriting relative paths to literal absolute ones as it goes:

```bash
./dave/scripts/install-pi.sh --with-agents-md
```

| Flag | Effect |
|---|---|
| `--pi-root DIR` | Install somewhere other than `~/.pi/agent` |
| `--with-agents-md` | Append the session stanza to `$PI_ROOT/AGENTS.md` (the nearest thing to the hook) |
| `--dry-run` | Print what would happen, change nothing |
| `--selftest` | Install to a temp dir and assert 21 invariants |

It is idempotent — re-running overwrites managed files and never duplicates the
`AGENTS.md` stanza or the appended pi notes. Re-run it after every `git pull`.

### What lands where

```
~/.pi/agent/
  skills/dave/
    SKILL.md                     /skill:dave  (+ an appended "Running under pi" section)
    references/*.md              incl. redmine-rest.md
    references/roles/*.md        the 6 agents, Claude-only frontmatter stripped
    templates/, scripts/dave.sh
    README.md, USE_CASES.md      copied so the skill's own links resolve
  prompts/dave-*.md              /dave-brief /dave-focus /dave-intake /dave-check
                                 /dave-park /dave-delegate /dave-standup
  AGENTS.md                      the session stanza, only with --with-agents-md
```

Commands become pi **prompt templates**: `$ARGUMENTS` is rewritten to pi's
`{{args}}`, Claude-only `allowed-tools` / `argument-hint` frontmatter is dropped,
and every `scripts/dave.sh` and `references/` path is made absolute so it resolves
from any project directory.

## The four differences that change how you use him

**1. No subagents.** The [delegation contract](skills/dave/references/delegation-contract.md)
still governs, but "delegate to Scout" means *run a fresh, focused pass in the main
loop* using that role's charge and return format from `references/roles/scout.md`.
Brief it just as strictly — the discipline is what makes the output usable, not the
process boundary. The trade-off is real: the exploration burns your main context,
which is the one thing delegation was there to prevent. Keep the charges narrower
than you would on Claude Code.

If you install the official `subagent/` extension from the
[pi repo](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions),
dispatch real subagents instead and the contract works as written.

**2. No MCP, so no Redmine MCP.** Use
[skills/dave/references/redmine-rest.md](skills/dave/references/redmine-rest.md) —
plain `curl` against Redmine's REST API, with the API key in `~/.dave/.redmine-key`
(mode 600), never in `config.json`. **Every approval rule from
[redmine.md](skills/dave/references/redmine.md) still applies**: exact payload
shown, one explicit yes per write, hours never invented. The transport changed; the
gate did not.

**3. Shell state does not persist between Bash calls.** Never `export DAVE_HOME` in
one step and rely on it in the next — it will be empty and the failure is quiet.
`dave.sh` defaults to `~/.dave`, so just call it by its literal absolute path. To
use a different state directory, set it inline on every call:

```bash
DAVE_HOME=/path/to/state ~/.pi/agent/skills/dave/scripts/dave.sh brief
```

The community `pi-persistent-term` extension removes this constraint, at the cost
of running third-party TypeScript with your full permissions.

**4. No hooks.** Nothing injects your focus at session start. Either run
`/dave-brief` when you sit down, or install with `--with-agents-md` so the
instruction to do so lives in `~/.pi/agent/AGENTS.md`, which pi loads globally.
Note the difference honestly: the stanza is *an instruction to check*, not an
automatic injection of live state — it depends on the model choosing to act on it,
which a small model often won't. On pi, treat `/dave-brief` as a habit rather than
a guarantee.

## Optional extensions that close the gaps

A pi extension is arbitrary TypeScript running with your full user permissions —
installing one *is* granting code execution. Prefer the official ones shipped in
the pi repo; read the source of community ones and pin a version.

| Extension | Closes |
|---|---|
| `subagent/` (official) | Difference 1 — real delegation |
| `pi-persistent-term` (community) | Difference 3 — shell state survives |
| `todo.ts` (official) | Step drift across D.A.V.E.'s longer multi-phase runs |
| `question.ts` (official) | The park / promote / continue branch as a structured prompt |

None are required. Everything above runs on bare pi core.

## Verifying

```bash
./dave/scripts/install-pi.sh --selftest          # 21 assertions, temp dir, no side effects
~/.pi/agent/skills/dave/scripts/dave.sh init     # creates ~/.dave
~/.pi/agent/skills/dave/scripts/dave.sh brief    # composite read
ls ~/.pi/agent/prompts/dave-*.md                 # 7 templates
```

Then in pi: `/skill:dave` should load the orchestrator, and typing `/dave-` should
offer the seven templates. First run detects the unconfigured state and walks you
through setup.

## Updating and removing

```bash
git pull && ./dave/scripts/install-pi.sh --with-agents-md    # Route B
pi update                                                    # Route A
```

To remove a Route B install:

```bash
rm -rf ~/.pi/agent/skills/dave ~/.pi/agent/prompts/dave-*.md
```

Then delete the `<!-- dave:begin -->` … `<!-- dave:end -->` block from
`~/.pi/agent/AGENTS.md`. Your state in `~/.dave/` is untouched by any of this —
delete it separately if you actually want the priority list gone.
