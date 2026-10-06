# Question design

Use this file to write a question, pick a primitive, build state, compose
answers, or diagnose a miss. Jump to the matching section.

## Choose the primitive

| Primitive | Use when | Code acts with |
| --- | --- | --- |
| Choice | The answer is one of a known, unordered set | a branch per option |
| Score | The answer is a position on a spectrum you can describe in steps | a threshold, rank, or weight |
| Noul | The answer is a clean yes or no and the probability is the signal | an `if` on a threshold |

- Add an `other` or `none_of_the_above` option to any Choice whose list may not
  cover every input.
- A Noul at 0.5 means unsure, not "medium". Measure a degree with a Score.
- A Noul needs a crisp condition. "Is the candidate strong in Python?" is vague;
  "Does `resume` state that the candidate used Python at work?" is crisp.

## Write instructions

- State the exact condition. The model reads scoping words, negations, and
  implied conditions literally.
- One property per question. A hidden second judgment lowers accuracy.
- Name the state path the question judges in backticks: `` `ticket.messages[0].text` ``.
- Avoid double negatives, properties of properties, and multi-hop questions.
- Keep numerals that stand for levels out of instructions ("rate 0 to 2" gives
  nothing to match).
- Put the full question in `instructions`; the id never reaches the model.
- Keep policy out of the question ("a shared address cannot override a name
  conflict" belongs in code).
- When you explain after a wrong answer what you really meant, that explanation
  is the missing half of the instruction. Add it.

Use object instructions for labeled parts or supporting data; pass schemas,
taxonomies, or rows as JSON rather than serialized into a template string.
Useful keys: `question`, `focus`, `inspect`, `note`, `compare` (list of state
paths), `field` (a shared `name`/`type`/`unit`/`description` record).

## Write criteria

Criteria extend the instruction and must point the same direction.

- **Choice:** describe each option; make descriptions contrastive when options
  sit close. An option value may be an object such as
  `{"what": ..., "not_for": ..., "examples": [...]}`.
- **Score:** list levels low to high, two to ten, each a standalone situation
  ("broken feature, workaround exists"), never a degree word or a comparison
  to a neighbor. The model judges each level separately and sees neither its
  number nor its neighbors. Give a rare extreme its own level when code treats
  it differently. Keep one dimension per Score.
- **Noul:** criteria are optional; add `true` and `false` sides with `what` and
  `examples` when the boundary is subtle, and place the neighboring case on the
  side it belongs to.
- **Examples:** short concrete instances ("I was charged twice"), not
  descriptions of instances.

## Build state

- Send only the fields the questions need. Unrelated detail lowers accuracy and
  hides which input caused a miss.
- Retrieve and filter in code first; when code cannot filter, ask a relevance
  Noul per passage and keep the passes.
- Convert encodings to words (color names, named buckets); compute date order,
  durations, counts, and sums in code and send the result.
- Keep text in state untrusted: it can steer answers. Say in criteria what
  counts, and test injected or self-describing content before deployment.

## Compose answers in code

- **Speculative fan-out:** ask every question code might need in one request;
  parallel questions add little latency. Ignore unused answers.
- **Second request** only when code cannot build it without the first answer.
  Questions in one request never see each other's answers.
- **Confidence-gated routing:** the answer says what, confidence says whether to
  act. Set a floor (docs use 0.5 to 0.6) and raise per-action thresholds with
  the cost of a wrong call (0.85 to 0.9 for high stakes). Paths: act, confirm or
  flag, hand off.
- **Composite scoring:** one Score per dimension, normalize by
  `len(criteria) - 1`, combine with weights in code. Change a weight, not a
  question, when policy shifts.
- **Intent routing:** a Choice for intent plus a complexity Score; route each
  intent to deterministic code, a specialist model, or a person.
- **Taxonomy walk:** one Choice per tree level, each option carrying its subtree
  as criteria; follow several branches when probabilities are close.
- **Counting:** the model does not count. One Noul per item, summed in code.
- **Dates:** a Choice per date part with a "not stated" option; assemble and
  compare in code.
- **Extraction:** generate candidates with a regex or generative model, then a
  Choice to pick or a Noul to verify.

```python
from typesafe_sdk import Choice, Noul, Score, TypeSafeClient

SEVERITY = [
    "Cosmetic; no impact to functionality",
    "Broken or degraded feature; a workaround exists",
    "Blocking issue; no workaround exists",
]

# base_url and api_key default to TYPESAFE_BASE_URL / TYPESAFE_API_KEY.
with TypeSafeClient(base_url="http://127.0.0.1:8000", api_key="local") as client:
    response = client.system_one(
        state={"ticket": ticket_text},
        questions={
            "category": Choice(
                instructions="Which category fits the main request in `ticket`?",
                criteria={"bug_report": "Something is broken", "billing": "Charges or refunds", "other": None},
            ),
            "severity": Score(instructions="How severe is the issue in `ticket`?", criteria=SEVERITY),
            "refund_requested": Noul(instructions="Does `ticket` explicitly ask for a refund or credit?"),
        },
    )

category = response.choices["category"]
if category.choice == "bug_report" and category.confidence > 0.6:
    severity = response.scores["severity"]
    if severity.score / (len(SEVERITY) - 1) > 0.75 and severity.confidence > 0.5:
        escalate()
```

The SDK rejects an empty `api_key`, so pass any placeholder for a keyless local
server; the helper script omits the header instead.

## Read answers

- `score` is the probability-weighted mean of level indices; 1.0 can mean
  certainty on level 1 or an even split of 0 and 2. Read `probabilities`.
- Threshold, rank, or round a score; do not interpolate a quantity from it.
- `confidence` measures how peaked the distribution is, not correctness.
- A Noul's distance from 0.5 is its confidence.
- Answers always stay inside the options supplied; code never parses prose.

## Diagnose a miss

Collect labeled examples, run them, and compare each question's answers and
probabilities to the labels before changing anything.

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Wrong answer, high confidence | Instruction read literally | State the exact condition; put the boundary case in criteria |
| Low confidence on a Choice | Options overlap or none fits | Add `what`/`not_for`/`examples`; add `other` |
| Low confidence on a Score | Levels overlap, two properties, or thin state | Rewrite levels as situations; split; add the missing field |
| Scores cluster mid-scale | Levels are degrees or numbers | Describe a concrete situation per level; remove numerals |
| Top-of-scale cases look alike | Extreme has no level | Add a level for it |
| Noul hovers near 0.5 | Vague condition | Define it; add `true`/`false` criteria with examples |
| Accuracy falls as input grows | Irrelevant state | Filter in code; send only needed fields |
| Errors on counts, sums, dates | Model doing arithmetic | Move arithmetic to code; ask only per-item judgments |
| Errors on nested or negated questions | Too much indirection | Ask directly; name the path; split and combine in code |
| Answer follows text inside state | Content steers the model | Tighten criteria; test adversarial cases; gate on confidence |
| Rewording trades one error for another | Several properties in one question | Split into atomic questions |
| Each answer right, decision wrong | Policy wrong | Change weights or thresholds in code |
| Slow or costly | Sequential calls | Merge into one request |
| Hosted answers differ from a local model | Different weights and calibration | Retune thresholds per model on labeled data; pin the model id in logs |

Revision rules: change one or two questions per round; judge on labeled data,
not confidence; keep the answer space stable once code depends on it; write
general rules in instructions and criteria, specific names only in `examples`.

## Checklist

- [ ] Each question asks one property a person could answer in a second.
- [ ] The primitive matches how code uses the answer.
- [ ] Instructions state the exact condition and name state paths in backticks.
- [ ] Criteria agree with instructions and point the same direction.
- [ ] Score levels are standalone situations with no numerals.
- [ ] Choices that may not cover every input have an `other` option.
- [ ] Code does all counting, arithmetic, and date comparison.
- [ ] State holds only what questions need and fits the model's limits.
- [ ] Questions sharing a state travel in one request.
- [ ] Every action has a confidence threshold matched to its risk and a fallback.
- [ ] Weights and thresholds live in code; labeled examples back every revision.

## Sources

- https://docs.typesafe.ai/primitives.md, `/primitives/choice.md`, `/primitives/score.md`, `/primitives/noul.md`, `/primitives/advanced.md`
- https://docs.typesafe.ai/concepts/state.md, `/confidence.md`, `/concepts/how-to-build-with-system-one.md`
- https://docs.typesafe.ai/patterns.md with `/fan-out`, `/confidence-routing`, `/composite-scoring`, `/intent-routing`
- https://docs.typesafe.ai/model-jaggedness/jev-1.13.md (recheck when the model changes)
