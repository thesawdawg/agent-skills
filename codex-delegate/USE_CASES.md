# codex-delegate: Practical Use Cases

This guide shows **when to invoke `codex-delegate`**, **how to recognize the request**, **what to establish before starting**, and **what a successful run looks like**.

See `README.md` for the underlying CLI mechanics and policy verification, and `SKILL.md` for the operational workflow itself. This file is examples only.

## Use it when

Use `codex-delegate` when a task is substantial enough to deserve a second model's full, dedicated attention on the real files — and when you want that work done without flooding Claude's own context with a second model's reasoning trace.

Good uses include:

- A real implementation task (a feature, an endpoint, a migration script)
- A multi-file refactor
- A from-scratch investigation or audit ("why is this failing," "find every place X pattern is used and assess it")
- Getting a second model's independent take on a design or a diff before committing to it
- Any task where you'd otherwise reach for a heavyweight `Agent` subagent, but specifically want Codex's perspective/model rather than another Claude instance

Do **not** use it for a one-line fix, a question answerable by reading a file yourself, or anything where the round-trip overhead (tens of seconds, a fresh model spin-up) outweighs the benefit. It is also not a way to run two things at once — it is strictly sequential, one Codex turn at a time.

## User examples

> Delegate the rate-limiter refactor to Codex — have it split the middleware into its own module and add tests.

> Use Codex to investigate why the checkout webhook is dropping events. Have it dig through the handler and report back before we touch anything.

> Get Codex's opinion on this API design before we implement it — read-only, no file changes.

> Have Codex implement the CSV export endpoint, then in a follow-up ask it to add the missing error handling once we see the first pass.

> I want a second model's eyes on this migration. Delegate it to Codex.

## Model selection cues

Select this skill when the user asks for:

- "delegate this to Codex" / "use Codex for this" / "have Codex do X"
- "get a second opinion / second model" on a design, diff, or bug
- a task they explicitly want handled by Codex rather than a Claude subagent
- a multi-step task where they want one continuous Codex conversation ("have it do X, then Y based on what it found")

Do not select it when:

- The task is small enough to just do directly (don't add a round-trip for its own sake)
- The user wants several independent things done concurrently — that's `Agent`, not this (this skill is deliberately sequential/single-session)
- Codex isn't authenticated (`codex login status` fails) — surface that to the user instead of trying to work around it
- The user hasn't said or implied Codex specifically — don't default to this skill just because a task is "big"; a Claude `Agent` subagent is still the default for large Claude-only work

## Inputs the model should establish

Before starting, determine:

- **Scope of this task** — is it one shot, or will there be follow-up steps in the same thread?
- **Sandbox mode** — will Codex need to write files (`workspace-write`), or is this pure analysis (`read-only`)? Decide once, up front — it can't change mid-session.
- **Whether `danger-full-access` is genuinely needed** — if so, get the user's explicit go-ahead before starting, not after (see `SKILL.md`/`README.md` for why).
- **State file location** — one state file per task (e.g. under the scratchpad), not reused across unrelated work.
- **What "done" looks like** — a specific behavior, passing tests, a specific file, an answer to a specific question — so the prompt to Codex is self-contained.

## Example model plan

1. Confirm `codex login status` succeeds.
2. Decide the sandbox mode for the whole task (`read-only` vs `workspace-write`; confirm with the user first if `danger-full-access` seems necessary).
3. `scripts/codex-session.sh start <state-file> <sandbox> "<self-contained prompt>"` — the first prompt carries all the context Codex needs, since it can't see this conversation.
4. If the sandbox was `workspace-write`, run `git status` / `git diff --stat` and read the actual diff — don't just trust Codex's self-reported summary.
5. For each follow-up step: `scripts/codex-session.sh send <state-file> "<next instruction>"`, referring back to what Codex already did rather than re-explaining it.
6. After the final step, verify any remaining file changes, then report Codex's findings/output and the verified diff to the user together.
7. `rm -f <state-file>` once the task is wrapped up.

## Expected output

A useful run leaves:

- Codex's final reply for each turn (already captured, not the full reasoning trace)
- A verified `git diff` for any turn that wrote files — checked by the model, not just relayed from Codex's own claim
- A clear statement of what was delegated vs. what still needs the user's review or a follow-up turn
- No dangling state file once the task is done

## Example result shape

```
--- start (workspace-write) ---
$ scripts/codex-session.sh start .codex-session-id workspace-write \
    "Add input validation to POST /users: reject missing email or password
     with a 400 and a JSON error body. Add a test for both cases."
Added validation to `handlers/users.go` and two table-driven test cases in
`handlers/users_test.go`. Both pass.

--- verify ---
$ git diff --stat
 handlers/users.go       | 14 ++++++++++++++
 handlers/users_test.go  | 22 ++++++++++++++++++++++
 2 files changed, 36 insertions(+)
[diff reviewed — matches the summary, no unrelated changes]

--- send (follow-up, same session) ---
$ scripts/codex-session.sh send .codex-session-id \
    "Also reject an empty-string password, not just a missing field."
Updated the check in `handlers/users.go` to treat an empty string the same
as a missing field; added one more test case, still passing.

--- verify ---
$ git diff --stat
 handlers/users.go       | 16 ++++++++++++++++
 handlers/users_test.go  | 30 ++++++++++++++++++++++++++++++
 2 files changed, 46 insertions(+)

--- cleanup ---
$ rm -f .codex-session-id
```

Report to the user: what was implemented, that the diff was checked and matches the description, and that the session/state file has been cleaned up.
