"""Tests for the D.A.V.E. dashboard server against a throwaway DAVE_HOME."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DAVE_SH = ROOT / 'dave' / 'skills' / 'dave' / 'scripts' / 'dave.sh'
SERVER = ROOT / 'dave' / 'skills' / 'dave' / 'dashboard' / 'server.py'


def dave(home: str, *arguments: str, stdin: str = '') -> subprocess.CompletedProcess:
    """Run dave.sh against a given home.

    Args:
        home: The throwaway DAVE_HOME.
        arguments: dave.sh arguments.
        stdin: Optional stdin payload.
    Returns:
        The completed process.
    """
    return subprocess.run(
        ['bash', str(DAVE_SH), *arguments],
        env=dict(os.environ, DAVE_HOME=home),
        input=stdin or None, capture_output=True, text=True, timeout=30)


class DashboardTests(unittest.TestCase):
    """Exercise the API end to end over a seeded state tree."""

    server: subprocess.Popen
    base: str
    token: str
    home_dir: tempfile.TemporaryDirectory
    home: str

    @classmethod
    def setUpClass(cls) -> None:
        """Seed a state tree and boot the server on an ephemeral port.

        Returns:
            None.
        """
        cls.home_dir = tempfile.TemporaryDirectory(prefix='dave dash ')
        cls.home = cls.home_dir.name
        assert dave(cls.home, 'init').returncode == 0
        dave(cls.home, 'focus', 'set', 'RM-4471', 'retry double-fire')
        dave(cls.home, 'log', 'seeded log line')
        dave(cls.home, 'park', 'a parked idea')
        dave(cls.home, 'park', 'another parked idea')
        dave(cls.home, 'promise', 'add', 'Maya', 'SSO demo', 'friday', '--ref', 'RM-4471')
        dave(cls.home, 'mission', 'new', 'sso rollout', '--ref', 'RM-4471')
        assignment = dave(cls.home, 'mission', 'assign', 'sso-rollout', 'scout',
                          'have a look').stdout.strip()
        dave(cls.home, 'mission', 'record', assignment, '--verdict', 'partial',
             '--summary', 'needs a rerun')
        dave(cls.home, 'mission', 'open', 'sso-rollout')
        repo = Path(cls.home) / 'work' / 'repo'
        repo.mkdir(parents=True)
        subprocess.run(['git', '-C', str(repo), 'init', '-q'], check=True)
        subprocess.run(['git', '-C', str(repo), 'config', 'user.email', 't@t'],
                       check=True)
        subprocess.run(['git', '-C', str(repo), 'config', 'user.name', 't'],
                       check=True)
        (repo / 'f.txt').write_text('a')
        subprocess.run(['git', '-C', str(repo), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(repo), 'commit', '-qm', 'feat: seed'],
                       check=True)
        dave(cls.home, 'project', 'add', str(repo), '--goal', 'test repo')
        dave(cls.home, 'scan')

        env = dict(os.environ, DAVE_HOME=cls.home)
        cls.server = subprocess.Popen(
            ['python3', str(SERVER), '--port', '0', '--dave-sh', str(DAVE_SH)],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        ready = cls.server.stdout.readline().strip()
        assert ready.startswith('READY http://127.0.0.1:'), ready
        cls.base = ready.split(' ', 1)[1].rstrip('/')
        index = urllib.request.urlopen(f'{cls.base}/', timeout=5).read().decode()
        cls.token = index.split('name="dave-token" content="')[1].split('"')[0]

    @classmethod
    def tearDownClass(cls) -> None:
        """Stop the server and drop the throwaway home.

        Returns:
            None.
        """
        cls.server.terminate()
        try:
            cls.server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.server.kill()
        cls.server.stdout.close()
        cls.server.stderr.close()
        cls.home_dir.cleanup()

    def get(self, path: str) -> tuple[int, dict]:
        """GET an API path.

        Args:
            path: URL path including any query string.
        Returns:
            (status, decoded body) — errors decode the envelope too.
        """
        request = urllib.request.Request(f'{self.base}{path}')
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as exc:
            with exc:
                return exc.code, json.loads(exc.read())

    def post(self, path: str, payload: dict, headers: dict = None) -> tuple[int, dict]:
        """POST an API path with a JSON body.

        Args:
            path: URL path.
            payload: Body fields.
            headers: Extra/override headers; X-Dave-Token defaults to the token.
        Returns:
            (status, decoded body).
        """
        merged = {'X-Dave-Token': self.token}
        if headers:
            merged.update(headers)
        request = urllib.request.Request(
            f'{self.base}{path}', data=json.dumps(payload).encode(),
            headers=merged, method='POST')
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as exc:
            with exc:
                return exc.code, json.loads(exc.read())

    # ------------------------------------------------------------------ tests

    def test_health(self) -> None:
        """Health reports the home and setup state.

        Returns:
            None.
        """
        status, body = self.get('/api/health')
        self.assertEqual(200, status)
        self.assertEqual('success', body['status'])
        self.assertEqual(self.home, body['data']['dave_home'])
        self.assertTrue(body['data']['setup'])
        self.assertEqual(2, body['data']['schema_version'])

    def test_overview_shape(self) -> None:
        """Overview carries the seeded focus and sections.

        Returns:
            None.
        """
        status, body = self.get('/api/overview')
        self.assertEqual(200, status)
        data = body['data']
        self.assertEqual('RM-4471', data['focus']['ref'])
        self.assertIsInstance(data['focus_minutes'], int)
        self.assertIn('now', data['priorities']['sections'])
        self.assertEqual(2, data['parked_open_count'])
        self.assertEqual(1, len(data['promises_due_soon']))
        self.assertEqual('sso-rollout', data['active_mission'])

    def test_priorities_parsed(self) -> None:
        """Parsed sections come back even when the template list is empty.

        Returns:
            None.
        """
        status, body = self.get('/api/priorities')
        self.assertEqual(200, status)
        sections = body['data']['sections']
        self.assertIn('reconciled', body['data'])
        self.assertIn('raw', body['data'])
        for name in ('now', 'next', 'blocked', 'someday'):
            self.assertIn(name, sections)

    def test_post_requires_token(self) -> None:
        """A POST without the token is a 403.

        Returns:
            None.
        """
        request = urllib.request.Request(
            f'{self.base}/api/log', data=b'{"text":"x"}', method='POST')
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(request, timeout=10)
        self.assertEqual(403, ctx.exception.code)
        ctx.exception.close()

    def test_post_bad_origin(self) -> None:
        """A POST with a foreign Origin is a 403 even with the token.

        Returns:
            None.
        """
        status, body = self.post('/api/log', {'text': 'x'},
                                 {'Origin': 'http://evil.example'})
        self.assertEqual(403, status)
        self.assertEqual('error', body['status'])

    def test_post_focus_round_trip(self) -> None:
        """Setting focus through the API shows up in the overview.

        Returns:
            None.
        """
        status, body = self.post('/api/focus', {'action': 'set', 'ref': 'RM-9',
                                              'label': 'api test'})
        self.assertEqual(200, status)
        _, overview = self.get('/api/overview')
        self.assertEqual('RM-9', overview['data']['focus']['ref'])
        dave(self.home, 'focus', 'set', 'RM-4471', 'retry double-fire')

    def test_post_priorities_round_trip(self) -> None:
        """priorities set via the API replaces the file.

        Returns:
            None.
        """
        markdown = '# P\n\n## Now\n\n1. **RM-4471** — retry\n'
        status, body = self.post('/api/priorities', {'markdown': markdown})
        self.assertEqual(200, status)
        now = body['data']['priorities']['sections']['now']
        self.assertEqual('RM-4471', now[0]['ref'])
        _, again = self.get('/api/priorities')
        self.assertEqual(markdown, again['data']['raw'])

    def test_parked_done(self) -> None:
        """Retiring through the API marks the n-th open item.

        Returns:
            None.
        """
        status, body = self.post('/api/parked/done', {'index': 1})
        self.assertEqual(200, status)
        self.assertEqual(1, len(body['data']['parked']['open']))
        self.assertEqual(1, len(body['data']['parked']['retired']))
        text = Path(self.home, 'parking-lot.md').read_text()
        self.assertIn('- [x] a parked idea', text)
        self.assertIn('_(retired', text)

    def test_assignments_roster(self) -> None:
        """Roster stats fold assign/record events per agent.

        Returns:
            None.
        """
        status, body = self.get('/api/assignments')
        self.assertEqual(200, status)
        scout = body['data']['roster']['scout']
        self.assertEqual(1, scout['total'])
        self.assertEqual(0, scout['open'])
        self.assertEqual(1, scout['by_verdict']['partial'])

    def test_intake_traversal_refused(self) -> None:
        """?file= with a path part is a 400, not a read outside intake/.

        Returns:
            None.
        """
        status, _ = self.get('/api/intake?file=../etc/passwd')
        self.assertEqual(400, status)
        status, _ = self.get('/api/intake?file=../../etc/passwd')
        self.assertEqual(400, status)

    def test_unknown_route(self) -> None:
        """Unknown API paths are a 404 in the error envelope.

        Returns:
            None.
        """
        status, body = self.get('/api/nope')
        self.assertEqual(404, status)
        self.assertEqual('error', body['status'])

    def test_loopback_only(self) -> None:
        """The READY line advertises loopback and no --host flag exists.

        Returns:
            None.
        """
        self.assertTrue(self.base.startswith('http://127.0.0.1:'))
        proc = subprocess.run(
            ['python3', str(SERVER), '--host', '0.0.0.0', '--dave-sh', str(DAVE_SH)],
            capture_output=True, text=True, timeout=10)
        self.assertNotEqual(0, proc.returncode)

    def test_mission_without_brief_is_listed(self) -> None:
        """A missions.json entry with no brief file still appears, flagged.

        Returns:
            None.
        """
        missions_path = Path(self.home, 'missions.json')
        meta = json.loads(missions_path.read_text())
        meta['ghost-mission'] = {'project': 'repo', 'ref': 'RM-1',
                                 'status': 'open', 'opened': '2026-01-01',
                                 'closed': None, 'outcome': None}
        missions_path.write_text(json.dumps(meta))
        try:
            status, body = self.get('/api/missions')
            self.assertEqual(200, status)
            ghost = next(m for m in body['data']['missions']
                         if m['slug'] == 'ghost-mission')
            self.assertTrue(ghost['brief_missing'])
            self.assertEqual('repo', ghost['project'])
            status, body = self.get('/api/missions?slug=ghost-mission')
            self.assertEqual(200, status)
            self.assertIsNone(body['data']['brief'])
            self.assertTrue(body['data']['brief_missing'])
        finally:
            meta.pop('ghost-mission')
            missions_path.write_text(json.dumps(meta))

    def test_priority_text_strips_leading_ref(self) -> None:
        """Parsed item text drops a duplicated leading **REF** — marker.

        Returns:
            None.
        """
        markdown = ('# P\n\n## Now\n\n'
                    '1. **RM-1** — the _real_ label\n'
                    '- a bullet with no ref\n')
        status, body = self.post('/api/priorities', {'markdown': markdown})
        self.assertEqual(200, status)
        now = body['data']['priorities']['sections']['now']
        self.assertEqual('RM-1', now[0]['ref'])
        self.assertEqual('the _real_ label', now[0]['text'])
        self.assertIn('**RM-1**', now[0]['raw'])
        self.assertIsNone(now[1]['ref'])
        self.assertEqual('a bullet with no ref', now[1]['text'])

    def test_projects_and_missions(self) -> None:
        """Projects merge registration with scan state; missions list rows.

        Returns:
            None.
        """
        status, body = self.get('/api/projects')
        self.assertEqual(200, status)
        projects = {p['slug']: p for p in body['data']['projects']}
        self.assertIn('repo', projects)
        self.assertTrue(projects['repo']['scan']['repo'])
        status, body = self.get('/api/missions')
        self.assertEqual(200, status)
        mission = body['data']['missions'][0]
        self.assertEqual('sso-rollout', mission['slug'])
        self.assertEqual(1, len(mission['assignments']))
        status, body = self.get('/api/missions?slug=sso-rollout')
        self.assertIn('# Mission: sso-rollout', body['data']['brief'])

    def test_config_is_redacted(self) -> None:
        """Credential-shaped keys are masked in /api/config.

        Returns:
            None.
        """
        config_path = Path(self.home, 'config.json')
        cfg = json.loads(config_path.read_text())
        cfg['redmine']['api_key'] = 'sekrit'
        config_path.write_text(json.dumps(cfg))
        try:
            status, body = self.get('/api/config')
            self.assertEqual(200, status)
            self.assertEqual('***', body['data']['redmine']['api_key'])
        finally:
            cfg['redmine'].pop('api_key')
            config_path.write_text(json.dumps(cfg))


if __name__ == '__main__':
    unittest.main()
