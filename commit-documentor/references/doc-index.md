# Optional doc index for larger documentation trees

The index lives in the project repo at the config's `doc_index` path (default
`.agents/commit-documentor/doc-index.md`) and is **committed** — it is the local,
reviewable map of code area → doc page, and it is what keeps doc querying cheap
and in sync.

For a small tree, use scoped search directly and skip index setup. If an index
is used and missing or stale, refresh it:

```bash
scripts/doc-repo.sh sync     # repo mode: clone or fast-forward. local mode: no-op
scripts/doc-repo.sh list     # every doc file under docs_root
```

Then, for each significant top-level code area in the project (directories under
the source root, the CLI, the API surface, config), search the docs for it:

```bash
scripts/doc-repo.sh search "<module name>" "<command name>" "<env var>"
```

Fill in [templates/doc-index-template.md](../templates/doc-index-template.md) from the
results, including the two negative sections — undocumented code areas, and doc
pages with no code owner. Both are load-bearing later: the first tells you when to
propose a *new* page, the second tells you what to leave alone. Record the docs'
current SHA in the header so drift is detectable next run.

In local mode on a project with no `docs/` tree yet, the scan is legitimately
empty: every code area lands under "Undocumented areas", and the first real run
will propose new pages rather than edits. Say that plainly rather than reporting
an empty index as a failure.

Show the index to the user before committing it — a wrong mapping silently
mis-targets every future run.
