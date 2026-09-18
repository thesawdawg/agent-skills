---
description: "Spawn a project-tuned D.A.V.E. instance (.<slug>-dave/) beside this project, with a guided tuning walkthrough"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

Load the `dave` skill and read its **Project-tuned instances** section and
`references/projects.md` first.

Request: "$ARGUMENTS" — an optional path; default is the current directory.

1. `scripts/dave.sh project home <path>`. If it prints a path, an instance already
   exists: summarize its `config.json` overrides and `project.md`, offer to adjust
   them, and stop. Never re-spawn over it.
2. `scripts/dave.sh project show` and `scripts/dave.sh config --global` — collect
   what is already known so the walkthrough asks only for what is missing.
3. Run the two question rounds from the skill (what the project is; how D.A.V.E.
   should behave here), each as **one** `AskUserQuestion` call. Prefill every
   answer you already have and say so.
4. Assemble a single `scripts/dave.sh project spawn …` command from the answers,
   show it, and run it on approval.
5. Fill `Scope`, `Sources`, `Rules` and `Project roles` in the new `project.md`
   from the answers. Then show `scripts/dave.sh config` — the merged result — in
   full, so the user sees exactly what changed and what was inherited.

Say plainly what stays global: the ranked list, the log, missions, time. If the
user asked for a second priority list, explain in one sentence why the instance
does not provide one and offer `project link` instead.
