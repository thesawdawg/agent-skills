"""Exercise pinned CLI discovery and real selected installations."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'node_modules/skills/bin/cli.mjs'


def main() -> None:
    """Validate CLI names and isolated copy/symlink bundles.

    Returns:
        None; command and assertion failures propagate.
    """
    expected = (ROOT / 'tests/discovery-expected.txt').read_text().splitlines()
    environment = dict(os.environ, DO_NOT_TRACK='1')
    output = subprocess.check_output(['node', str(CLI), 'add', str(ROOT), '--list'], env=environment, text=True)
    output = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', output)
    discovered = re.findall(r'^│    ([a-z0-9-]+)\s*$', output, re.M)
    assert sorted(discovered) == expected, discovered
    with tempfile.TemporaryDirectory(prefix='selected installs ') as directory:
        for mode in ['copy', 'symlink']:
            for name in expected:
                project = Path(directory) / mode / name
                project.mkdir(parents=True)
                (project / '.claude').mkdir()
                (project / '.cursor').mkdir()
                args = ['node', str(CLI), 'add', str(ROOT), '--skill', name, '--agent', 'claude-code', 'cursor', '-y']
                if mode == 'copy':
                    args.append('--copy')
                result = subprocess.run(args, cwd=project, env=environment, capture_output=True, text=True, timeout=30)
                assert result.returncode == 0, result.stdout + result.stderr
                installed = project / '.claude/skills' / name
                assert installed.is_symlink() == (mode == 'symlink'), installed
                assert (installed / 'SKILL.md').exists()
                if name == 'dave':
                    assert not (installed.parent / 'code-review').exists()
                    state_env = dict(environment, DAVE_HOME=str(project / 'state'))
                    driver = installed / 'scripts/dave.sh'
                    for arguments in [['init'], ['mission', 'new', 'install'], ['mission', 'pack', 'install', '--agent', 'constructor']]:
                        subprocess.run(['bash', str(driver), *arguments], cwd=project, env=state_env, check=True, capture_output=True)
                if name == 'accessibility-audit':
                    result = subprocess.run(['bash', str(installed / 'scripts/preflight.sh'), str(project / 'missing-dogfood')], capture_output=True)
                    assert result.returncode == 3
    print(f'CLI discovery and {len(expected) * 2} selected copy/symlink installations passed')


if __name__ == '__main__':
    main()
