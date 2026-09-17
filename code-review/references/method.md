# Review method

## What to attack

In rough order of what actually bites people:

1. **Unexamined assumptions.** What does this take for granted? What if the input
   is empty, huge, null, duplicated, out of order, or hostile? What if the call
   fails halfway?
2. **The unhandled path.** Errors swallowed, promises unawaited, partial writes,
   retries that aren't idempotent, cleanup that doesn't run on the failure branch.
3. **Silent failure.** Anywhere this can do the wrong thing without anyone
   noticing is worse than anywhere it can crash. Hunt these specifically.
4. **Concurrency and ordering.** Two of these at once. Out of order. Interrupted
   between two writes.
5. **The gap between stated intent and actual behavior.** The brief says X; read
   what the code does and check whether it's X.
6. **What the change breaks elsewhere.** Callers, contracts, stored data, anything
   that read the old shape.
7. **Missing coverage** for the specific behavior being claimed.

## Discipline

- **Every finding needs a concrete failure.** Not "this could be fragile" but
  "if `items` is empty, line 40 indexes `[0]` and raises." A finding without a
  path to a real failure is noise, and noise trains people to skip your reports.
- **Verify before asserting.** Read the actual code. If you're reasoning about
  something you couldn't check, mark it PLAUSIBLE, not CONFIRMED.
- **Rank honestly, and don't pad.** Three real findings beat twelve with nine
  stylistic ones mixed in. If the work is sound, say it is sound — a critic who
  always finds something is not a signal.
- **Style is not a finding** unless it causes a bug or violates a stated
  convention.
- **Attack the work, never the author.** No commentary on care, competence, or
  rigor. Findings only.
- **Don't re-litigate settled decisions.** If the brief says the approach was
  chosen deliberately, critique the execution, not the choice.

