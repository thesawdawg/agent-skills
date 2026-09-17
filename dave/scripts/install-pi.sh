#!/usr/bin/env bash
# Configure optional Pi prompts around a separately installed portable D.A.V.E.
set -euo pipefail
source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pi_root="${PI_ROOT:-$HOME/.pi/agent}"
skill_dir="${DAVE_SKILL_DIR:-$HOME/.agents/skills/dave}"
dry=0
with_agents=0
selftest=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pi-root) pi_root="${2:?directory required}"; shift 2 ;;
    --skill-dir) skill_dir="${2:?installed skill directory required}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --with-agents-md) with_agents=1; shift ;;
    --selftest) selftest=1; shift ;;
    --force) echo '--force no longer overwrites existing prompt files' >&2; shift ;;
    -h|--help) echo 'install-pi.sh [--skill-dir DIR] [--pi-root DIR] [--dry-run] [--with-agents-md] [--selftest]'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
if [ "$selftest" -eq 1 ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  cp -R "$source_root/skills/dave" "$tmp/installed skill"
  before=$(sha256sum "$tmp/installed skill/SKILL.md")
  bash "$0" --skill-dir "$tmp/installed skill" --pi-root "$tmp/pi" --with-agents-md
  bash "$0" --skill-dir "$tmp/installed skill" --pi-root "$tmp/pi" --with-agents-md
  test "$before" = "$(sha256sum "$tmp/installed skill/SKILL.md")"
  test "$(grep -c 'dave:begin' "$tmp/pi/AGENTS.md")" = 1
  DAVE_HOME="$tmp/state" bash "$tmp/installed skill/scripts/dave.sh" init >/dev/null
  DAVE_HOME="$tmp/state" bash "$tmp/installed skill/scripts/dave.sh" mission new adapter >/dev/null
  DAVE_HOME="$tmp/state" bash "$tmp/installed skill/scripts/dave.sh" mission pack adapter --agent constructor | grep -q 'Return format'
  test -f "$tmp/pi/prompts/dave-brief.md"
  echo 'Pi adapter selftest passed'
  exit 0
fi
[ -f "$skill_dir/SKILL.md" ] && [ -f "$skill_dir/scripts/dave.sh" ] || {
  echo 'Missing portable dave installation. Install with skills CLI first, then pass --skill-dir.' >&2
  exit 3
}
skill_dir=$(cd "$skill_dir" && pwd -P)
if [ "$dry" -eq 1 ]; then
  echo "Would configure $pi_root/prompts using $skill_dir; skill source stays unchanged."
  exit 0
fi
python3 - "$source_root/commands" "$pi_root" "$skill_dir" "$with_agents" <<'PY'
"""Render optional prompt adapters without modifying a portable skill."""
from pathlib import Path
import sys

source, destination, skill, with_agents = sys.argv[1:]
root = Path(destination)
prompts = root / 'prompts'
prompts.mkdir(parents=True, exist_ok=True)
for command in Path(source).glob('*.md'):
    text = command.read_text()
    if text.startswith('---\n'):
        text = text.split('---', 2)[2].lstrip()
    text = text.replace('$ARGUMENTS', '{{args}}')
    text = text.replace('scripts/dave.sh', f'"{skill}/scripts/dave.sh"')
    text = text.replace('`references/', f'`{skill}/references/')
    text = f'Read `{skill}/SKILL.md` first. Use available session capabilities.\n\n' + text
    target = prompts / ('dave-' + command.name)
    if target.exists():
        if target.read_text() != text:
            print(f'Preserved existing prompt: {target}', file=sys.stderr)
        continue
    target.write_text(text)
if with_agents == '1':
    target = root / 'AGENTS.md'
    current = target.read_text() if target.exists() else ''
    if '<!-- dave:begin -->' not in current:
        target.write_text(current + f'\n<!-- dave:begin -->\nFor requested priority orientation, read `{skill}/SKILL.md` and run\n`"{skill}/scripts/dave.sh" brief`. Honor its approval and no-push rules.\n<!-- dave:end -->\n')
PY
printf 'Optional Pi prompts configured; portable skill left unchanged.\n'
