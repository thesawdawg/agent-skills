# Development Plan: {project_name}

**Date:** {date}
**Based on:** specifications.md, stack-decisions.md

---

## Stack Summary

| Layer | Choice |
|-------|--------|
| Language/runtime | {choice} |
| Frontend | {choice} |
| Backend / API | {choice} |
| Datastore | {choice} |
| Auth | {choice} |
| Hosting / CI | {choice} |

(Full reasoning in `stack-decisions.md`.)

## First Vertical Slice

The thinnest end-to-end path that proves the architecture works:

> {e.g., "User signs up, creates one {core entity}, and sees it persisted — wired through UI → API → DB → deployed to staging."}

**Why this slice:** {what risk it retires}

## Milestones

### Milestone 1 — {name}
**Goal:** {demoable outcome}
**Definition of done:** {checklist}

| Task | Depends on | Notes |
|------|-----------|-------|
| {task} | — | {note} |
| {task} | {task} | {note} |

### Milestone 2 — {name}
**Goal:** {demoable outcome}
**Definition of done:** {checklist}

| Task | Depends on | Notes |
|------|-----------|-------|
| {task} | M1 | {note} |

## Testing Strategy

- **Unit:** {what / where}
- **Integration:** {what / where}
- **End-to-end:** {what / where}
- **Exploratory QA:** run the `dogfood` workflow once a UI exists, scoped to the core flows.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| {risk} | {L/M/H} | {L/M/H} | {plan} |

## Immediate Next Action

> {The single next thing to do — e.g., "Scaffold the repo and implement the first vertical slice."}
