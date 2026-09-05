# Redmine

Redmine reaches D.A.V.E. through an MCP server whose exact tool names vary by
install. **Never assume a tool name.**

> On a harness with no MCP support — pi, and anything else whose core is just
> Read/Write/Edit/Bash — use [redmine-rest.md](redmine-rest.md) instead: the same
> operations over `curl` against Redmine's REST API. Every approval rule below
> still applies there, unchanged.
 Discover what is actually present, once per
session, before claiming any Redmine capability:

```
ToolSearch: "+redmine issue query"
```

If nothing comes back, Redmine is unavailable this session. Say so plainly and
carry on — the priority list still works from kanban and ad-hoc items, just with a
gap that gets noted at the top of the list. Do not fabricate ticket data, and do
not fall back to guessing issue numbers from memory of an earlier session.

## Reading

Reading is unrestricted. Pull assigned open issues at intake, and pull a single
issue whenever the user references one by number.

Cache what you read into `priorities.md` rather than re-querying — the list is the
working copy. Re-query at intake, when the user asks, or when about to write.

Bring back only what ranking needs: id, subject, status, priority, assignee,
due date, and the last update. Full descriptions and comment threads are for when
the user opens a specific ticket, not for a list refresh — pulling forty full
tickets to rank them is exactly the kind of context burn that makes D.A.V.E.
forget what you were doing.

## Writing

Configured authority is `redmine.authority` in config. The default, and what this
setup assumes, is **`propose-writes`**: D.A.V.E. actively looks for writes worth
making and drafts them — but **every outward write is shown in full and requires
an explicit yes for that specific write.** Not a standing yes, not a yes inherited
from earlier in the session, and never a yes assumed from silence.

An outward write is anything the user's team can see: status transitions, comment
posts, time logs, assignee changes, field edits, new issues.

### The approval gate

Show the exact payload before asking. Every field that will change, with its
before and after:

```
Redmine write — RM-4471
  status:    In Progress  →  Resolved
  time:      +2.5h "traced the double-fire to the retry middleware"
  comment:   "Root cause was the retry wrapper re-entering on 5xx. Fixed in
              a3f9c21; added a regression test."

Send it? (yes / edit / skip)
```

Rules that do not bend:

- **One approval, one write.** Approving a status change is not approval to also
  log time.
- **Batches are itemized.** Five ticket updates means five payloads shown; the
  user may approve all at once, but they must see all five first.
- **Never invent time.** Log only hours grounded in the session log or that the
  user stated. If the log is thin, ask rather than estimate — a fabricated time
  entry is a false record in the team's system of record.
- **Never write to a ticket the user hasn't touched this session** without saying
  why it came up.
- **Never close anything on inference.** "Looks done" is a proposal for the user,
  never a reason to transition.

If a write fails, report the failure and the ticket's actual current state. Never
retry silently, and never report success you didn't observe.

## Drafting good writes

The Scribe agent drafts these well — delegate when there are several, or when a
comment needs to reconstruct a day's work from the log. A ticket comment should
say what changed, why, and what a reader needs to know next; it should not narrate
the debugging journey.

Time logs come from `dave.sh standup` — the day's log is the evidence. Present it
alongside the draft so the user can check the hours against what actually happened.
