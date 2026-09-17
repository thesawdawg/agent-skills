# Authoring and verification

The catalog is flat: `<name>/SKILL.md`, with D.A.V.E. retained at
`dave/skills/dave/SKILL.md` for plugin compatibility. `SKILL.md` frontmatter owns
activation. README owns the human catalog; extra chooser files are unnecessary.

Each selected bundle must contain its own required references, templates, helper
scripts, and upstream notices. Resolve these from the loaded skill path, never
from the user's cwd. Cross-skill dependencies must be explicit and preflighted;
installer metadata does not install siblings. Human cross-package links use
repository URLs so they remain usable in isolated installs.

Keep the primary workflow short and move conditional lookups into references.
Keep authorization, scope, and destructive-action boundaries in SKILL.md. Reuse
existing user answers and approved artifacts; ask only for missing decisions.
Default to one primary artifact. Preserve existing output and user state.

Read [portable authoring](docs/authoring-portability.md) for self-contained shell
blocks, capability fallbacks, JSONL evidence, process ownership, and security.

Run from the repository root:

```bash
npm ci
bash scripts/verify.sh
```

Requires Bash, Python 3, git, jq, Node 22+, npm, and ShellCheck. The command validates
frontmatter/catalog, links, attribution, CLI discovery, selected copy/symlink
installs, shell syntax, helper regressions, and the D.A.V.E. suite except its
push exercise. `VERIFY_BROWSER=1 bash scripts/verify.sh` additionally prepares
locked browser dependencies in a temporary runtime and runs the local browser
fixture (Chromium must be installed or downloadable). CI runs this mode.

Preflight convention: each executable skill may provide `scripts/preflight.sh`.
`bash scripts/preflight.sh` runs these without installing packages or contacting
services. Parsers may expose `--selftest`; integrated helpers use `tests/` to avoid
embedding a second test harness in each production script. Tests mock external
providers and security tools; they never publish, deploy, or scan real targets.

Trigger fixtures in `tests/triggers.json` are manually reviewed routing examples,
not a claim of model evaluation. Check expected selection and abstention when
changing a description. Size >150 lines is a warning, not a reason to hide guards.

After verification, maintainers can tag a release locally. Publish tags and commits
manually. Never let a cleanup rewrite installed skills or user state automatically.
