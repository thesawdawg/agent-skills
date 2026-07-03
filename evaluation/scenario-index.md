# Scenario Index

Each current `SKILL.md` in the repository has at least one scenario.

| Skill id | Skill path | Scenario file |
|---|---|---|
| `root-dependabot-validator` | `dependabot-validator/SKILL.md` | `scenarios/root-dependabot-validator.md` |
| `root-dogfood` | `dogfood/SKILL.md` | `scenarios/root-dogfood.md` |
| `root-pr-grill-me` | `pr-grill-me/SKILL.md` | `scenarios/root-pr-grill-me.md` |
| `pi-adversarial-ux-test` | `pi-skills/adversarial-ux-test/SKILL.md` | `scenarios/pi-adversarial-ux-test.md` |
| `pi-cloudflare-temporary-deploy` | `pi-skills/cloudflare-temporary-deploy/SKILL.md` | `scenarios/pi-cloudflare-temporary-deploy.md` |
| `pi-dependabot-validator` | `pi-skills/dependabot-validator/SKILL.md` | `scenarios/pi-dependabot-validator.md` |
| `pi-dogfood` | `pi-skills/dogfood/SKILL.md` | `scenarios/pi-dogfood.md` |
| `pi-pr-grill-me` | `pi-skills/pr-grill-me/SKILL.md` | `scenarios/pi-pr-grill-me.md` |
| `pi-rest-graphql-debug` | `pi-skills/rest-graphql-debug/SKILL.md` | `scenarios/pi-rest-graphql-debug.md` |
| `pi-subagent-driven-development` | `pi-skills/subagent-driven-development/SKILL.md` | `scenarios/pi-subagent-driven-development.md` |
| `pi-web-pentest` | `pi-skills/web-pentest/SKILL.md` | `scenarios/pi-web-pentest.md` |

## Coverage Expectations

- Root skills should be evaluated in the richer environment they were written for.
- Pi skills should be evaluated with only Read, Write, Edit, Bash, plus tools explicitly required by the skill.
- Safety-sensitive skills must include a scenario where the correct behavior is to stop and ask before taking action.
