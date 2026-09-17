# Agent skills

A selectively installable collection of workflows and conventions. Some skills
bundle executable helpers; prerequisites are declared in each skill. Installing a
skill does not register plugin agents, hooks, commands, or always-on host rules.

## Install

The verified installer is **`skills@1.6.0`** (plural). `npx skill install` is not
an alias for it.

```bash
npx skills@1.6.0 add thesawdawg/agent-skills --list
npx skills@1.6.0 add thesawdawg/agent-skills -g --skill dogfood
npx skills@1.6.0 add thesawdawg/agent-skills -g --skill dave code-review --copy
```

With multiple agent directories (e.g. `--agent claude-code cursor`), omitting
`--copy` uses symlinks. Version 1.6.0 automatically copies for a single target. `--all` selects all skills/agents; use
selective installation for a smaller catalog. For an unpublished checkout, replace
`thesawdawg/agent-skills` with its absolute path. `npx skills@1.6.0 use --help`
describes the CLI's opt-in skill-use workflow; it is separate from installation.

## Catalog

| Skill | Purpose |
|---|---|
| [accessibility-audit](accessibility-audit/SKILL.md) | WCAG criteria, axe evidence, and manual accessibility checks; requires dogfood or equivalent browser capability. |
| [app-design](app-design/SKILL.md) | Assess an existing repository and prioritize verified improvements. |
| [cloudflare-temporary-deploy](cloudflare-temporary-deploy/SKILL.md) | Prepare and verify an explicitly authorized public Worker preview. |
| [code-review](code-review/SKILL.md) | Read-only review of a diff or plan, without an author interview. |
| [codex-delegate](codex-delegate/SKILL.md) | Continuous Codex CLI session mechanics for authorized delegation. |
| [commit-documentor](commit-documentor/SKILL.md) | Draft commit-related docs and commit only approved files locally. |
| [constructor](constructor/SKILL.md) | Architecture, dependencies, specifications, and milestones. |
| [datasecurer](datasecurer/SKILL.md) | Threat models, data protection, and tested recovery planning. |
| [dave](dave/skills/dave/SKILL.md) | Optional priority/state management and plan execution; Critic reviews require code-review. |
| [dependabot-validator](dependabot-validator/SKILL.md) | Compatibility review of Dependabot, Renovate, or manual dependency updates. |
| [dogfood](dogfood/SKILL.md) | Evidence-backed browser QA and optional simulated persona UX. |
| [flask-tests](flask-tests/SKILL.md) | Legacy application-specific fixtures; use only after confirming the owning app. |
| [ideator](ideator/SKILL.md) | New-project scope and a concise project brief. |
| [memory](memory/SKILL.md) | Optional durable memory, reusing the configured system. |
| [ollama-delegate](ollama-delegate/SKILL.md) | Text-only Ollama invocation and bounded conversation mechanics. |
| [pr-grill-me](pr-grill-me/SKILL.md) | Author interview checked against the actual PR diff. |
| [rest-graphql-debug](rest-graphql-debug/SKILL.md) | Layered HTTP/GraphQL diagnosis and focused lookup recipes. |
| [web-pentest](web-pentest/SKILL.md) | Explicitly authorized, scoped security assessment with protected evidence. |
| [workflow-rules](workflow-rules/SKILL.md) | Advisory workflow conventions and on-demand coding style. |

## Migration

| Previous entry/path | Current owner |
|---|---|
| Pi API/security/deploy subdirectories | Same skill names at repository root |
| adversarial-ux-test | dogfood persona UX reference |
| subagent-driven-development | dave execution reference |
| coding-style | workflow-rules style reference |
| app-design spec/milestone templates | constructor |
| D.A.V.E. constructor / ideator / brainstormer / module-finder | implementer / options / options / scout lookup aliases |

Updates do not necessarily remove old installed entries. After reviewing your
installed list (`npx skills@1.6.0 list -g`), reinstall the new owners. Only with your
approval, remove superseded entries using `npx skills@1.6.0 remove coding-style
adversarial-ux-test subagent-driven-development -g`. Source cleanup does not modify
personal installations, host rules, or D.A.V.E. state. Flask relocation is deferred
until its owning project is identified.

[Optional D.A.V.E. integrations](dave/README.md) are configured separately.
[Authoring and verification](STRUCTURE.md) describes `bash scripts/verify.sh`.
The [cleanup plan](CLEANUP-PLAN.md) records decisions and validation limits.
MIT license: [LICENSE](LICENSE); adapted bundles carry their own upstream NOTICE.
