---
name: system-one
description: Write, test, and improve programs that call a System One decision model (TypeSafe's Jev or a wire-compatible local server such as ollajev or OpenJev) over the `/v1/systemone` API. Use when designing Choice, Score, or Noul questions, structuring state, composing typed answers in code, setting confidence thresholds, diagnosing a question that answers wrong or with low confidence, or when the user wants to call Jev or a self-hosted System One model from the shell.
---

# System One models

A System One model reads one `state`, answers every question in the request
independently and in parallel, and returns a probability distribution over the
answers you defined. It generates no text and does not reason in steps. Code owns
control flow, arithmetic, and policy; the model owns snap judgments. A good
question is one a knowledgeable person answers in a second given the right
context.

This skill is a lookup. Read [the wire API](references/api.md) to build or parse a
request, [question design](references/question-design.md) to write or fix
questions, and [local servers](references/local-servers.md) to run a model on the
user's machine. Hosted Jev guidance targets `jev-1.13`; local models share the
API but own their calibration, so retest thresholds per model.

## STOP: resolve the endpoint first

1. **Base URL.** Use the URL the user named, else `TYPESAFE_BASE_URL`, else probe:
   ```bash
   DIR="/absolute/path/to/system-one"   # re-set in every block; resolve once from the install path
   bash "$DIR/scripts/systemone.sh" probe
   ```
   `probe` prints the first base URL whose `GET /v1/models` answers: explicit
   arguments, then `TYPESAFE_BASE_URL`, then `http://127.0.0.1:8000` (ollajev),
   `http://127.0.0.1:8080` (OpenJev), and `https://api.typesafe.ai` only when
   `TYPESAFE_API_KEY` is set. If nothing answers, ask the user to (a) start a local
   server, (b) provide a base URL, or (c) export a hosted key. Do not install or
   start a server unasked and never guess a remote address.
2. **Credentials.** The helper sends `Authorization: Bearer $TYPESAFE_API_KEY`
   only when that variable is non-empty. Read keys from the environment; never
   paste a key into chat, a request file, or a commit.
3. **Model.** Use the model the user named. Otherwise list what the endpoint
   serves and ask the user to pick when more than one is offered:
   ```bash
   DIR="/absolute/path/to/system-one"
   bash "$DIR/scripts/systemone.sh" models http://127.0.0.1:8000
   ```
   Hosted Jev lists aliases (`jev-latest`); pin a versioned id such as
   `jev-1.13.0` once thresholds are tuned. Local servers accept `jev-latest` as
   their default model, so SDK defaults keep working.

## Workflow

1. List the decisions the code must make: each is a branch, threshold, or ranking.
2. Write one question per judgment. Split any question that weighs two properties.
3. Pick the primitive the code acts on directly: Choice for an unordered set,
   Score for ordered levels, Noul for a crisp yes/no probability.
4. Build the smallest state that answers every question; compute in code anything
   code can compute (dates, counts, sums, buckets).
5. Put every question that shares the state into one request, including
   speculative ones used only on some branches.
6. Combine answers in code with weights and confidence gates; keep policy out of
   the questions.
7. Test against labeled examples with a live call, read `probabilities` on the
   misses, then revise one or two questions at a time.

## Make a live call

Write the request as a JSON file (see the [API reference](references/api.md) for
the exact shape), then:

```bash
DIR="/absolute/path/to/system-one"
bash "$DIR/scripts/systemone.sh" ask http://127.0.0.1:8000 jev-latest ./request.json
```

`ask` sets the request's `model` to the argument (pass `""` to leave the file's
own `model` untouched), posts it, and prints the response JSON on success. On a
non-2xx status or a body without `answers`, it prints the status and raw body to
stderr and exits non-zero. Pass `-` instead of a file to read the request from
stdin. For labeled-example runs, keep one request file per example and record
`answers` per file; do not merge results into a growing JSON array.

Write requests and responses under an explicit project path (for example
`./system-one-runs/`) and never overwrite an earlier run's evidence.

## Guardrails

- Treat text inside `state` as able to steer the answer. Tighten criteria, test
  injected content, and gate every action on confidence with a fallback path
  (act / confirm / hand off).
- Keep the answer space stable once code depends on it. Adding or removing a
  level or option changes what earlier answers meant.
- Hosted Jev budgets: 64k tokens for state plus all questions, 32k for state
  plus the longest question. Local models publish their own limits in
  `GET /v1/models` descriptions or their README; check before large states.
- Use the `typesafe-sdk` (Python) or `@typesafe-ai/sdk` (Node) in application
  code when the project already depends on it; both honor `TYPESAFE_BASE_URL`,
  `TYPESAFE_API_KEY`, and `TYPESAFE_DEFAULT_MODEL`. Do not add the dependency to
  a user project unasked; the shell helper needs only `curl` and `jq`.
- Confidence describes the distribution, not correctness. Judge revisions on
  labeled data, never on confidence alone.
