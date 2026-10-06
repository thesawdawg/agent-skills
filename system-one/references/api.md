# System One wire API

Every compatible server exposes the same two routes under a base URL. Hosted Jev
uses `https://api.typesafe.ai`; local servers use their own base URL (see
[local servers](local-servers.md)). Only the base URL and the key change.

## Routes

| Method | Path | Purpose | Success body |
| --- | --- | --- | --- |
| `POST` | `/v1/systemone` | Evaluate `state` against a map of typed questions | `{model, answers, usage}` |
| `GET` | `/v1/models` | List model names and aliases the endpoint accepts | `{models: [{name, description, release_date}]}` |

Headers: `Content-Type: application/json`; `Authorization: Bearer <API_KEY>` when
the server requires a key (hosted Jev always; local servers only when configured).

## Request body

```json
{
  "model": "jev-latest",
  "state": "Help! My payouts have been failing for 3 days.",
  "questions": {
    "is_urgent": { "type": "noul", "instructions": "Does `state` convey urgency?" }
  }
}
```

| Field | Type | Notes |
| --- | --- | --- |
| `model` | string | Required by hosted Jev. Alias (`jev-latest`, `jev-preview`) or pinned id (`jev-1.13.0`). The response's `model` reports the versioned id that answered. Local servers also accept their own names and default when `model` is `jev-latest` or omitted. |
| `state` | string, object, or array | The content every question refers to. Structure it so questions can name paths in backticks. |
| `questions` | map of id to Question | At least one. Ids are yours; they never reach the model and answers return under the same ids. |

## Question types

All three carry `type` and `instructions`. `instructions` may be a string, an
object, or an array; put the question in one field and supporting data in others,
then refer to that data by name in backticks.

**Noul** (`"type": "noul"`): yes/no. `criteria` is optional:
`{"true": <what yes means>, "false": <what no means>}`.

**Choice** (`"type": "choice"`): one option from a set. `criteria` is required: a
map of option name to description (string, object, array, or `null`). Up to 255
options.

**Score** (`"type": "score"`): a position on an ordered rubric. `criteria` is
required: an ordered array of 2 to 10 level descriptions, low to high.

## Answer types

```json
{
  "model": "jev-1.13.0",
  "answers": {
    "department": {
      "type": "choice",
      "choice": "billing",
      "probabilities": { "billing": 0.88, "technical": 0.12, "sales": 0.0 },
      "confidence": 0.81
    },
    "frustration": {
      "type": "score",
      "score": 1.3,
      "legend": { "0": "Calm", "1": "Frustrated", "2": "Very angry" },
      "probabilities": { "0": 0.1, "1": 0.5, "2": 0.4 },
      "confidence": 0.42
    },
    "is_urgent": { "type": "noul", "noul": 0.95 }
  },
  "usage": { "input_tokens": 318, "output_tokens": 34 }
}
```

| Type | Fields | Reading |
| --- | --- | --- |
| noul | `noul` | Probability of yes, 0 to 1. No `confidence`; distance from 0.5 plays that role. Some local servers add a `confidence` field; ignore it for portability. |
| choice | `choice`, `probabilities`, `confidence` | `choice` is the highest-probability option. Branch on it; gate the branch on `confidence`. |
| score | `score`, `legend`, `probabilities`, `confidence` | `score` is the probability-weighted level index and can fall between levels. Threshold or rank it; read `probabilities` before trusting a middle value. |

## Status codes

| Status | Meaning | Action |
| --- | --- | --- |
| 401 | Missing or invalid key | Check `TYPESAFE_API_KEY`; local servers without a key never return this. |
| 422 | Body failed validation (`{"detail": [...]}`) | Fix the field named in `detail`: missing `model`, wrong `criteria` shape, empty `questions`. |
| 429 | Rate limit (hosted: 100K tokens/s and 80 requests/s per account) | Back off; honor `retry-after` or `retry-after-ms`. |
| 408, 5xx, 529 | Transient | Retry with backoff. |
| 400, 413 | Request too large or malformed for this server | Shrink `state`; check the model's token and option limits. |

## Limits (hosted `jev-1.13.0`)

- 64k tokens for `state` plus all questions; 32k for `state` plus the longest
  single question.
- Text only; preprocess images, audio, and binaries into text or fields.
- Charged per input token; output tokens are free.
- English is the strongest language; test other languages and watch confidence.

Local models publish their own limits (typically 255 options, 10 levels, and a
model-specific context length); read them from `GET /v1/models` descriptions or
the server's README.

## Sources

- https://docs.typesafe.ai/api.md and https://docs.typesafe.ai/models.md
- https://docs.typesafe.ai/llms.txt lists every page; append `.md` for raw text.
