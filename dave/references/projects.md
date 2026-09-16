# The project layer

The ranked list answers *what next*. It cannot answer *what has gone quiet*,
because a list of items has no memory of the container they belong to. A project
is that container: a directory, a goal, a cadence, and the refs that serve it.

Projects do not replace `priorities.md` and do not change its format. One ranked
list still spans every source. A project is a **facet** of that list — a way to
ask which items belong to the same body of work, and whether that body of work has
been touched lately.

## The direction of the link

**Projects reference refs. Refs never reference projects.**

```bash
dave.sh project link webcrawler RM-4471
```

The ref lives in `projects/<slug>/project.json`, not in the priority line. This is
deliberate: `priorities.md` is the file the user hand-edits most, and giving it a
parseable schema would mean every intake has to preserve one. Nothing in the
project layer parses the user's document.

The cost is that the two can disagree — a linked ref that no longer appears in the
list. `project show` prints those as `(not in priorities.md)` rather than hiding
them. That disagreement is usually the ref having been closed, and it is worth a
sentence, not a cleanup.

## Registering

```bash
dave.sh project add ~/Projects/webcrawler --goal "crawl politely" --cadence weekly
```

Paths are canonicalized on the way in, which is what makes resolution work. A
project does not have to be a git repository; one that isn't simply has no git
section.

With `projects.root` set and `projects.autodiscover` on, `project list` names
unregistered directories under that root as **candidates**. It never adds them.
Registration is a decision — a tool that quietly enrolls every directory it finds
is a tool that reports on work the user never asked it to watch.

## Cadence, and why the sweep needs it

| Cadence | Means |
|---|---|
| `daily` | Silence for a few days is a finding |
| `weekly` | The default. Silence for a couple of weeks is a finding |
| `monthly` | Long gaps are normal |
| `dormant` | Deliberately idle. Silence is never a finding |

Status is a different axis: `active`, `paused`, `maintenance`, `archived`.

Cadence is what keeps the weekly review honest. Without it every quiet project
looks like a problem, the sweep fills with findings that are not findings, and the
user stops reading it — which costs more than never having built it. A
`maintenance` project with no commits in two months is working as intended, and the
review says so under *quiet and fine*.

## Resolution

```bash
dave.sh project resolve            # from $PWD
dave.sh project resolve <path>
```

Walks up from the directory to the filesystem root and prints the first registered
project whose path matches, so a session opened deep inside a tree still resolves.
It is **silent and exits 0** when nothing matches — both the session-start hook and
`brief` call it in directories that have nothing to do with D.A.V.E., and neither
may pay for that with noise.

This is what makes the session-start hook say something specific: in a registered
project it leads with that project's name, goal and refs; anywhere else it emits
exactly what it emitted before the project layer existed.

## The scan

```bash
dave.sh scan            # every non-archived project
dave.sh scan <slug> --fresh
```

Branch, dirty and untracked counts, commits behind and unpushed ahead, and how old
the last commit is. Optionally the open PR count, when `projects.use_gh` is on, the
remote is GitHub and `gh` is installed — and silently skipped on any failure,
because a scan must not break when the network does.

**It never fetches.** Ahead/behind is measured against the last-known remote ref,
and the output says so rather than implying freshness it does not have.

Results are cached for `projects.scan_ttl_seconds` (default 300). The split matters:

- **`brief` refreshes the cache** — it is explicitly invoked, so it can afford the
  walk, and it leaves the result behind for whoever reads next.
- **The session-start hook only reads it.** It shows git state when a scan already
  knows it and says nothing when none does. A hook that probes every registered
  repository at session start is a hook that gets disabled, and then nothing works.

This is the one signal about a project that is always current. Boards arrive by
hand and go stale; Redmine needs an MCP that may not be there; git is sitting in
the directory. It is how the weekly review knows a project has gone quiet without
anyone having told it.

## What belongs in a project, and what doesn't

**Belongs:** the goal, the cadence, the refs, the cached codebase dossier, the
missions opened against it.

**Does not belong:** the ranking. Rank is global and lives in `priorities.md`,
because a per-project ranking would let three projects each hold a number-one item
and quietly reintroduce the problem D.A.V.E. exists to solve — several lists, none
of them the list.
