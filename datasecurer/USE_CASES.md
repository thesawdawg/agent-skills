# datasecurer: Practical Use Cases

This guide shows **when to invoke `datasecurer`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See [SKILL.md](SKILL.md) for the full workflow and the `references/` directory for threat models and redundancy patterns. See also the [top-level skills index](../USE_CASES.md).

**`datasecurer` is stage three of the new-project chain:** [`ideator`](../ideator/USE_CASES.md) → [`constructor`](../constructor/USE_CASES.md) → `datasecurer`. It reads the brief and the architecture, then produces the threat model, security plan, and redundancy plan — and says plainly where the architecture and the security requirements conflict.

## Use it when

Use `datasecurer` when a design exists and the question is what could go wrong: attack, loss, or outage.

Good uses:

- Threat-modelling a planned system before it's built
- Deciding what data is actually sensitive and what protection it warrants
- Planning backup and redundancy against a stated recovery objective
- Reviewing an architecture for security and reliability gaps
- Answering "what happens when this component dies?"

Do not use it as a penetration test of a running system — that's [`web-pentest`](../pi-skills/web-pentest/SKILL.md), which needs authorization and a live target. Do not use it to fix vulnerabilities in existing code. Do not run it before there's an architecture to review; without one it can only produce generalities.

## User examples

> Secure my data — threat model this before we build it.

> What's the redundancy plan if the database host dies?

> Review my architecture for security and reliability.

> What happens when the queue backs up or the region goes down?

## Model selection cues

Select this skill when the user says "secure my data", "threat model this", "redundancy plan", "data protection", "review my architecture for security", or asks what happens when a component fails.

Do not select it for testing a live application (`web-pentest`, or `/security-review` for a diff), for a dependency's known CVEs (`dependabot-validator`), or when no design exists yet.

## Inputs the model should establish

| Input | Where it comes from |
|---|---|
| The project brief | `ideator-output/project-brief.md` |
| The architecture | `constructor-output/architecture-doc.md` |
| Security decisions already flagged | `constructor-output/security-flags.md` — the explicit hand-off |
| What data actually exists | Ask; "user data" is not specific enough to protect |
| Recovery objectives | How much loss and how much downtime is genuinely acceptable |
| Compliance obligations | GDPR, HIPAA, PCI, or none — this changes what is optional |

If the architecture is missing, say so and offer `/constructor` first. A threat model against an imagined design protects nothing.

## Example model plan

1. **Read the brief, the architecture, and the security flags.** The flags are `constructor`'s explicit hand-off — start there.
2. **Inventory the assets.** What data exists, where it lives, who touches it, and what it would cost to lose or leak. Write to `datasecurer-output/assets.md`.
3. **Threat-model against the real design** — entry points, trust boundaries, what an attacker gains at each. Write to `datasecurer-output/threat-model.md`.
4. **Plan the controls** proportionally. A hobby project does not need an HSM; say so rather than performing thoroughness.
5. **Plan redundancy** against stated recovery objectives, not against fear. Write to `datasecurer-output/redundancy-plan.md`.
6. **Name the conflicts.** Where the architecture and the security requirements genuinely disagree, write them to `datasecurer-output/architecture-conflicts.md` and put the trade-off to the user rather than silently choosing.

## Expected output

- `datasecurer-output/assets.md` — what's worth protecting, and why
- `datasecurer-output/threat-model.md` — threats against the actual design, with likelihood and impact
- `datasecurer-output/security-plan.md` — proportionate controls, each tied to a threat
- `datasecurer-output/redundancy-plan.md` — backup, failover, and recovery objectives
- `datasecurer-output/architecture-conflicts.md` — where security and the design disagree, for the user to settle

## Example result shape

```markdown
## Threat model — Team Habit Tracker

| Threat | Entry point | Impact | Likelihood | Control |
|---|---|---|---|---|
| Session hijack | Cookie without `Secure`/`SameSite` | Full account access | Medium | Set both; short expiry |
| Habit log leak | Public team URL guessable | Low — but personal | Medium | Unguessable team IDs, auth check |
| Total data loss | Single Postgres host | Project over | Low | Nightly dump off-host; RPO 24h agreed |

## Architecture conflicts

**Session storage.** The architecture puts sessions in-process for simplicity;
that breaks the moment there's a second instance, and forces a re-login on every
deploy. Options: sticky sessions (cheap, fragile), or Redis (one more component).
Six-week deadline argues for in-process now, with a note that scaling out
requires revisiting. **Needs your decision.**
```
