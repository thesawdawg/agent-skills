# Kanban intake

There is no API. Boards arrive because the user pastes them, screenshots them, or
exports them — which makes board data **stale by default**, and that staleness has
to be visible rather than assumed away.

## Accepting a board

Take whatever form it arrives in:

- **Pasted text** — columns as headings, cards as lines. Most common.
- **Screenshot** — read it directly. Transcribe cards verbatim before ranking; do
  not summarize a card into what you assume it means.
- **CSV / export** — parse structurally.
- **A verbal list** — "I've got SSO, the billing migration, and two bugs." Treat
  as a board with one column.

Archive the raw input first, before any parsing:

```bash
dave.sh intake "<board name>" < /path/to/pasted-board.txt
```

This stamps `last_intake` and keeps the original, so a later disagreement about
what a card said is resolvable, and so the same board is never re-parsed from
scratch.

## Normalizing

Map the board's columns onto the priority model. Column names vary; ask once
rather than guessing at an unfamiliar one:

| Typical column | Section |
|---|---|
| Doing / In Progress / WIP | **Now** |
| Ready / To Do / Sprint Backlog | **Next** |
| Blocked / Waiting / Review | **Blocked** — capture what it waits on |
| Backlog / Icebox | **Someday** |
| Done | not carried over; use it to close items |

Give every card a ref: `KB-<board>-<slug>`, slug from the card title. Keep refs
stable across intakes — a card that gets renamed keeps its original ref, with the
new title as the label, or every cross-reference in the logs breaks.

## Staleness

Board data has an age, and the age matters more than the content. Record the
intake date against each board in config's `kanban.boards`. When a board is older
than `kanban.stale_after_days` (default 7), say so at the top of any brief that
leans on it:

> Worth flagging: the platform board is from the 28th. Anything I say about its
> ranking is nine days out of date.

Never present stale board data as current, and never quietly re-use a week-old
board to argue the user is off-track. If a drift call depends on board state older
than the threshold, ask for a fresh board before making the call — being confidently
wrong about someone's priorities is worse than saying nothing.

## Deduplication

The same work often appears on a board *and* in Redmine. Merge into one item with
both refs (`RM-4471 / KB-platform-sso-rollout`) rather than ranking it twice.
Redmine is authoritative for status; the board is authoritative for the team's
current intent about ordering. When they disagree, list it as **contested** in the
reconcile diff and let the user settle it — that disagreement is usually real
information about the team, not a data error to be cleaned up.
