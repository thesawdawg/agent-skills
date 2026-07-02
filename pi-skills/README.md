# pi-skills

Skills adapted from other agent-skill collections (currently: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)'s `optional-skills` tree). This file records the conventions those adaptations follow, so future imports don't have to re-decide the same questions.

## Frontmatter

Match the rest of this repo: only `name` and `description` in the YAML frontmatter. Upstream sources sometimes carry extra fields (`version`, `platforms`, `metadata.*`, `triggers`, `toolsets`) — drop them on import. Fold anything in `triggers` that's genuinely useful ("use when...") into the `description` field instead, since that's what this harness actually reads to decide when to load a skill.

## Harness-specific by default

Skills in this repo are written for the environment they'll actually run in (Claude Code), not for portability across arbitrary agent harnesses. Concrete tool names (`Read`, `Bash`, `WebFetch`, `Agent`, `AskUserQuestion`, `SendUserFile`) are preferred over vague paraphrases ("use an image-viewing capability") — an agent following these instructions gets a specific, actionable step instead of something it has to re-interpret. `dogfood/SKILL.md` set this precedent before `pi-skills` existed, and every skill here follows it.

`subagent-driven-development` is the deliberate exception: it was imported with an explicit ask to keep it usable by other agent harnesses, since delegation/todo-list primitives vary a lot between them. If you want another skill made harness-agnostic, that's a separate decision to make explicitly per-skill, not a default to apply silently — the tradeoff (portability vs. actionability) is real and worth thinking about each time, not templating away.

## Referencing shared scripts and other skills' files

Never assume the shell's current working directory. A skill can be invoked from inside whatever project the user is actually working on, not from inside this repo, and other skills in this repo may `cd` around during their own workflow. Any command that needs a path to a script — this skill's own, or another skill's (e.g. `adversarial-ux-test` and `web-pentest` both reuse `dogfood/scripts/browser-driver.mjs`) — should resolve it from the repo root first:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SOME_SCRIPT="$REPO_ROOT/some-skill/scripts/thing.sh"
```

Do the same for a skill's own multi-step workflows that create a working directory and might be tempted to `cd` into it: keep the directory as a variable and reference `$THAT_DIR/subpath` throughout instead of changing directories, so nothing in the instructions silently depends on where you happen to be standing when a given step runs.

Plain prose references to a skill's own same-directory `references/*.md` or `templates/*.md` docs (read via the `Read` tool, not executed) don't need this treatment — resolve those relative to the skill directory the same way every other skill here already does.

## Testing expectations

If a skill bundles a script, it should be runnable and checked before it ships, not just read for plausibility:

- Scripts with meaningful logic (parsing, scope enforcement, anything security-relevant) should include a `--selftest` mode or equivalent, covering realistic edge cases — not just the happy path.
- Run it. A script that "looks right" and a script that's actually been executed against a deliberately awkward input (quotes in a URL, mixed-case hostnames, multiple matches) are different levels of confidence, and only the second one belongs in a merged PR.

## Security expectations

- Anything that looks like a credential (tokens, claim URLs, session cookies) is redacted by default in script output. Require an explicit flag to reveal it, and only request that flag at the one step that actually needs the real value.
- Skills that touch real network targets (`web-pentest`) keep their authorization/scope guardrails intact on import — tighten them if anything, never loosen them silently during adaptation.
- This harness compresses/summarizes older parts of long conversations. Skills that produce sensitive output (secrets, exploit payloads) should say so explicitly and prefer writing sensitive values to files with the path mentioned in chat, rather than pasting the values inline.

## Attribution

All five skills currently in `pi-skills/` are adapted from `NousResearch/hermes-agent`, which is MIT-licensed (Copyright (c) 2025 Nous Research). Some individual files carry their own upstream attribution beyond that, listed here for visibility:

| Skill | Adapted from | License basis |
|---|---|---|
| `adversarial-ux-test` | `optional-skills/dogfood/adversarial-ux-test` | MIT (hermes-agent repo license); upstream frontmatter also credited `Omni @ Comelse` as author |
| `rest-graphql-debug` | `optional-skills/software-development/rest-graphql-debug` | MIT (hermes-agent repo license); upstream frontmatter also credited `eren-karakus0` as author |
| `web-pentest` | `optional-skills/security/web-pentest` | MIT (hermes-agent repo license). Adapted from Shannon's pipeline (Keygraph, AGPL) — **concepts only, no code borrowed**, per the upstream skill's own disclaimer, carried forward in this skill's intro. |
| `cloudflare-temporary-deploy` | `optional-skills/web-development/cloudflare-temporary-deploy` | MIT (hermes-agent repo license and upstream frontmatter) |
| `subagent-driven-development` | `optional-skills/software-development/subagent-driven-development` | MIT (hermes-agent repo license). Its two `references/*.md` files are further adapted from `gsd-build/get-shit-done`, MIT © 2025 Lex Christopherson — attribution kept inline in those files. |

Note: this repository (`agent-skills`) does not currently declare its own top-level `LICENSE` file. That's a decision for the repo owner, not something to pick unilaterally during a skill import — flagging it here rather than resolving it. Everything attributed above is MIT-sourced, which is permissive enough to be compatible with essentially any license this repo eventually adopts.
