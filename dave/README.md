# D.A.V.E. optional integrations

Install the portable `dave` skill using the root [catalog](../README.md). It
contains state scripts, templates, references, and seven role contracts. State
remains in `~/.dave`; migration does not rewrite existing missions or config.

The Claude plugin provides commands, a session hook, and thin role wrappers.
Installing the skill alone does not register those integrations. The plugin
retains its existing `skills/dave` layout; wrappers read bundled contracts via
`CLAUDE_PLUGIN_ROOT`. Critic reviews additionally require installed `code-review`.
Model selections in plugin agent frontmatter are host defaults, not portable rules.

Pi users may configure [optional prompts](INSTALL-PI.md) after universal skill
installation. Other hosts can invoke the installed `scripts/dave.sh` by absolute
path. Read [the delegation contract](skills/dave/references/delegation-contract.md)
for roles, aliases, and optional coordination; read [execution](skills/dave/references/execution.md)
for an existing plan without priority setup.

Run `bash scripts/install-pi.sh --selftest` from this directory to test the adapter.
Never auto-run `sync push`; cross-device publication is a user-run action.

`scripts/dave.sh dashboard` serves a local web dashboard — focus, priorities,
missions, projects, time, log, review — at `http://127.0.0.1:8766` (override with
`--port`). It binds loopback only; the state tree is personal and never leaves
the machine. Every write the UI offers goes back through `dave.sh`, so the file
stays the only writer — and `sync push` from the UI fires only on a real button
click, the same user-run boundary as the CLI.
