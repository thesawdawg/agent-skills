# ollama-delegate: Practical Use Cases

This guide shows **when to invoke `ollama-delegate`**, **how to recognize the
request**, **what to establish before starting**, and **what a successful
run looks like**.

See [README.md](README.md) for the API mechanics and [SKILL.md](SKILL.md)
for the operational workflow. This file is examples only. See also the
[top-level skills index](../USE_CASES.md).

## Use it when

Use `ollama-delegate` for tasks well-suited to a local or self-hosted model
— usually lighter-weight text work, or work the user specifically wants
kept off a hosted API — and especially when there are many independent
small tasks that benefit from running in parallel rather than one at a
time.

Good uses include:

- Summarizing or classifying a batch of files/records, one call per item, in parallel
- Drafting boilerplate text (commit messages, changelog entries, comments) from structured input
- Extracting structured fields from unstructured text at volume
- A quick second opinion from a specific local model the user wants to test
- Any task the user explicitly asks to run through Ollama, a local model, or a self-hosted model

Do **not** use it for tasks needing real reasoning depth, multi-file code
edits, or tool/file access — the model only sees the prompt text you give
it and has no way to act on the filesystem itself.

## User examples

> Use Ollama to summarize each of these 12 changelog files — run them in parallel.

> I've got llama3 running locally, use it to classify these support tickets as bug/feature/question.

> Delegate a first-pass draft of these API docs to my local Ollama model, then I'll polish it myself.

> We have an internal Ollama server at http://10.0.4.12:11434 — use that instead of localhost, and use the `mixtral` model.

> Ask the local model what it thinks of this function name before we commit to it.

## Model selection cues

Select this skill when the user asks for:

- "use Ollama" / "use my local model" / "run this through llama3 / mistral / etc."
- a self-hosted or external Ollama API endpoint specifically
- a batch of similar small tasks that would benefit from parallel dispatch
- explicit avoidance of a hosted API for a given piece of text

Do not select it when:

- The user hasn't mentioned Ollama or a local model, and the task needs real reasoning, tool use, or file edits — do that yourself or use `codex-delegate`
- Ollama isn't reachable at the given host — surface that rather than trying to start/install it
- The task is a single trivial thing not worth a round-trip

## Inputs the model should establish

Before starting, determine:

- **Host** — if the user names one, use it. Otherwise check `http://localhost:11434` first; if that's unreachable, ask the user for a host rather than guessing a remote address.
- **Model** — if the user names one, use it. Otherwise list available models on the resolved host (`ollama-task.sh models <host>`) and ask the user to pick one — never guess or default to the first entry.
- **One-shot vs multi-turn** — most batch/classification work is one-shot (`run`); an iterative back-and-forth needs `start`/`send` with a state file.
- **Parallel or sequential** — if there are N independent items, plan to fan them out concurrently; only serialize if they share a `start`/`send` thread.
- **What "done" looks like** — the output format expected back, and whether it needs validation before being used downstream.

## Example model plan

1. Resolve the host: use it if the user named one; otherwise check `http://localhost:11434` first, and ask the user for a host if that's unreachable.
2. Resolve the model: use it if the user named one; otherwise list models on that host and ask the user to pick one.
3. For a batch of N independent items: launch `scripts/ollama-task.sh run <host> <model> "<prompt for item i>"` for each item in parallel (background Bash calls or a Task subagent per item).
4. For an iterative task: `start` once with a state file, then `send` for each follow-up.
5. Review each reply — local models are more prone to off-format or off-task output than Claude/Codex; validate before using results downstream (e.g. as JSON, as code).
6. Report the aggregated results to the user.
7. `rm -f <state-file>` for any multi-turn threads once done.

## Expected output

A useful run leaves:

- The model's reply text for each task, already extracted from the raw API response
- For batches, a clear per-item mapping of input → output
- A note on anything that looked malformed or off-task and was excluded or flagged
- No dangling state files for multi-turn threads

## Example result shape

```
--- reachability check ---
$ curl -fsS http://localhost:11434/api/tags | jq -r '.models[].name'
llama3:8b
mistral:7b

--- parallel batch (3 files) ---
$ scripts/ollama-task.sh run http://localhost:11434 llama3:8b "Summarize in one sentence: <file1 contents>"
Adds retry logic with exponential backoff to the webhook dispatcher.
$ scripts/ollama-task.sh run http://localhost:11434 llama3:8b "Summarize in one sentence: <file2 contents>"
Migrates the users table to add a nullable `deleted_at` column.
$ scripts/ollama-task.sh run http://localhost:11434 llama3:8b "Summarize in one sentence: <file3 contents>"
Fixes an off-by-one error in the pagination cursor.
[all three launched concurrently, reviewed individually]

--- cleanup ---
(no state files — all one-shot)
```

Report to the user: the per-item summaries, and that each was spot-checked
against its source file before being reported.
