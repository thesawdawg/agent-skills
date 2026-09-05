# agent-skills

Personal collection of [Agent Skills](https://code.claude.com/docs/en/skills) for
Claude Code, [pi](https://pi.dev), and any harness that reads a `SKILL.md` —
plus **D.A.V.E.**, an orchestrator plugin that sits above them.

There is no build and no runtime. Each directory is an independently-triggered
skill: the harness reads its `SKILL.md` frontmatter and loads it when a request
matches. [`USE_CASES.md`](USE_CASES.md) is the chooser.

## What's here

| | |
|---|---|
| **13 skills** | Idea-to-architecture chain, codebase audit, browser QA, WCAG audit, model delegation, PR and dependency review, docs sync |
| **1 plugin** | [`dave/`](dave/README.md) — priority orchestration with a nine-agent roster, `/dave:*` commands and a session hook |
| **3 conventions** | [`coding-style`](coding-style/), [`workflow-rules`](workflow-rules/), [`memory`](memory/) — read automatically, never chosen |
| **[`pi-skills/`](pi-skills/README.md)** | Harness-portable skills written to a four-tool baseline (Read/Write/Edit/Bash) |

Start at [**USE_CASES.md**](USE_CASES.md) — it maps intent to skill and explains
how they chain. [STRUCTURE.md](STRUCTURE.md) documents the layout rules.

## Install

**Claude Code** — clone into the global skills directory and everything loads,
including D.A.V.E. as `dave@skills-dir`:

```bash
git clone https://github.com/thesawdawg/agent-skills.git ~/.claude/skills
```

Already cloned? `git -C ~/.claude/skills pull`.

**Any harness, via the skills CLI** — installs to `~/.agents/skills/` and symlinks
into every agent it detects:

```bash
npx skills add thesawdawg/agent-skills -g
```

**pi** — copies the package into `~/.pi/skills/`, then enable what you want with
`pi config`:

```bash
pi install git:github.com/thesawdawg/agent-skills
```

D.A.V.E. needs more than a skill install to get his agents, commands and hook onto
pi — see [`dave/INSTALL-PI.md`](dave/INSTALL-PI.md).

**As a plugin marketplace** — this repo is one:

```bash
claude plugin marketplace add ~/.claude/skills && claude plugin install dave@agent-skills
```

### Prerequisites

Only what a given skill actually needs: `jq` for D.A.V.E., Node for `dogfood`'s
browser driver and for [`archify`](https://github.com/tt-a1i/archify) (which
D.A.V.E.'s `cartographer` uses for diagrams, installed with
`npx skills add tt-a1i/archify -g`), the Codex CLI for `codex-delegate`, a
reachable Ollama daemon for `ollama-delegate`.

## Two name collisions worth knowing

`ideator` and `constructor` exist twice, deliberately, doing different jobs:

|  | Top-level skill | D.A.V.E. agent |
|---|---|---|
| **Ideator** | Scopes a *new project* into a brief | Generates competing approaches to a decided problem |
| **Constructor** | Turns a brief into architecture and dependencies | Implements an already-agreed plan in existing code |

The skills are a project-inception chain; the agents work mid-ticket inside a
codebase that exists. See [`dave/skills/dave/references/delegation-contract.md`](dave/skills/dave/references/delegation-contract.md).

## Contributing

Skills follow the layout in [STRUCTURE.md](STRUCTURE.md): a directory named for
the skill, a `SKILL.md` whose frontmatter `name` matches that directory, and a
`USE_CASES.md` alongside it. Git and code conventions live in
[`workflow-rules`](workflow-rules/SKILL.md) and [`coding-style`](coding-style/SKILL.md) —
they apply here too.

## License

[MIT](LICENSE). The `pi-skills/` collection includes work adapted from
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) (MIT);
per-file attribution is in [`pi-skills/README.md`](pi-skills/README.md).
