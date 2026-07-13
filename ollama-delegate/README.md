# Ollama HTTP API — Reference

Background reference for this skill's design. [SKILL.md](SKILL.md) says what
to do; this file documents the API surface it relies on. See also
[USE_CASES.md](USE_CASES.md) for example invocations and the
[top-level skills index](../USE_CASES.md).

## Relevant API surface

Ollama exposes a local HTTP daemon by default at `http://localhost:11434`
(also reachable over a network if the user has configured
`OLLAMA_HOST=0.0.0.0` or is pointing at a remote/external Ollama instance —
this skill treats the host as a parameter, not a hardcoded constant).

- `GET /api/tags` — lists locally available models. Used as a reachability
  check and to let the user pick a model without guessing a name.
- `POST /api/generate` — one-shot completion. Body: `{"model", "prompt",
  "stream": false}`. Response JSON has a `.response` field with the full
  text (with `"stream": false` it's a single JSON object, not an event
  stream, which is what keeps parsing simple with `jq`).
- `POST /api/chat` — multi-turn chat completion. Body: `{"model",
  "messages": [{"role", "content"}, ...], "stream": false}`. Response JSON
  has `.message.content`. This skill's `start`/`send` commands maintain the
  growing `messages` array in a local state file and resend the full history
  each turn — Ollama's API is stateless server-side, so the client (this
  script) owns conversation continuity, unlike Codex's server-side thread
  IDs.

## Why no CLI (`ollama run`) usage

The `ollama run <model> "<prompt>"` CLI is interactive-first (TTY prompting,
streamed output) and awkward to script reliably for structured single-shot
or multi-turn use. The HTTP API is the documented, stable interface for
non-interactive/programmatic use and is what this skill's script uses
throughout — `ollama` itself doesn't need to be on `PATH` at all, only the
API needs to be reachable, which is what makes remote/external Ollama
instances work the same way as a local daemon.

## Concurrency

Ollama's daemon can serve multiple requests concurrently, controlled by
`OLLAMA_NUM_PARALLEL` and `OLLAMA_MAX_LOADED_MODELS` on the server side (the
user's Ollama config, not something this skill sets). Because of this, the
skill explicitly permits parallel `run` calls for independent one-shot
tasks — unlike `codex-delegate`, which is deliberately serialized because
Codex CLI sessions are single-threaded per working tree. A single multi-turn
`start`/`send` state file is still sequential: sending two requests against
the same state file concurrently would race on which reply gets appended
last.

## No sandboxing model

Ollama models called this way have no tool use, no file access, and no
shell — the API only ever returns generated text for whatever was in the
prompt. There is no equivalent of Codex's `read-only` /
`workspace-write` / `danger-full-access` sandbox distinction because there's
nothing here that can touch the filesystem in the first place. Any file
reading/writing implied by a task must happen on the Claude side, before or
after the Ollama call.
