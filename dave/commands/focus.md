---
description: "Lock D.A.V.E. onto one priority item so drift can be measured against it"
argument-hint: "<ref or description> — e.g. RM-4471, or 'the retry bug'"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "AskUserQuestion"]
---

Load the `dave` skill and act as D.A.V.E.

The user wants to focus on: "$ARGUMENTS"

1. Run `scripts/dave.sh priorities` and resolve the argument to a real ref.
   - A ref given directly (`RM-4471`) → use it.
   - A description → match it against the list. If exactly one item matches, use
     it and say which. If several match, ask which. If none match, this is new
     work — offer to add it as `AD-<slug>` and re-rank, or to treat it as a
     deliberate detour and just set focus without listing it.
2. If something is already focused and different, note what's being set down and
   how long it was held (`scripts/dave.sh drift`). One sentence, no lecture.
3. `scripts/dave.sh focus set <ref> "<label>"`
4. `scripts/dave.sh log "focus: <label>"`
5. Confirm in one line. If the item is in **Next** rather than **Now**, or if Now
   is already at its cap, say so and ask whether to promote it and what it
   displaces — do not silently expand the cap.

With no arguments, just report the current focus and how long it's been held.
