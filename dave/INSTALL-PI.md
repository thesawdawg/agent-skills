# Optional Pi prompts

First install the portable bundle:

```bash
npx skills@1.6.0 add thesawdawg/agent-skills -g --skill dave
```

From this source checkout, configure prompts against the actual installed path:

```bash
bash dave/scripts/install-pi.sh --skill-dir "$HOME/.agents/skills/dave"
```

Use `--pi-root DIR` for another Pi configuration directory. `--dry-run` previews
locations. `--with-agents-md` explicitly opts into a marked orientation stanza;
existing stanzas and differing prompt files are preserved. Review any retained
older prompts before replacing them. The adapter never installs or transforms
the portable skill and does not remove stale personal configuration.

Check available session capabilities. Without delegation, role work is self-review;
without MCP use the bundled REST reference where appropriate. No session hook is
installed. Run `/dave-brief` when priority orientation is wanted.

`bash dave/scripts/install-pi.sh --selftest` verifies the adapter in temporary paths.
