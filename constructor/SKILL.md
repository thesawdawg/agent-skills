---
name: constructor
description: Design application architecture, folder structure, dependencies, specifications, and implementation milestones from an existing brief or user requirements.
---

# Constructor

Turn agreed requirements into a maintainable design and, when requested, an
implementation plan. Read supplied artifacts first; an ideator-generated brief
is optional. Ask only for missing constraints that affect a decision.

1. Identify state, request shape, trust boundaries, expected scale, team capacity,
   and operational constraints. Respect existing stack decisions.
2. Recommend an architecture with its costs, alternatives where meaningful,
   and conditions for revisiting it. Consult
   [architecture patterns](references/architecture-patterns.md) as needed.
3. Include a concrete folder tree, entry points, domain/data boundaries,
   configuration, and test locations. Use [the folder template](templates/folder-structure.md)
   if useful.
4. Recommend only needed dependencies, checking current primary documentation
   for compatibility and maintenance. The [catalog](references/dependency-catalog.md)
   is a starting point, not proof of current versions. Explain replacement cost.
5. Identify security/data-protection decisions and unresolved risks. Incorporate
   an existing security plan; request specialist input only when it changes the
   design. No mandatory agent handoff.
6. When specifications or milestones are requested, use
   [spec and plan](references/spec-and-plan.md) with the agreed requirements.
   Include ordered tasks, acceptance criteria, dependencies, and a first vertical slice.

Default output: `constructor-output/architecture-doc.md`, with sections for
needs, architecture, folder structure, dependencies, security, and optional plan.
Use [the architecture template](templates/architecture-doc.md) selectively.
Split documents only for independent consumption, size, or user preference.
Existing separate output files remain supported inputs; do not rewrite them just
for consistency. Implementation is a separate action governed by the user's task.
