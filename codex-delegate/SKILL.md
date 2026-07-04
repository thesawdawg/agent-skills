---
name: codex-delegate
description: Delegate a medium-to-high importance implementation, refactor, debugging, or audit task to the Codex CLI as a single external subagent, keeping one continuous Codex session alive and resumed sequentially across steps so Claude's own context only ever holds Codex's final replies. Use when a task is substantial enough to deserve a second model's full, focused attention on the real files — a real implementation, a multi-file refactor, a thorough investigation — but not for trivial one-liners or pure Q&A that don't need a second opinion.
---

# Codex Delegate

Runs the `codex` CLI (user is already authenticated) as a single, sequential external subagent. One Codex conversation thread is opened per task and resumed for every follow-up step — never more than one Codex process running at a time, and never more than one thread per task.

See also: [README.md](README.md) for the underlying CLI mechanics and the policy check behind this design, [USE_CASES.md](USE_CASES.md) for trigger phrases and a worked example, and the [top-level skills index](../USE_CASES.md) for how this skill fits alongside the others.

## When to use this

**Use it for:** a real implementation task, a multi-file refactor, a from-scratch investigation/audit, or anything where you'd otherwise spin up a heavyweight `Agent` subagent — i.e. medium-to-high importance work worth a second model's dedicated attention on the actual codebase.

**Don't use it for:** a one-line fix, a question you can answer by reading a file yourself, or anything where the overhead of a round-trip (tens of seconds, a fresh model spin-up) outweighs the benefit. Don't reach for this reflexively on every task — treat each delegation like you would a subagent dispatch: deliberate, not default.

**Don't parallelize it.** This skill is explicitly sequential: one Codex session, one turn at a time. If you have several genuinely independent tasks, either run them through this skill one after another, or use Claude's own `Agent` tool for concurrent work — don't run multiple `codex exec` processes against the same thread or the same working tree at once.

## Prerequisites

The user is pre-authenticated. Confirm once per session if you haven't already:

```bash
codex login status
# expect: Logged in using ChatGPT (or API key)
```

If not logged in, stop and tell the user to run `codex login` themselves — don't attempt to manage credentials for them.

## Mechanics

All interaction goes through `scripts/codex-session.sh`, which wraps `codex exec` / `codex exec resume` and hands back only Codex's final reply — the full JSONL event stream and reasoning trace never enter Claude's context. That's the token-saving mechanism: Codex's thread grows every turn (it replays its own history internally), but your context only ever grows by one reply per turn.

Pick a state file to track the thread id for this task — e.g. `<scratchpad>/.codex-session-id`. One state file = one Codex session = one task. Don't reuse a state file across unrelated tasks.

**Start the session** (first delegation in the task):

```bash
scripts/codex-session.sh start <state-file> <sandbox> "<self-contained prompt>"
```

**Resume it** (every subsequent step in the same task):

```bash
scripts/codex-session.sh send <state-file> "<self-contained prompt>"
```

Both print Codex's final message to stdout and nothing else on success. On failure they print the raw event log to stderr and exit non-zero — read that log yourself to diagnose; don't retry blindly.

### Sandbox is fixed for the life of the session

`<sandbox>` is one of `read-only`, `workspace-write`, `danger-full-access`, chosen only at `start`. `codex exec resume` does not accept `-s` — it inherits whatever the session started with, so you cannot upgrade read-only to workspace-write mid-thread.

Decide up front: if *any* step you plan to delegate in this task will need to write files, `start` with `workspace-write`. If the whole task is pure investigation/analysis/review, use `read-only`. `danger-full-access` removes sandboxing and approvals entirely — OpenAI's own docs call it reserved for trusted, isolated environments (a container or CI runner) and explicitly discourage it otherwise. Treat it as a last resort, not a default escalation from `workspace-write`, and only use it with the user's explicit go-ahead given *before* starting the session, not after.

## Writing prompts for Codex

Codex has no visibility into this conversation. Each prompt — especially the first — must be self-contained the same way you'd brief a fresh subagent:

- What to do, concretely, and why it matters
- Relevant file paths / project conventions it can't infer
- What "done" looks like (tests passing, a specific behavior, a specific file produced)
- Anything the earlier turns in *this* Codex thread already established (Codex remembers its own thread, but doesn't know what happened in your conversation with the user before you invoked it)

Since the thread already carries its own history, later `send` prompts can be short and refer back to what Codex already did ("now add tests for the function you just wrote") — no need to re-paste context Codex already has.

## After a workspace-write turn: verify before reporting

Codex edits real files directly when running `workspace-write` — this is not a preview or a diff to approve, it already happened. After any `start`/`send` call in `workspace-write` (or `danger-full-access`) mode:

```bash
git status
git diff --stat
```

Read the actual diff, not just Codex's summary of what it did — a subagent's self-report and its real diff can diverge. Surface the real changes to the user before declaring the task done, same as you would for your own edits.

## When to start a fresh session instead of resuming

Resuming is for continuing the *same* task. Start a new session (new state file, new `start` call) when:

- The next piece of work is genuinely independent of what the thread has done so far
- The thread has grown long enough that resumes are getting slow or the context feels diluted (there's no hard threshold — use judgment, the same way you'd decide a Claude subagent's context is getting crowded)

Don't resume an old task's session for unrelated new work just because a state file happens to exist.

## Cleanup

The state file only needs to live as long as the task does. Delete it when the task wraps up:

```bash
rm -f <state-file>
```

The underlying Codex session itself persists on disk regardless (`codex resume --last` / `codex resume <id>` can revisit it interactively) — deleting the state file only forgets the thread id on Claude's side, it doesn't delete Codex's session.
