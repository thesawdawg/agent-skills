# The priority model

One ranked list, in `~/.dave/priorities.md`, spanning every source. Redmine
tickets and kanban cards are *inputs* to that list — they are not themselves the
list, because neither system knows about the other and neither knows what the user
promised someone in a hallway.

## Refs

Every item carries a stable ref so focus, logs, missions, and drift checks can all
point at the same thing:

| Prefix | Source | Example |
|---|---|---|
| `RM-` | Redmine issue id | `RM-4471` |
| `KB-` | Kanban card, `KB-<board>-<slug>` | `KB-platform-sso-rollout` |
| `AD-` | Ad hoc — real work with no ticket anywhere | `AD-cache-warmup` |

An `AD-` item that survives more than a few days is a smell: either it deserves a
ticket or it belongs in Someday. Say so once, then leave it alone.

## The four sections

**Now** — capped at `priorities.max_now` (default 3). This is the operative
definition of on-track: work not in Now is drift until the list says otherwise.
When Now is full, adding to it requires taking something out, and D.A.V.E. asks
which rather than quietly expanding the cap.

**Next** — ordered. The top item is what gets promoted when Now empties. Order is
maintained explicitly; ties are broken and recorded, not left ambiguous.

**Blocked** — must name *what* it waits on and *who owes it*. If nothing is owed
by anyone, it is not blocked, it is unstarted, and it belongs in Next. Re-check
blockers at every intake; a blocker nobody is chasing is a blocker that will not
clear on its own.

**Someday** — real but not now. Exists so Next stays honest.

## Ranking

Rank by `priorities.ranking_factors`, in config order. The default order:

1. **A commitment made to someone.** A promise outranks a preference. This sits
   first deliberately — it is the factor users discount and then regret. Record
   them: `dave.sh promise add "<who>" "<what>" <due> [--ref R]`. Until a commitment
   is a record it cannot be ranked, chased, or shown coming due — it is a thing the
   user has to remember, which is the problem D.A.V.E. exists to remove. `brief`
   surfaces anything inside `review.promise_horizon_days`, and a moved date keeps
   its history rather than quietly overwriting the original.
2. **Deadline.** Hard external dates before soft internal ones.
3. **Blocking others.** Work that unblocks another person beats solo work of equal
   size, because their idle time is a real cost.
4. **Effort.** Among equals, shorter first — finishing things is load-bearing.
5. **Energy fit.** A real factor, and the last one. It justifies picking between
   two items of equal rank; it never justifies skipping the list.

Ranking is a recommendation. When the user overrides it, record *why* in the item
line — the override is usually context D.A.V.E. lacked, and it should survive the
next reconcile rather than being silently re-sorted away.

## Reconciling

On intake, produce a **diff, never a silent rewrite**:

- **New** — appeared in a source since last intake
- **Moved** — changed status or rank, with the reason
- **Gone** — closed, or vanished from a board (these two are different; say which)
- **Stale** — in Now with no log activity for days
- **Contested** — a source disagrees with the list (ticket closed in Redmine but
  still sitting in Now)

Show the diff, get a yes, then write the file. `priorities.md` is the user's
document; D.A.V.E. maintains it, but does not own it.

## Drift

Drift is not "working on something unplanned" — that is often correct. Drift is
**working on something unplanned without having decided to.** The distinction is
the whole point: a deliberate detour is a decision, and D.A.V.E. respects
decisions. An accidental one is what he exists to catch.

Signals, from `dave.sh drift` plus what's visible in the session:

- Current focus ref is absent from `priorities.md`
- No focus set at all while real work is happening
- Time on an unlisted thread exceeds `drift_threshold_minutes` (default 45)
- Third-plus distinct repository, service, or subject area in one session
- The session is deep in something that was explicitly parked before

**The protocol** — at most once per drift episode:

1. Name it in one sentence, with the number that makes it concrete ("50 minutes,
   and RM-4471 hasn't moved").
2. Offer exactly three doors: **park it** (capture, return to the list), **promote
   it** (it is genuinely more important — re-rank now), or **continue** (a
   deliberate detour, logged and left alone).
3. Take the answer at face value and act on it immediately.

If the answer is continue, `dave.sh focus push` onto the detour rather than
replacing the focus — the parent and its clock survive, and `focus pop` returns to
it. Then do not raise it again for that thread. Repeating a settled objection is
the single fastest way for this plugin to become something the user turns off.

**Record the episode once it is settled:**

```bash
dave.sh drift record third-repo continued          # kind, then outcome
```

Kinds: `unlisted`, `third-repo`, `parked-resurfaced`, `no-focus`. Outcomes:
`parked`, `promoted`, `continued`. This is not for nagging — it is never read back
in the same session. It exists so the weekly review can say *four of this week's
six drift calls went into the same project*, which is a fact about the work rather
than a fact about the user's discipline.
