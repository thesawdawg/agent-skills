# Codex CLI — Scripted/Non-Interactive Usage Reference

Background reference for this skill's design. `SKILL.md` says what to do; this
file documents why it's safe to do and where the facts came from, so the
design can be re-verified later without repeating the research.

## Relevant CLI surface (verified against `codex-cli 0.142.5`)

- `codex exec [PROMPT]` — runs Codex non-interactively, invoked as a single
  binary call rather than the interactive TUI. Progress streams to stderr;
  the final agent message is what you actually want.
- `codex exec resume <THREAD_ID|--last> [PROMPT]` — continues a previous
  thread. Confirmed empirically: a resumed thread recalls facts from earlier
  turns (Codex replays its own history internally each turn).
- `--json` — emits JSONL events (`thread.started`, `item.completed`,
  `turn.completed`, ...) to stdout. `thread.started` is where the thread id
  comes from; parsed by `scripts/codex-session.sh`.
- `-o, --output-last-message <FILE>` — writes only the final reply to a file,
  separate from the event stream. This is what keeps the JSONL trace and
  reasoning out of Claude's context — only the file's contents get read.
- `-s, --sandbox <read-only|workspace-write|danger-full-access>` — only
  accepted by `codex exec` (session start). **Not accepted by `codex exec
  resume`** — confirmed by testing (`error: unexpected argument '-s' found`).
  A session's sandbox is fixed for its whole lifetime.
- `codex login status` — exits 0 when credentials are present; used as a
  cheap pre-flight check. No credential handling happens in this skill's
  script at all — auth is entirely the user's pre-existing `codex login`
  session.

## Sandbox modes (from OpenAI's docs)

| Mode | Behavior |
|---|---|
| `read-only` | No file writes, no command execution. Analysis/audit only. |
| `workspace-write` | Reads, edits within the working directory, runs commands. Network disabled by default. This is `codex exec`'s own default when no `-s` is given. |
| `danger-full-access` | No sandbox, no approvals — full system access. OpenAI's docs: *"reserved for trusted environments only"* (e.g. an isolated CI runner or container) and explicitly discouraged otherwise. |

Protected paths (`.git`, `.agents`, `.codex`) stay read-only even under
`workspace-write`.

## Approval policies

Codex layers approval prompts on top of the sandbox (`on-request`, `never`,
`untrusted`, or granular category rules). In practice, `codex exec` does not
expose an `--ask-for-approval` flag at all (only `codex exec resume` and the
interactive CLI do) — non-interactive `exec` runs to completion under the
chosen sandbox without pausing for approval, since there's no TTY to prompt
on. Verified empirically: `codex exec -s workspace-write "<prompt that
writes a file>"` completed and wrote the file without hanging or requiring
any approval flag.

This skill's script never sets an approval-bypass flag
(`--dangerously-bypass-approvals-and-sandbox`) — that flag exists in the CLI
but is deliberately not used or exposed here.

## Policy check (2026-07-04)

Verified this skill's design against OpenAI's own documentation before
relying on it:

- Non-interactive `codex exec` is a first-party, documented feature built
  specifically for scripts/CI — not a workaround.
- `codex exec resume` for continuing a prior run is explicitly documented
  and is the intended mechanism for exactly what this skill does.
- Escalating to `workspace-write` for automated workflows is documented as
  normal, expected practice.
- `danger-full-access` is explicitly flagged by OpenAI as discouraged
  outside isolated/trusted environments — this skill treats it as a
  last-resort, confirm-before-starting option (see `SKILL.md`), matching
  that guidance rather than defaulting to it.

No use of credential extraction, approval-bypass flags, or rate-limit/ToS
evasion is present anywhere in this skill.

Sources:
- https://developers.openai.com/codex/noninteractive
- https://developers.openai.com/codex/agent-approvals-security
- https://developers.openai.com/codex/cli/reference
