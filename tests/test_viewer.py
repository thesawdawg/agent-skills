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
        for name in ['credentials.json', 'secrets.yaml', 'terraform.tfstate.json', 'id_ecdsa',
                     'service-account-prod.json', 'api_token.json']:
            (cls.root / name).write_text('x\n')
        (cls.root / 'grow.log').write_text('small\n')
        (cls.root / 'secrets-policy.md').write_text('# prose about secrets\n')
        (cls.root / 'id_mapping.md').write_text('# ids\n')
        cls.outside = tempfile.TemporaryDirectory(prefix='viewer outside ')
        (Path(cls.outside.name) / 'notes.txt').write_text('outside\n')
        (cls.root / 'link.md').symlink_to(Path(cls.outside.name) / 'notes.txt')
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
        cls.outside.cleanup()

    def get(self, path: str, token: bool = True) -> tuple[int, str]:
        url = self.base + path + (('&' if '?' in path else '?') + 't=' + self.token if token else '')
        try:
            with urllib.request.urlopen(url) as reply:
                return reply.status, reply.read().decode()
        except urllib.error.HTTPError as error:
            return error.code, ''

    def test_loopback_bind_and_secret_filtering(self) -> None:
        self.assertEqual(self.record['bind'], '127.0.0.1')
        self.assertTrue(any('.env' in w for w in self.record['warnings']))

    def listed(self) -> list[str]:
        return [d['name'] for d in json.loads(self.get('/api/docs')[1])['docs']]

    def test_secret_patterns_and_prose_allowed(self) -> None:
        names = self.listed()
        for blocked in ['credentials.json', 'secrets.yaml', 'terraform.tfstate.json', 'id_ecdsa',
                        'service-account-prod.json', 'api_token.json', '.env', 'key.pem']:
            self.assertNotIn(blocked, names)
        self.assertIn('secrets-policy.md', names)
        self.assertIn('id_mapping.md', names)

    def test_symlink_escape_skipped(self) -> None:
        self.assertNotIn('link.md', self.listed())
        self.assertTrue(any('symlink' in w for w in self.record['warnings']))
        self.assertFalse(any('outside' in n for n in self.listed()))

    def test_token_required(self) -> None:
        self.assertEqual(self.get('/api/docs', token=False)[0], 403)
        self.assertEqual(self.get('/', token=False)[0], 403)
        self.assertEqual(self.get('/api/docs')[0], 200)

    def test_non_ascii_token_rejected_cleanly(self) -> None:
        for token in ['%C3%A9', '']:
            try:
                urllib.request.urlopen(f'{self.base}/api/docs?t={token}')
                self.fail('accepted bad token')
            except urllib.error.HTTPError as error:
                self.assertEqual(error.code, 403)

    def test_cookie_flow_is_per_port(self) -> None:
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        opener = urllib.request.build_opener(NoRedirect)
        with self.assertRaises(urllib.error.HTTPError) as caught:
            opener.open(f'{self.base}/?t={self.token}')
        self.assertEqual(caught.exception.code, 302)
        cookie = caught.exception.headers['Set-Cookie']
        self.assertTrue(cookie.startswith(f"lv_token_{self.record['port']}="), cookie)
        self.assertIn('HttpOnly', cookie)
        request = urllib.request.Request(f'{self.base}/api/docs', headers={'Cookie': cookie.split(';')[0]})
        with urllib.request.urlopen(request) as reply:
            self.assertEqual(reply.status, 200)

    def test_host_header_checked_on_loopback(self) -> None:
        request = urllib.request.Request(f'{self.base}/api/docs?t={self.token}', headers={'Host': 'evil.example'})
        with self.assertRaises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(request)
        self.assertEqual(caught.exception.code, 403)

    def test_vendor_assets_cacheable_and_gzipped(self) -> None:
        request = urllib.request.Request(f'{self.base}/vendor/marked.umd.js?t={self.token}',
                                         headers={'Accept-Encoding': 'gzip'})
        with urllib.request.urlopen(request) as reply:
            self.assertEqual(reply.headers['Content-Encoding'], 'gzip')
            self.assertIn('max-age', reply.headers['Cache-Control'])
        with urllib.request.urlopen(f'{self.base}/app.js?t={self.token}') as reply:
            self.assertEqual(reply.headers['Cache-Control'], 'no-store')

    def test_idle_connections_time_out(self) -> None:
        import socket
        sock = socket.create_connection(('127.0.0.1', self.record['port']))
        sock.settimeout(15)
        self.assertEqual(sock.recv(1), b'')  # server closes the silent connection
        sock.close()

    def test_negative_and_huge_ids(self) -> None:
        self.assertEqual(self.get('/api/doc?id=-1')[0], 404)
        self.assertEqual(self.get('/api/doc?id=99999999999999999999')[0], 404)

    def test_only_registered_files(self) -> None:
        status, body = self.get('/api/doc?id=0')
        self.assertEqual(status, 200)
        self.assertTrue(body.startswith('# A'))
        self.assertEqual(self.get('/api/doc?id=9999')[0], 404)
        self.assertEqual(self.get('/api/doc?id=../../etc/passwd')[0], 404)
        self.assertEqual(self.get('/%2e%2e/%2e%2e/etc/passwd')[0], 404)

    def test_security_headers_and_assets(self) -> None:
        request = urllib.request.Request(f'{self.base}/app.js?t={self.token}')
        with urllib.request.urlopen(request) as reply:
            self.assertIn("script-src 'self'", reply.headers['Content-Security-Policy'])
            self.assertEqual(reply.headers['X-Content-Type-Options'], 'nosniff')
            self.assertIn('javascript', reply.headers['Content-Type'])

    def test_file_growing_past_cap_refused(self) -> None:
        index = self.listed().index('grow.log')
        (self.root / 'grow.log').write_text('x' * (5 * 1024 * 1024 + 1))
        self.assertEqual(self.get(f'/api/doc?id={index}')[0], 413)

    def test_change_detection(self) -> None:
        before = json.loads(self.get('/api/version')[1])['version']
        time.sleep(0.01)
        (self.root / 'a.md').write_text('# A changed\n')
        after = json.loads(self.get('/api/version')[1])['version']
        self.assertNotEqual(before, after)


if __name__ == '__main__':
    unittest.main()
