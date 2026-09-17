#!/usr/bin/env bash
# install-pi.sh — install D.A.V.E. into the pi harness (https://pi.dev).
#
# pi has no plugin system, so the Claude Code plugin is taken apart and each piece
# installed where pi actually looks for it:
#
#   skills/dave/**          -> $PI_ROOT/skills/dave/         (/skill:dave)
#   agents/<role>.md        -> $PI_ROOT/skills/dave/references/roles/<role>.md
#   commands/<name>.md      -> $PI_ROOT/prompts/dave-<name>.md   (/dave-<name>)
#   hooks/                  -> not installed; pi has no hooks (see --with-agents-md)
#
# Usage:
#   install-pi.sh [--pi-root DIR] [--dry-run] [--with-agents-md] [--force] [--selftest]

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_ROOT="${PI_ROOT:-$HOME/.pi/agent}"
DRY=0; WITH_AGENTS=0; FORCE=0; SELFTEST=0

die() { echo "install-pi: $*" >&2; exit 1; }
say() { echo "$*"; }
run() { if [ "$DRY" -eq 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --pi-root) PI_ROOT="${2:-}"; [ -n "$PI_ROOT" ] || die "--pi-root needs a directory"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --with-agents-md) WITH_AGENTS=1; shift ;;
    --force) FORCE=1; shift ;;
    --selftest) SELFTEST=1; shift ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

SKILL_DST="$PI_ROOT/skills/dave"
PROMPTS_DST="$PI_ROOT/prompts"
ROLES_DST="$SKILL_DST/references/roles"

# ---------------------------------------------------------------- transforms

# Commands become pi prompt templates: pi has no $ARGUMENTS and no
# allowed-tools/argument-hint frontmatter, and the working directory at expansion
# time is the user's project, not the skill dir — so every relative path the
# command referenced has to become the literal installed path.
convert_command() {
  local src="$1" dst="$2" desc
  desc="$(sed -n 's/^description: *"\{0,1\}\(.*\)/\1/p' "$src" | head -1 | sed 's/"$//')"
  {
    printf '<!-- %s -->\n\n' "$desc"
    sed '1,/^---$/d' "$src" | sed '1{/^---$/d}' \
      | sed -e 's/\$ARGUMENTS/{{args}}/g' \
            -e "s|scripts/dave\.sh|$SKILL_DST/scripts/dave.sh|g" \
            -e "s|\`references/|\`$SKILL_DST/references/|g" \
            -e 's|Load the `dave` skill|Load the `dave` skill (`/skill:dave`)|g' \
            -e "s|the \`\\([a-z]*\\)\` agent|the \`\\1\` role (see $ROLES_DST/\\1.md)|g"
  } > "$dst"
}

# Agents become role reference docs. pi has no built-in subagents, so `model:` and
# `color:` are meaningless here and are dropped rather than left to confuse a
# small model reading the file.
convert_agent() {
  local src="$1" dst="$2"
  sed -e '/^model: /d' -e '/^color: /d' "$src" > "$dst"
}

# The installed SKILL.md sits alone in pi's skills dir, so links that pointed up
# out of the plugin have to be re-pointed at the copies installed alongside it.
fix_skill_links() {
  local f="$1"
  sed -i \
    -e 's|(\.\./\.\./USE_CASES\.md)|(USE_CASES.md)|g' \
    -e 's|\[top-level skills index\](\.\./\.\./\.\./USE_CASES\.md)|the top-level skills index in the source repo|g' \
    -e 's|(\.\./\.\./README\.md)|(README.md)|g' \
    "$f"
}

