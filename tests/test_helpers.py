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

    def run_helper(self, script: str, *arguments: str,
                   env: dict | None = None) -> subprocess.CompletedProcess:
        """Invoke a helper with no real provider access.

        Args:
            script: Repository-relative helper path.
            arguments: Helper arguments.
            env: Optional environment overrides merged over the isolated PATH.
        Returns:
            Captured process result.
        """
        environment = dict(self.environment, **env) if env else self.environment
        return subprocess.run(['bash', str(ROOT / script), *arguments], cwd=self.directory,
                              env=environment, capture_output=True, text=True, timeout=20)

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

    def curl_mock_recording(self, logic: str) -> None:
        """Mock curl: record argv, honor -o/-w, then run per-test logic.

        Args:
            logic: Shell body run after argv capture; may use $out and $url.
        Returns:
            None.
        """
        self.mock('curl', '''printf '%s\\n' "$@" >> curl-args.txt
out=""
url=""
writeout=""
data=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -w) writeout="$2"; shift ;;
    -d|--data-binary) data="$2"; shift ;;
    http://*|https://*) url="$1" ;;
  esac
  shift
done
case "$data" in @*) cp "${data#@}" curl-body.json ;; esac
emit() {
  if [ -n "$out" ]; then printf '%s' "$1" > "$out"; else printf '%s' "$1"; fi
  if [ -n "$writeout" ]; then printf '%s' "$2"; fi
}
''' + logic)

    def test_system_one_ask_sets_model_and_prints_answers(self) -> None:
        """ask posts the body with .model set and never leaks the key.

        Returns:
            None.
        """
        self.curl_mock_recording('''emit '{"model":"m","answers":{"q":{"type":"noul","noul":0.9}},"usage":{"input_tokens":1,"output_tokens":0}}' 200
''')
        request = self.directory / 'request.json'
        request.write_text('{"state":"x","questions":{"q":{"type":"noul","instructions":"y"}}}')
        script = 'system-one/scripts/systemone.sh'
        result = self.run_helper(script, 'ask', 'http://mock', 'jev-latest', str(request),
                                 env={'TYPESAFE_API_KEY': '', 'TYPESAFE_BASE_URL': ''})
        self.assertEqual(result.returncode, 0, result.stderr)
        response = json.loads(result.stdout)
        self.assertEqual(response['answers']['q']['noul'], 0.9)
        posted = json.loads((self.directory / 'curl-body.json').read_text())
        self.assertEqual(posted['model'], 'jev-latest')
        self.assertEqual(posted['state'], 'x')
        recorded = (self.directory / 'curl-args.txt').read_text()
        self.assertNotIn('Authorization', recorded)

        request.write_text(json.dumps({'state': 'x' * 300_000,
                                       'questions': {'q': {'type': 'noul', 'instructions': 'y'}}}))
        result = self.run_helper(script, 'ask', 'http://mock', 'jev-latest', str(request),
                                 env={'TYPESAFE_API_KEY': '', 'TYPESAFE_BASE_URL': ''})
        self.assertEqual(result.returncode, 0, result.stderr)

        (self.directory / 'curl-args.txt').unlink()
        result = self.run_helper(script, 'ask', 'http://mock', 'jev-latest', str(request),
                                 env={'TYPESAFE_API_KEY': 'secret', 'TYPESAFE_BASE_URL': ''})
        self.assertEqual(result.returncode, 0, result.stderr)
        recorded = (self.directory / 'curl-args.txt').read_text()
        self.assertIn('Authorization: Bearer secret', recorded)
        self.assertNotIn('secret', result.stdout + result.stderr)

    def test_system_one_ask_rejects_malformed_and_error_status(self) -> None:
        """ask fails on a 2xx body without answers and on error statuses.

        Returns:
            None.
        """
        script = 'system-one/scripts/systemone.sh'
        request = self.directory / 'request.json'
        request.write_text('{"state":"x"}')
        env = {'TYPESAFE_API_KEY': '', 'TYPESAFE_BASE_URL': ''}

        self.curl_mock_recording('emit \'{}\' 200\n')
        result = self.run_helper(script, 'ask', 'http://mock', 'm', str(request), env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('malformed', result.stderr)

        self.curl_mock_recording('emit \'{"detail":"bad key"}\' 401\n')
        result = self.run_helper(script, 'ask', 'http://mock', 'm', str(request), env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('HTTP 401', result.stderr)
        self.assertIn('bad key', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_system_one_probe_order_and_models(self) -> None:
        """probe tries defaults in order; the hosted URL needs a key.

        Returns:
            None.
        """
        script = 'system-one/scripts/systemone.sh'
        no_key = {'TYPESAFE_API_KEY': '', 'TYPESAFE_BASE_URL': ''}
        self.curl_mock_recording('''case "$url" in
  http://127.0.0.1:8080/*)
    emit '{"models":[{"name":"local-m","description":"d"}]}' 200
    ;;
  *) exit 7 ;;
esac
''')
        result = self.run_helper(script, 'probe', env=no_key)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'http://127.0.0.1:8080')
        result = self.run_helper(script, 'models', 'http://127.0.0.1:8080', env=no_key)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'local-m\td')

        self.curl_mock_recording('exit 7\n')
        args_log = self.directory / 'curl-args.txt'
        args_log.unlink(missing_ok=True)
        result = self.run_helper(script, 'probe', env=no_key)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('api.typesafe.ai', args_log.read_text())

        args_log.unlink()
        result = self.run_helper(script, 'probe',
                                 env={'TYPESAFE_API_KEY': 'k', 'TYPESAFE_BASE_URL': ''})
        self.assertEqual(result.returncode, 1)
        self.assertIn('https://api.typesafe.ai/v1/models', args_log.read_text())

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
