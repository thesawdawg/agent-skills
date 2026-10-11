"""Test the lan-viewer server over loopback against a throwaway directory."""
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VIEWER = ROOT / 'lan-viewer' / 'scripts' / 'viewer.py'


class ViewerTests(unittest.TestCase):
    """Start one server and exercise auth, scoping, and change detection."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = tempfile.TemporaryDirectory(prefix='viewer test ')
        cls.root = Path(cls.tmp.name)
        (cls.root / 'a.md').write_text('# A\n')
        (cls.root / '.env').write_text('SECRET=1\n')
        (cls.root / 'key.pem').write_text('PRIVATE\n')
        cls.server = subprocess.Popen(
            ['python3', str(VIEWER), str(cls.root), str(cls.root / '.env'), '--idle-timeout', '1'],
            stdout=subprocess.PIPE, text=True)
        cls.record = json.loads(cls.server.stdout.readline())
        cls.base = f"http://127.0.0.1:{cls.record['port']}"
        cls.token = cls.record['url'].split('?t=')[1]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.terminate()
        cls.server.wait(timeout=10)
        cls.server.stdout.close()
        cls.tmp.cleanup()

    def get(self, path: str, token: bool = True) -> tuple[int, str]:
        url = self.base + path + (('&' if '?' in path else '?') + 't=' + self.token if token else '')
        try:
            with urllib.request.urlopen(url) as reply:
                return reply.status, reply.read().decode()
        except urllib.error.HTTPError as error:
            return error.code, ''

    def test_loopback_bind_and_secret_filtering(self) -> None:
        self.assertEqual(self.record['bind'], '127.0.0.1')
        self.assertEqual(self.record['files'], 1)
        self.assertTrue(any('.env' in w for w in self.record['warnings']))

    def test_token_required(self) -> None:
        self.assertEqual(self.get('/api/docs', token=False)[0], 403)
        self.assertEqual(self.get('/', token=False)[0], 403)
        self.assertEqual(self.get('/api/docs')[0], 200)

    def test_only_registered_files(self) -> None:
        status, body = self.get('/api/doc?id=0')
        self.assertEqual(status, 200)
        self.assertTrue(body.startswith('# A'))
        self.assertEqual(self.get('/api/doc?id=1')[0], 404)
        self.assertEqual(self.get('/api/doc?id=../../etc/passwd')[0], 404)
        self.assertEqual(self.get('/%2e%2e/%2e%2e/etc/passwd')[0], 404)

    def test_security_headers_and_assets(self) -> None:
        request = urllib.request.Request(f'{self.base}/app.js?t={self.token}')
        with urllib.request.urlopen(request) as reply:
            self.assertIn("script-src 'self'", reply.headers['Content-Security-Policy'])
            self.assertEqual(reply.headers['X-Content-Type-Options'], 'nosniff')
            self.assertIn('javascript', reply.headers['Content-Type'])

    def test_change_detection(self) -> None:
        before = json.loads(self.get('/api/version')[1])['version']
        time.sleep(0.01)
        (self.root / 'a.md').write_text('# A changed\n')
        after = json.loads(self.get('/api/version')[1])['version']
        self.assertNotEqual(before, after)


if __name__ == '__main__':
    unittest.main()
