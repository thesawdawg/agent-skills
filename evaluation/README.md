# Agent Skill Evaluation

This directory defines a spec-driven methodology for evaluating agent skills with a common metric.

The evaluation contract is:

1. Every skill gets one or more scenario specs.
2. Each scenario is written for the lowest-capability executor model that should be able to complete the task with the skill.
3. The executor model runs the scenario using only the tools and constraints named in the scenario.
4. The highest available model grades the transcript and artifacts against the standard metric.
5. Results are reported as a comparable score with safety gates, evidence, and failure modes.

## Files

- `methodology.md` - end-to-end evaluation process.
- `metric-rubric.md` - the standard 100-point metric and hard gates.
- `scenario-index.md` - all current skills and their scenario specs.
- `templates/scenario-template.md` - template for adding a new scenario.
- `templates/judge-prompt.md` - grading prompt for the evaluator model.
- `scenarios/*.md` - concrete scenarios for the skills in this repo.

## Required Result Shape

Each run should produce:

```text
skill_id:
scenario_id:
executor_model:
judge_model:
gate_status: PASS | FAIL
score: 0-100
metric_breakdown:
evidence:
critical_failures:
recommended_skill_changes:
```

Scores are not valid unless the judge cites the transcript or generated artifacts for each scoring dimension.
