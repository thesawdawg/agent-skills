"""Validate catalog, package-local assets, attribution, and routing fixtures."""
import json
from pathlib import Path
import re
from urllib.parse import unquote

import yaml

ROOT = Path(__file__).resolve().parents[1]


def validate() -> None:
    """Fail on packaging drift; warn on long primary workflows.

    Returns:
        None; raises AssertionError for invalid repository content.
    """
    entries = sorted([*ROOT.glob('*/SKILL.md'), ROOT / 'dave/skills/dave/SKILL.md'])
    names = []
    errors = []
    catalog = (ROOT / 'README.md').read_text()
    allowed = {'name', 'description', 'license', 'compatibility', 'metadata', 'allowed-tools'}
    for entry in entries:
        text = entry.read_text()
        metadata = yaml.safe_load(text.split('---', 2)[1])
        name = metadata['name']
        names.append(name)
        if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', name) or len(name) > 64:
            errors.append(f'{entry}: invalid name')
        if entry.parent.name != name or set(metadata) - allowed:
            errors.append(f'{entry}: folder/name or unsupported frontmatter')
        if not isinstance(metadata.get('description'), str) or not 0 < len(metadata['description']) <= 1024:
            errors.append(f'{entry}: invalid description')
        if f'[{name}]({entry.relative_to(ROOT).as_posix()})' not in catalog:
            errors.append(f'{entry}: missing catalog row')
        if len(text.splitlines()) > 150:
            print(f'Warning: {name} has {len(text.splitlines())} lines; retain guards, split conditional detail where useful.')
    expected = (ROOT / 'tests/discovery-expected.txt').read_text().splitlines()
    if len(names) != len(set(names)) or sorted(names) != expected:
        errors.append('Duplicate names or discovery snapshot drift')
    for name in ['dogfood', 'rest-graphql-debug', 'web-pentest', 'cloudflare-temporary-deploy', 'dave/skills/dave']:
        notice = ROOT / name / 'NOTICE'
        if not notice.exists() or 'Permission is hereby granted' not in notice.read_text():
            errors.append(f'{name}: missing distributable MIT notice')
    for path in ROOT.rglob('*.md'):
        if (any(part in {'.git', 'node_modules', '.agents', '.codex'} for part in path.parts)
                or path.name == 'CLEANUP-PLAN.md' or path.name.startswith('codex-session-')):
            continue
        text = path.read_text()
        for retired in ['pi-skills/', 'USE_CASES.md', 'IMPLEMENTATION-PLAN.md']:
            if retired in text:
                errors.append(f'{path.relative_to(ROOT)}: retired path {retired}')
        # Examples in fenced code are not operational Markdown links.
        text = re.sub(r'```.*?```', '', text, flags=re.S)
        text = re.sub(r'`[^`]*`', '', text)
        for target in re.findall(r'\[[^\]]+\]\(([^)]+)\)', text):
            if re.match(r'[a-z]+:|#|/|\{', target):
                continue
            target = unquote(target.split('#', 1)[0].split(' "', 1)[0])
            if target and not (path.parent / target).exists():
                errors.append(f'{path.relative_to(ROOT)}: broken link {target}')
    for case in json.loads((ROOT / 'tests/triggers.json').read_text()):
        if not set(case['expected']).issubset(names) or not case['prompt']:
            errors.append(f'Invalid trigger case: {case}')
    assert not errors, '\n'.join(errors)
    print(f'Validated {len(names)} skills, catalog, links, notices, and trigger fixture targets')


if __name__ == '__main__':
    validate()
