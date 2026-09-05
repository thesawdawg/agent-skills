# Repository structure

Rules for what lives where, so the next addition doesn't drift. See
[README.md](README.md) for what the repo is and [USE_CASES.md](USE_CASES.md) for
the chooser.

## Three kinds of thing

**Skills** — a directory the harness can select and run. One job each.

**Conventions** — `coding-style`, `workflow-rules`, `memory`. Structurally
identical to skills (a `SKILL.md` the harness loads), but they are *standards read
by default*, not tasks a user picks. They never appear in the chooser table.

**Plugins** — currently only `dave/`. A plugin ships agents, commands and hooks
alongside its skill, which a plain skill cannot do.

## A skill directory

```
<skill-name>/
├── SKILL.md          required — frontmatter `name` MUST equal <skill-name>
├── USE_CASES.md      required — when to use it, and what a good run looks like
├── references/       optional — deep detail loaded on demand
├── templates/        optional — files the skill fills in
└── scripts/          optional — executable helpers, chmod +x
```

**`SKILL.md`** carries YAML frontmatter with `name` and `description`. The
description is what the harness matches against, so write it as *what it does and
when to use it*, not a title. Keep the body a workflow; push detail into
`references/`.

**`USE_CASES.md`** is the selection and calibration document: when it applies, user
phrasings, model selection cues, inputs to establish, an example plan, expected
output, and a sample result. It exists so a model can decide *whether* to use the
skill without reading the whole `SKILL.md`.

Conventions use the same layout, but their `USE_CASES.md` describes **when the
convention applies** rather than trigger phrases, since nothing selects them.

## The rules

1. **Directory name equals frontmatter `name`.** No exceptions — the name is what
   users type and what the harness reports.
2. **Every skill has a `USE_CASES.md`.** A skill without one is invisible to
   selection and gets picked by accident or not at all.
3. **Every skill is listed in [USE_CASES.md](USE_CASES.md)** — the chooser table
   for skills, the Conventions section for conventions.
4. **One job per skill.** If two skills answer the same request, one of them is
   wrong. Resolve it rather than documenting around it.
5. **Cross-link, don't duplicate.** When skills chain, each says which one comes
   next and what artifact it hands over. Never copy another skill's rules into
   yours — point at them.
6. **Scripts get run before shipping**, with a `--selftest` where there's real
   logic. "Looks right" is not tested.
7. **Relative links must resolve** from the file they're written in.

## `pi-skills/`

A separate collection targeting a constrained baseline — **Read, Write, Edit, Bash
only**. Its own [README](pi-skills/README.md) documents the portability rules that
apply there and not here: no reliance on shell state between calls, literal
absolute paths, `curl` instead of web search, JSONL instead of growing JSON arrays.

Don't copy a root skill into `pi-skills/` — the three that were duplicated have
since been deduplicated. Adapt only when the portable version genuinely differs.

## Artifact conventions

Skills that produce files write them to a predictable directory named for the
skill, in the working directory, so a chain can find its predecessor's output:

```
ideator-output/project-brief.md
constructor-output/architecture-doc.md
datasecurer-output/threat-model.md
app-design-output/app-model.md
dogfood-output/report.md
```

State that outlives a session goes under `~/.agents/` (the harness-agnostic home)
— `~/.agents/memory/` for memory. D.A.V.E. is the deliberate exception, keeping a
hand-edited working document at `~/.dave/`; its README explains why.

## Adding a skill

1. Create `<name>/` with `SKILL.md` (frontmatter `name` matching) and `USE_CASES.md`.
2. Check nothing already does the job. If something is close, extend it or
   cross-link — do not add an overlapping second skill.
3. Add a chooser row in [USE_CASES.md](USE_CASES.md), and a section under the right
   grouping.
4. If it chains with others, say so in both directions.
5. Run any scripts you shipped.
