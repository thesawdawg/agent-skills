---
name: ollama-delegate
description: Offload a task to a local or remote Ollama model as an external subagent, over the Ollama HTTP API. Unlike a single-threaded CLI subagent, multiple independent Ollama calls can run concurrently — use this to fan out several parallel, low-to-medium-stakes tasks (classification, summarization, extraction, drafting, bulk transforms) to a model running on the user's machine or a reachable Ollama server, keeping Claude's own context free of the raw work. Use when the user asks to use Ollama, a local model, or a self-hosted model for a task.
---

# Ollama Delegate

Runs tasks through the Ollama HTTP API (`/api/generate` for one-shot, `/api/chat` for multi-turn) rather than shelling out interactively. Works against `http://localhost:11434` (the default local Ollama daemon) or any other reachable Ollama-compatible API base URL the user gives you — including an external/remote Ollama instance.


## When to use this

**Use it for:** a task suited to a smaller/local model that doesn't need Claude-level reasoning — summarization, classification, extraction, translation, bulk drafting, format conversion, or a first pass on many similar items. Also use it when the user explicitly asks for Ollama or a local/self-hosted model.

**Don't use it for:** tasks that need deep reasoning, multi-file code changes, or tool use — Ollama models here are called through a plain HTTP API with no file access, no shell, and no tools of their own. If the task needs to read/write real files or run commands, do that yourself or use `codex-delegate`, then optionally hand only the text content to Ollama.

**This skill parallelizes.** Ollama's daemon can serve multiple requests concurrently (subject to its own queuing/`OLLAMA_NUM_PARALLEL` config), so unlike `codex-delegate`'s strict one-at-a-time rule, you may fire off several independent `run` calls — e.g. one per file, one per item in a batch — at once. Still keep each multi-turn `start`/`send` *thread* sequential (a single state file is one conversation; don't send to it from two calls at once).

## Prerequisites: resolving host and model

Do this once per task, in order, before any `run`/`start` call:

1. **Resolve the host.** If the user already named a host (local or an external/remote Ollama API URL), use it. Otherwise, check localhost first:
   ```bash
   curl -fsS --max-time 5 http://localhost:11434/api/tags
   ```
   If that succeeds, use `http://localhost:11434`. If it fails (no daemon running locally), **ask the user** for a host — don't guess a remote address and don't try to install/start Ollama yourself.

2. **Resolve the model.** If the user already named a model, use it as given (don't second-guess it against the list). Otherwise, list what's actually available on the resolved host:
   ```bash
   scripts/ollama-task.sh models <host>
   ```
   Then **ask the user to pick one** from that list — never silently default to the first entry or guess a model name that may not be pulled. If the list is empty, tell the user no models are available on that host instead of proceeding.

Only after both host and model are settled should you make the actual `run`/`start` call.

## Mechanics

All calls go through `scripts/ollama-task.sh`, which wraps `curl` against the Ollama API and hands back only the model's reply text — the raw HTTP JSON never needs to enter your context beyond that.

**One-shot task** (no follow-up needed):

```bash
scripts/ollama-task.sh run <host> <model> "<self-contained prompt>"
```

**Multi-turn conversation** (need follow-ups building on prior context):

```bash
scripts/ollama-task.sh start <state-file> <host> <model> "<system prompt or empty string>" "<first prompt>"
scripts/ollama-task.sh send  <state-file> "<next prompt>"
```

`<state-file>` is a JSON file holding the running message history — pick one per conversation (e.g. under the scratchpad), never reused across unrelated tasks. Pass `""` for the system-prompt argument to skip it.

**List models on a host:**

```bash
scripts/ollama-task.sh models <host>
```

## Writing prompts for Ollama

The model has no visibility into this conversation and, unlike Codex, no file or shell access at all — everything it needs must be *in the prompt text itself*:

- The actual content to work on (paste it in, or read the file yourself first and inline the relevant excerpt)
- What output format you want back (plain text, a specific structure, a list)
- Any constraints on length or style

Local/smaller models are typically weaker at following complex multi-part instructions than Claude or Codex — keep each individual task focused and check the output before trusting it downstream, especially for anything structured (JSON, code) that you plan to parse programmatically.

## Fan-out pattern for parallel batches

For N independent one-shot tasks, launch N `run` calls in parallel (e.g. via background Bash calls or a Task subagent per item) rather than looping sequentially — this is the main advantage over `codex-delegate` here. Collect and review each result before using it; a local model is more likely to produce a malformed or off-task response than Codex or Claude, so don't chain its output into further automation unchecked.

## Cleanup

Multi-turn state files only need to live as long as the conversation does:

```bash
rm -f <state-file>
```

The Ollama daemon itself keeps no server-side session — deleting the state file just forgets the message history on Claude's side.

Use one writer per state file. `start` refuses existing state; malformed provider
responses fail without changing conversation state. HTTP requests are bounded
by connection and overall timeouts. Validate semantic output before using it.
