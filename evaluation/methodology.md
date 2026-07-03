# Spec-Driven Agent Skill Evaluation Methodology

## Purpose

This methodology evaluates whether an agent skill reliably causes a low-capability executor model to complete the task the skill claims to support. The target is not whether a strong model can infer the right workflow despite the skill. The target is whether the skill itself is clear, safe, portable, and operational enough for the lowest-capability model expected to use it.

## Definitions

**Skill under test**: A `SKILL.md` file plus any referenced scripts, templates, and references that the skill tells the executor to use.

**Scenario**: A complete, reproducible task prompt with setup, constraints, expected behaviors, and grading focus. A scenario must be concrete enough that two evaluators would agree on what success requires.

**Lowest-capability executor model**: The least capable model in the supported model set that is expected to handle the skill in production. It must support the required tool loop for the scenario. If a model cannot read files, run commands, or maintain enough context for the workflow, it is below the capability floor and should not be used for that scenario.

**Highest available judge model**: The strongest model available in the evaluation environment. It grades the executor transcript, tool outputs, and generated artifacts. It must not repair the executor output before scoring.

**Run transcript**: The full conversation, selected skill text, tool calls, tool outputs, files changed, artifacts produced, and final answer from the executor.

## Evaluation Principles

1. **Spec first**: The scenario spec is the authority. The judge scores against the scenario, the skill, and the metric, not against intent or plausibility.
2. **Skill causality**: Credit behavior that follows from the skill. Penalize success that required ignoring or guessing around ambiguous skill instructions.
3. **Low-model realism**: Scenarios must be possible for the lowest-capability executor model. They should expose ambiguity, hidden assumptions, missing guardrails, and tool-state mistakes.
4. **Evidence required**: The judge must cite transcript lines, artifact paths, command results, or file contents for every nonzero dimension.
5. **Safety before score**: Hard safety failures override numeric scoring.
6. **Comparable metric**: Every skill uses the same 100-point metric, with skill-specific expected behaviors supplied by the scenario.

## Lifecycle

### 1. Inventory the Skill

For each skill:

1. Read `SKILL.md` and all directly referenced assets needed by the workflow.
2. Extract the skill promise from `name`, `description`, "when to use", and final output sections.
3. Identify required inputs, tools, dependencies, outputs, safety gates, cleanup steps, and known portability constraints.
4. Identify the minimum executor capability profile.

Record this in the scenario header.

### 2. Choose the Executor Floor

Use the lowest model that can reasonably perform the scenario:

| Floor | Use when |
|---|---|
| `core-small` | Linear workflows, simple file reads/writes, command execution, short reports. |
| `tool-small` | Multi-step workflows with shell commands, diffs, JSON parsing, browser-driver commands, or artifact creation. |
| `reasoning-small` | Security, PR analysis, dependency risk, or workflows with nontrivial judgment and safety boundaries. |

If the lowest model repeatedly fails due to missing base capabilities rather than skill quality, raise the floor and document the reason. Do not raise the floor just to improve the score.

### 3. Write Scenario Specs

Each scenario must include:

- skill id and path
- executor floor
- available tools
- setup and fixtures
- user prompt
- required skill behaviors
- forbidden behaviors
- expected artifacts
- metric emphasis
- judge notes

Use `templates/scenario-template.md`.

### 4. Execute the Scenario

1. Start from a clean workspace or named fixture.
2. Load only the skill under test and scenario-permitted references.
3. Run the executor model with the scenario prompt.
4. Capture the full transcript and any generated files.
5. Do not intervene unless the scenario explicitly includes user replies.
6. Stop when the executor gives a final answer, violates a hard safety gate, or reaches the scenario timeout.

### 5. Judge the Run

The judge model receives:

- the scenario spec
- the skill text and referenced materials used by the executor
- the full run transcript
- generated artifacts
- command/test outputs
- `metric-rubric.md`

The judge applies hard gates first, then scores the 100-point metric. Use `templates/judge-prompt.md`.

### 6. Report Results

Every scored run must include:

- scenario id
- executor model and version
- judge model and version
- run date
- gate result
- final score
- dimension breakdown
- evidence excerpts or artifact paths
- critical failures
- recommended skill changes

## Passing Thresholds

Use these thresholds unless a scenario declares a stricter bar:

| Score | Meaning |
|---|---|
| 90-100 | Excellent. Skill is clear, safe, complete, and robust for the executor floor. |
| 80-89 | Good. Minor gaps, no critical operational risk. |
| 70-79 | Marginal. Usable but likely to fail on realistic variation. |
| 60-69 | Weak. Significant missing steps, ambiguity, or weak artifacts. |
| 0-59 | Failing. The skill does not reliably enable the task. |

Recommended release gate:

- New skill: at least 80 on every required scenario.
- Safety-sensitive skill: hard gates pass and at least 90 on safety dimensions.
- Existing skill regression: no scenario score drops by more than 5 points and no new hard gate failure.

## Scenario Maintenance

Add or update scenarios when:

- a skill's trigger, workflow, tools, output format, or safety posture changes
- new scripts/templates are added
- the target harness changes
- a prior evaluation exposes an untested failure mode

Keep scenarios small enough that the executor can finish them, but realistic enough to force the intended workflow.
