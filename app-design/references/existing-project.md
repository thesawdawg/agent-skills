# Existing Project Playbook (Mode A)

> Referenced from [SKILL.md](../SKILL.md).

Work the phases in order. Do not jump ahead. STOP and wait wherever it says to
ask the user. All tools are pi built-ins: `ls`, `find`, `grep`, `read`, `bash`,
`write`, `edit`.

## Phase 1 — Discover (look, don't judge yet)

Goal: build an accurate picture of the code before forming opinions.

**1a. See the shape of the repo:**

```sh
ls -la
find . -maxdepth 2 -type d -not -path '*/node_modules/*' -not -path '*/.git/*' | sort
```

**1b. Read the docs and manifests** with the `read` tool:

- `README*`, `CONTRIBUTING*`, anything in `docs/`
- Whichever manifest exists: `package.json`, `pyproject.toml`,
  `requirements.txt`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`,
  `Gemfile`, `composer.json`
- Config: `.env.example`, `Dockerfile`, `docker-compose.yml`, CI files in
  `.github/workflows/`

**1c. Find the important code with `grep`** (don't read everything):

```sh
# entry points / route definitions (adjust patterns to the language):
grep -rn -E "def main|if __name__|app =|createServer|addRoute|@app.route|router\.(get|post)" --include='*.py' --include='*.js' --include='*.ts' --include='*.go' . | head -40
# data model:
grep -rln -E "class .*Model|CREATE TABLE|@Entity|schema|migration" . | head -20
```

Then `read` the files those point to: entry point, route/controller list, core
models, and 2–3 representative feature files.

**1d. Record how to build/run/test.** Copy the exact commands from the manifest
scripts and CI. You will need them in Phase 3.

Output of this phase: a short internal map — stack, app type, entry points,
data model, run commands.

## Phase 2 — Verify (ask the user)

Goal: turn your map into confirmed truth.

**2a. Write your hypotheses** in plain language: what the app does, who it's
for, the main user flows, the key features. Mark each "confident" or "unsure".

**2b. Ask the user**, 2–4 numbered questions at a time (wording in
[question-bank.md](question-bank.md)). Prioritize:
- everything you marked "unsure"
- behavior that looks intentional but odd (feature or bug?)
- gaps: auth model, permissions, edge cases, expected scale
- what "correct" looks like for the main flows

**STOP after each batch and wait for answers.** Then ask follow-ups until the
picture is solid.

**2c. Write `app-design-output/app-model.md`** with the `write` tool: verified
purpose, users, structure, core flows, intended behaviors, known unknowns. This
is the source of truth for testing.

Do not start Phase 3 until the user confirms the core of the model.

## Phase 3 — Test

Follow [test-battery.md](test-battery.md) exactly: static checks → automated tests → runtime QA
([`/skill:dogfood`](../../dogfood/SKILL.md) for web apps) → collect every bug/discrepancy. A
"discrepancy" = behavior that differs from `app-model.md`. Do not fix anything
yet — finish the whole sweep first.

## Phase 4 — Triage (ask the user)

1. Group findings by severity (Critical/High/Medium/Low — use the dogfood issue
   taxonomy).
2. Present them briefly: what, where, evidence, why it seems wrong.
3. **Ask the user** to confirm each is a real bug vs intended. STOP and wait.
4. For confirmed bugs, agree on the fix and priority. Explain each fix and its
   trade-offs BEFORE editing.
5. Implement only approved fixes with `edit`. Re-test the fixed area.

## Phase 5 — Enhance

1. **New features** that fit the verified purpose — for each: user value, rough
   effort, risk.
2. **Refactors** that cut complexity — dead code, duplication, unclear
   boundaries, missing tests — for each: benefit, effort, regression risk.
3. Write all of it to `app-design-output/recommendations.md`, ordered by
   value-for-effort.
4. Let the user choose what to do. Do not implement anything they didn't ask for.