# references/ sit one level below the skill root, but link to plugin-root docs as
# ../../../ — which resolves in the repo and not in pi's flatter install layout.
fix_reference_links() {
  local d="$1"
  [ -d "$d" ] || return 0
  sed -i \
    -e 's|(\.\./\.\./\.\./INSTALL-PI\.md)|(../INSTALL-PI.md)|g' \
    -e 's|(\.\./\.\./\.\./README\.md)|(../README.md)|g' \
    -e 's|(\.\./\.\./\.\./USE_CASES\.md)|(../USE_CASES.md)|g' \
    "$d"/*.md
}

# README/USE_CASES/INSTALL-PI are copied from the plugin root into the skill root,
# so their "skills/dave/..." paths collapse by one level. The two links that point
# outside the plugin entirely become absolute URLs rather than dangling.
REPO_URL='https://github.com/thesawdawg/agent-skills/blob/main'
fix_root_doc_links() {
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    sed -i \
      -e 's|](skills/dave/|](|g' \
      -e "s|](\.\./USE_CASES\.md)|]($REPO_URL/USE_CASES.md)|g" \
      -e "s|](\.\./pi-skills/README\.md)|]($REPO_URL/pi-skills/README.md)|g" \
      "$f"
  done
}

PI_NOTE_MARK='<!-- pi-install-note -->'

append_pi_note() {
  local f="$1"
  grep -qF "$PI_NOTE_MARK" "$f" 2>/dev/null && return 0
  cat >> "$f" <<NOTE

$PI_NOTE_MARK
## Running under pi

This copy is installed in the pi harness, which differs from Claude Code in four
ways that change how the workflow above executes:

1. **No subagents.** The roster in
   [references/delegation-contract.md](references/delegation-contract.md) still
   applies, but a "delegate to X" step means *run a fresh, focused pass in this
   loop* using that role's charge and return format from
   \`references/roles/<role>.md\`. Brief it exactly as strictly — the discipline is
   what makes the result usable, not the process boundary. If the official pi
   \`subagent/\` extension is installed, dispatch a real subagent instead.

2. **No built-in MCP — but the Redmine MCP is still reachable.** Install the
   \`pi-mcp-adapter\` extension (\`pi install npm:pi-mcp-adapter\`) and
   [references/redmine.md](references/redmine.md) applies as written, except that
   discovery goes through the proxy tool — \`mcp({ search: "redmine issue" })\`
   instead of \`ToolSearch\`. Without the adapter, use
   [references/redmine-rest.md](references/redmine-rest.md): the same operations
   over plain \`curl\`. **Every approval rule still holds either way**, unchanged.

3. **Shell state does not persist between Bash calls.** Never \`export DAVE_HOME\`
   in one step and rely on it in the next. \`dave.sh\` defaults to \`~/.dave\`, so
   just call it by its literal absolute path:
   \`$SKILL_DST/scripts/dave.sh brief\`

4. **No session hook.** Nothing injects your focus automatically — run
   \`/dave-brief\` (or the command above) at the start of work. The drift watch is
   only active once something has actually read the list this session.

Commands are pi prompt templates: \`/dave-brief\`, \`/dave-focus\`, \`/dave-intake\`,
\`/dave-check\`, \`/dave-park\`, \`/dave-delegate\`, \`/dave-standup\`.
NOTE
}

# ---------------------------------------------------------------- install

do_install() {
  [ -f "$SRC/skills/dave/SKILL.md" ] || die "cannot find the plugin at $SRC"

  if [ -d "$SKILL_DST" ] && [ "$FORCE" -eq 0 ] && [ "$DRY" -eq 0 ]; then
    say "note: $SKILL_DST exists — overwriting managed files (use --force to silence)"
  fi

  say "Installing D.A.V.E. into pi at $PI_ROOT"
  run mkdir -p "$SKILL_DST" "$PROMPTS_DST" "$ROLES_DST"

  # 1. the skill itself
  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] copy skills/dave/{SKILL.md,references,templates,scripts} -> $SKILL_DST"
  else
    cp "$SRC/skills/dave/SKILL.md" "$SKILL_DST/SKILL.md"
    cp -r "$SRC/skills/dave/references" "$SKILL_DST/"
    cp -r "$SRC/skills/dave/templates"  "$SKILL_DST/"
    cp -r "$SRC/skills/dave/scripts"    "$SKILL_DST/"
    chmod +x "$SKILL_DST/scripts/dave.sh"
    # docs the skill links to, so those links resolve after install
    cp "$SRC/README.md"     "$SKILL_DST/README.md"
    cp "$SRC/USE_CASES.md"  "$SKILL_DST/USE_CASES.md"
    if [ -f "$SRC/INSTALL-PI.md" ]; then cp "$SRC/INSTALL-PI.md" "$SKILL_DST/INSTALL-PI.md"; fi
    mkdir -p "$ROLES_DST"
    fix_skill_links "$SKILL_DST/SKILL.md"
    fix_reference_links "$SKILL_DST/references"
    fix_root_doc_links "$SKILL_DST/README.md" "$SKILL_DST/USE_CASES.md" "$SKILL_DST/INSTALL-PI.md"
    append_pi_note "$SKILL_DST/SKILL.md"
  fi
  say "  skill      -> $SKILL_DST/SKILL.md            (/skill:dave)"

  # 2. agents -> role references
  local n=0
  for a in "$SRC"/skills/dave/references/roles/*.md; do
    [ -f "$a" ] || continue
    local base; base="$(basename "$a")"
    if [ "$DRY" -eq 1 ]; then echo "  [dry-run] agent $base -> $ROLES_DST/$base"
    else convert_agent "$a" "$ROLES_DST/$base"; fi
    n=$((n+1))
  done
  say "  roles      -> $ROLES_DST/  ($n)"

  # 3. commands -> prompt templates
  local m=0
  for c in "$SRC"/commands/*.md; do
    [ -f "$c" ] || continue
    local name; name="$(basename "$c" .md)"
    if [ "$DRY" -eq 1 ]; then echo "  [dry-run] command $name -> $PROMPTS_DST/dave-$name.md"
    else convert_command "$c" "$PROMPTS_DST/dave-$name.md"; fi
    m=$((m+1))
  done
  say "  prompts    -> $PROMPTS_DST/dave-*.md  ($m)  (/dave-brief, /dave-check, ...)"

  # 4. optional AGENTS.md stanza — pi's nearest thing to the SessionStart hook
  if [ "$WITH_AGENTS" -eq 1 ]; then
    local agents_md="$PI_ROOT/AGENTS.md"
    local mark='<!-- dave:begin -->'
    if [ "$DRY" -eq 1 ]; then
      echo "  [dry-run] append D.A.V.E. stanza to $agents_md"
    elif grep -qF "$mark" "$agents_md" 2>/dev/null; then
      say "  AGENTS.md  -> stanza already present, left alone"
    else
      cat >> "$agents_md" <<AGENTS

$mark
## D.A.V.E.

Priority state lives in \`~/.dave\`. At the start of substantive work, run:

\`\`\`bash
$SKILL_DST/scripts/dave.sh brief
\`\`\`

Lead with what is in **Now** and whether the last intake is stale. If work drifts
off that list — unlisted work running long, a third unrelated repository, something
previously parked — say so **once**, in one sentence, offer park / promote /
continue, then take the answer and drop it. Never raise a settled objection twice.
Load \`/skill:dave\` for the full workflow.
<!-- dave:end -->
AGENTS
      say "  AGENTS.md  -> stanza appended to $agents_md"
    fi
  else
    say "  AGENTS.md  -> skipped (pass --with-agents-md to add the session stanza)"
  fi

  say ""
  say "Done. pi has no hooks, so nothing runs automatically — start with /dave-brief."
  command -v jq >/dev/null 2>&1 || say "WARNING: jq is not installed; dave.sh requires it."
}

# ---------------------------------------------------------------- selftest

do_selftest() {
  local tmp; tmp="$(mktemp -d)"
  # Expand now, not at trap time — `tmp` is function-local and would be unset
  # (and fatal under `set -u`) by the time an EXIT trap fires.
  trap "rm -rf '$tmp'" EXIT
  local fails=0
  check() { if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }

  echo "selftest: installing into $tmp"
  PI_ROOT="$tmp" SKILL_DST="$tmp/skills/dave" PROMPTS_DST="$tmp/prompts" ROLES_DST="$tmp/skills/dave/references/roles" \
    bash "${BASH_SOURCE[0]}" --pi-root "$tmp" --with-agents-md >/dev/null

  echo "selftest: assertions"
  check "SKILL.md installed"            "[ -f '$tmp/skills/dave/SKILL.md' ]"
  check "dave.sh installed executable"  "[ -x '$tmp/skills/dave/scripts/dave.sh' ]"
  check "script libs installed"         "[ -f '$tmp/skills/dave/scripts/lib/common.sh' ]"
  check "state layer runs installed"    "DAVE_HOME='$tmp/state' '$tmp/skills/dave/scripts/dave.sh' init >/dev/null"
  check "templates copied"              "[ -f '$tmp/skills/dave/templates/config-template.json' ]"
  check "redmine-rest reference copied" "[ -f '$tmp/skills/dave/references/redmine-rest.md' ]"
  check "9 roles converted"             "[ \$(ls '$tmp/skills/dave/references/roles' | wc -l) -eq 9 ]"
  # Counted from the source rather than hardcoded: adding a command should not
  # mean remembering to bump a number in a test.
  check "every command converted"       "[ \$(ls '$tmp/prompts' | wc -l) -eq \$(ls '$SRC/commands' | wc -l) ]"
  check "role frontmatter stripped"     "! grep -q '^model: ' '$tmp/skills/dave/references/roles/scout.md'"
  check "role name kept"                "grep -q '^name: scout' '$tmp/skills/dave/references/roles/scout.md'"
  check "no \$ARGUMENTS left in prompts" "! grep -rq 'ARGUMENTS' '$tmp/prompts'"
  check "{{args}} substituted"          "grep -q '{{args}}' '$tmp/prompts/dave-focus.md'"
  check "no relative scripts/ path"     "! grep -rq '[^/]scripts/dave.sh' '$tmp/prompts'"
  check "no nested install path"        "! grep -rq 'dave/$tmp' '$tmp/prompts'"
  check "dave.sh path appears once"     "[ \$(grep -o '$tmp/skills/dave/scripts/dave.sh' '$tmp/prompts/dave-focus.md' | head -1 | wc -l) -eq 1 ] && ! grep -q 'dave//' '$tmp/prompts/dave-focus.md'"
  check "agent->role rewrite absolute"  "grep -q 'role (see $tmp/skills/dave/references/roles/quartermaster.md)' '$tmp/prompts/dave-intake.md'"
  check "absolute dave.sh in prompts"   "grep -q '$tmp/skills/dave/scripts/dave.sh' '$tmp/prompts/dave-brief.md'"
  check "pi note appended"              "grep -q 'Running under pi' '$tmp/skills/dave/SKILL.md'"
  check "AGENTS.md stanza written"      "grep -q 'dave:begin' '$tmp/AGENTS.md'"
  check "skill up-links rewritten"      "! grep -q '\\.\\./\\.\\./USE_CASES' '$tmp/skills/dave/SKILL.md'"
  check "linked USE_CASES.md present"   "[ -f '$tmp/skills/dave/USE_CASES.md' ]"
  check "INSTALL-PI.md copied"          "[ -f '$tmp/skills/dave/INSTALL-PI.md' ]"
  check "reference up-links rewritten"  "! grep -rq '\\.\\./\\.\\./\\.\\./' '$tmp/skills/dave/references'"
  check "reference link resolves"       "[ -f '$tmp/skills/dave/references/../INSTALL-PI.md' ]"
  check "root-doc links collapsed"      "! grep -rq '](skills/dave/' '$tmp/skills/dave'"
  check "outside links absolutized"     "! grep -rq '](\\.\\./USE_CASES.md)' '$tmp/skills/dave'"
  check "README link resolves"          "[ -f '$tmp/skills/dave/templates/config-template.json' ] && grep -q '](templates/config-template.json)' '$tmp/skills/dave/README.md'"

  echo "selftest: idempotence"
  bash "${BASH_SOURCE[0]}" --pi-root "$tmp" --with-agents-md >/dev/null
  check "pi note not duplicated"        "[ \$(grep -c 'Running under pi' '$tmp/skills/dave/SKILL.md') -eq 1 ]"
  check "AGENTS stanza not duplicated"  "[ \$(grep -c 'dave:begin' '$tmp/AGENTS.md') -eq 1 ]"

  echo
  if [ "$fails" -eq 0 ]; then echo "selftest: all checks passed"; else echo "selftest: $fails FAILED"; return 1; fi
}

if [ "$SELFTEST" -eq 1 ]; then do_selftest; else do_install; fi
