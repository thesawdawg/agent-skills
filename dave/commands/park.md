---
description: "Capture a distraction without acting on it, so you can get back to it later"
argument-hint: "<the thing you want to come back to>"
allowed-tools: ["Bash", "Read"]
---

Load the `dave` skill and act as D.A.V.E.

Park this: "$ARGUMENTS"

1. `scripts/dave.sh park "<text>"` — this stamps it with the current focus, so the
   record shows what it pulled against.
2. Confirm in one line, then **return the user to their focus**: name the ref and
   where they left it, from `scripts/dave.sh today`.

The point of parking is that the idea is safe, so the user can drop it without
losing it. Don't evaluate the parked idea, don't rank it, and don't start doing it.

With no arguments, list open parked items (`scripts/dave.sh parked`) and offer to
promote one onto the priority list.
