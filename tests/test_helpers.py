"""Test provider adapters, deployment, and scope gates without external calls."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HelperTests(unittest.TestCase):
    """Use temporary executable mocks and owned state."""

    def setUp(self) -> None:
        """Create an isolated PATH and scratch directory.

        Returns:
            None.
        """
        self.temporary = tempfile.TemporaryDirectory(prefix='helper tests ')
        self.directory = Path(self.temporary.name)
        self.environment = dict(os.environ, PATH=f'{self.directory}:{os.environ["PATH"]}')

    def tearDown(self) -> None:
        """Remove test-owned artifacts.

        Returns:
            None.
        """
        self.temporary.cleanup()

    def mock(self, name: str, body: str) -> None:
        """Place a mock executable on the isolated PATH.

        Args:
            name: Executable name.
            body: Shell script body.
        Returns:
            None.
        """
        path = self.directory / name
        path.write_text('#!/usr/bin/env bash\nset -eu\n' + body)
        path.chmod(0o755)

    def run_helper(self, script: str, *arguments: str) -> subprocess.CompletedProcess:
        """Invoke a helper with no real provider access.

        Args:
            script: Repository-relative helper path.
            arguments: Helper arguments.
        Returns:
            Captured process result.
        """
        return subprocess.run(['bash', str(ROOT / script), *arguments], cwd=self.directory,
                              env=self.environment, capture_output=True, text=True, timeout=20)

    def test_deployment_failure_preserves_status_and_private_log(self) -> None:
        """A plausible URL cannot mask a failed deployment.

        Returns:
            None.
        """
        self.mock('npx', 'echo "https://worker.example.workers.dev"\nexit 23\n')
        log = self.directory / 'deploy.log'
        result = self.run_helper('cloudflare-temporary-deploy/scripts/deploy.sh', str(log))
        self.assertEqual(result.returncode, 23)
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)
        self.assertEqual(result.stdout, '')
        before = log.read_bytes()
        self.assertNotEqual(self.run_helper('cloudflare-temporary-deploy/scripts/deploy.sh', str(log)).returncode, 0)
        self.assertEqual(log.read_bytes(), before)

    def test_ollama_invalid_response_preserves_state(self) -> None:
        """Malformed successful HTTP responses must not become a null reply.

        Returns:
            None.
        """
        self.mock('curl', 'printf \'{"message":{"content":"reply"}}\\n\'\n')
        state = self.directory / 'state.json'
        script = 'ollama-delegate/scripts/ollama-task.sh'
        self.assertEqual(self.run_helper(script, 'start', str(state), 'http://mock', 'model', '', 'hello').returncode, 0)
        before = state.read_bytes()
        self.mock('curl', 'echo "{}"\n')
        self.assertNotEqual(self.run_helper(script, 'send', str(state), 'again').returncode, 0)
        self.assertEqual(state.read_bytes(), before)

    def test_codex_whitespace_json_and_resume(self) -> None:
        """Parse valid JSON independent of serialization whitespace.

        Returns:
            None.
        """
        self.mock('codex', '''while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then printf 'reply\\n' > "$2"; shift; fi
  shift
done
printf '{"type": "thread.started", "thread_id": "thread-123"}\\n'
''')
        state = self.directory / 'codex.state'
        script = 'codex-delegate/scripts/codex-session.sh'
        self.assertEqual(self.run_helper(script, 'start', str(state), 'read-only', 'task').returncode, 0)
        self.assertEqual(state.read_text().strip(), 'thread-123')
        self.assertEqual(self.run_helper(script, 'send', str(state), 'continue').stdout.strip(), 'reply')

    def test_security_rejects_missing_auth_and_out_of_scope(self) -> None:
        """Scope/auth failures occur before any network executable.

        Returns:
            None.
        """
        marker = self.directory / 'network-used'
        for name in ['curl', 'nmap', 'whatweb']:
            self.mock(name, f'touch "{marker}"\nexit 0\n')
        engagement = self.directory / 'engagement'
        engagement.mkdir()
        (engagement / 'scope.txt').write_text('127.0.0.1')
        script = 'web-pentest/scripts/recon-scan.sh'
        self.assertEqual(self.run_helper(script, str(engagement), 'http://127.0.0.1').returncode, 3)
        (engagement / 'authorization.md').write_text('unfilled template\n')
        self.assertEqual(self.run_helper(script, str(engagement), 'http://127.0.0.1').returncode, 3)
        (engagement / 'authorization.md').write_text('Authorization status: authorized\n')
        self.assertEqual(self.run_helper(script, str(engagement), 'http://example.invalid').returncode, 5)
        self.assertNotEqual(self.run_helper(script, str(engagement), 'file://127.0.0.1/etc/passwd').returncode, 0)
        self.assertFalse(marker.exists())
        self.assertEqual(self.run_helper(script, str(engagement), 'http://127.0.0.1').returncode, 0)
        self.assertTrue(marker.exists())
        self.assertTrue((engagement / 'request-log.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
