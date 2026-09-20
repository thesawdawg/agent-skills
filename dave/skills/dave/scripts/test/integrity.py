#!/usr/bin/env python3
"""Exercise malformed history diagnostics and preservation-first recovery."""
from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'dave.sh'


class IntegrityTests(unittest.TestCase):
    """Run real commands against an isolated home without transport calls."""

    def setUp(self) -> None:
        """Initialize isolated source history."""
        self.temp = tempfile.TemporaryDirectory(prefix='dave-integrity-')
        self.home = Path(self.temp.name)
        self.run_cli('init')
        self.run_cli('log', 'one durable entry')
        self.journal = next((self.home / 'journal').glob('*.jsonl'))

    def tearDown(self) -> None:
        """Discard the fixture only."""
        self.temp.cleanup()

    def run_cli(self, *args: str, check: bool = True) -> subprocess.CompletedProcess:
        """Run one command without personal credentials.

        Args:
            args: CLI arguments.
            check: Whether nonzero exit is an error.
        Returns:
            Captured subprocess result.
        """
        return subprocess.run(['bash', str(CLI), *args],
            env=dict(os.environ, DAVE_HOME=str(self.home), SYNCTHING_API_KEY=''),
            text=True, capture_output=True, check=check, timeout=30)

    def test_partial_tail_warns_and_middle_corruption_blocks_refresh(self) -> None:
        """Tail tolerance is visible; damaged durable lines cannot hide."""
        original = self.journal.read_bytes()
        self.journal.write_bytes(original + b'{"partial":')
        self.run_cli('state')
        status = json.loads(self.run_cli('sync', 'status', '--json').stdout)
        self.assertEqual(status['integrity']['diagnostics'][0]['severity'], 'warning')
        self.journal.write_bytes(b'bad-json\n' + original)
        self.assertNotEqual(self.run_cli('state', check=False).returncode, 0)
        status = json.loads(self.run_cli('sync', 'status', '--json').stdout)
        self.assertFalse(status['integrity']['healthy'])
        self.assertEqual(status['views'], 'stale')

    def test_recovery_keeps_unique_events_without_replaying_duplicates(self) -> None:
        """Conflict prefixes do not duplicate logs; recovery imports unique tail."""
        conflict = self.journal.with_name('peer.sync-conflict-20260919-120000-A.jsonl')
        event = json.loads(self.journal.read_text().splitlines()[0])
        event['seq'] += 1
        event['data']['text'] = 'unique copy entry'
        conflict.write_text(self.journal.read_text() + json.dumps(event) + '\n')
        self.run_cli('state')
        logs = json.loads((self.home / '.local/views/log.json').read_text())
        self.assertEqual(sum(map(len, logs.values())), 1)
        preview = json.loads(self.run_cli('sync', 'journal-conflicts', str(conflict)).stdout)
        self.assertEqual(preview['unique_events'], 1)
        self.assertEqual(preview['duplicate_events'], 1)
        self.run_cli('sync', 'journal-conflicts', str(conflict), '--apply', preview['digest'])
        logs = json.loads((self.home / '.local/views/log.json').read_text())
        self.assertEqual(sum(map(len, logs.values())), 2)
        self.assertFalse(conflict.exists())
        self.assertTrue((self.home / '.local/recovery' / (preview['digest']+'.jsonl')).exists())
        self.run_cli('rebuild')
        logs = json.loads((self.home / '.local/views/log.json').read_text())
        self.assertEqual(sum(map(len, logs.values())), 2)

    def test_divergent_identity_refuses_recovery_without_deleting_copy(self) -> None:
        """Different payloads for the same identity require explicit reconciliation."""
        event = json.loads(self.journal.read_text().splitlines()[0])
        event['data']['text'] = 'different contents, same identity'
        conflict = self.journal.with_name('peer.sync-conflict-20260919-120000-A.jsonl')
        conflict.write_text(json.dumps(event)+'\n')
        result = self.run_cli('sync', 'journal-conflicts', str(conflict), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('divergent_event_identity', result.stdout)
        self.assertTrue(conflict.exists())

    def test_unsupported_events_are_diagnostic_errors(self) -> None:
        """A newer protocol cannot silently disappear from the materialized view."""
        event = json.loads(self.journal.read_text().splitlines()[0])
        event.update(seq=99, type='future.change')
        (self.home / 'journal/future.jsonl').write_text(json.dumps(event)+'\n')
        status = json.loads(self.run_cli('sync', 'status', '--json').stdout)
        self.assertFalse(status['integrity']['healthy'])
        self.assertEqual(status['integrity']['diagnostics'][0]['code'], 'unsupported_event_type')


if __name__ == '__main__':
    unittest.main()
