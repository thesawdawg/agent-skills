#!/usr/bin/env python3
"""Regression tests for atomic generation publication and reader retention."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BUNDLE = Path(__file__).resolve().parents[2]
CLI = BUNDLE / 'scripts/dave.sh'
sys.path.insert(0, str(BUNDLE / 'dashboard'))
from readers import StateReader  # noqa: E402


class GenerationTests(unittest.TestCase):
    """Exercise real state writes while a dashboard reader retains a snapshot."""

    def setUp(self) -> None:
        """Create a temporary initialized vault."""
        self.directory = tempfile.TemporaryDirectory(prefix='dave-generation-')
        self.home = Path(self.directory.name)
        self.run_cli('init')

    def tearDown(self) -> None:
        """Remove only this test's temporary state."""
        self.directory.cleanup()

    def run_cli(self, *args: str) -> str:
        """Run the CLI against the fixture and return successful stdout.

        Args:
            args: Command arguments.
        Returns:
            Captured stdout.
        """
        return subprocess.run(
            ['bash', str(CLI), *args], check=True, capture_output=True, text=True,
            env=dict(os.environ, DAVE_HOME=str(self.home)), timeout=30).stdout

    def test_reader_keeps_consistent_generation_then_releases_it(self) -> None:
        """A request spanning publication reads old files until it releases."""
        self.run_cli('next', 'set', 'R', 'old note')
        reader = StateReader(self.home)
        with reader.snapshot():
            self.assertEqual(reader.notes()['R']['text'], 'old note')
            old = (self.home / '.local/current').resolve()
            self.run_cli('next', 'set', 'R', 'new note')
            self.run_cli('park', 'new parking item')
            self.assertTrue(old.exists())
            self.assertEqual(reader.notes()['R']['text'], 'old note')
            self.assertEqual(reader.parking()['open'], [])
        with reader.snapshot():
            self.assertEqual(reader.notes()['R']['text'], 'new note')
            self.assertEqual(len(reader.parking()['open']), 1)
        self.run_cli('rebuild')
        self.assertFalse(old.exists())

    def test_failed_reducer_keeps_last_complete_generation(self) -> None:
        """Invalid event input cannot replace the previously readable cache."""
        self.run_cli('next', 'set', 'R', 'preserved')
        current = (self.home / '.local/current').resolve()
        (self.home / 'journal/broken.jsonl').write_text(
            '{"ts":"2099","seq":1,"dev":"bad","type":"next.set",'
            '"data":{"ref":{}}}\n')
        proc = subprocess.run(
            ['bash', str(CLI), 'rebuild'], capture_output=True, text=True,
            env=dict(os.environ, DAVE_HOME=str(self.home)), timeout=30)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual((self.home / '.local/current').resolve(), current)
        self.assertEqual(StateReader(self.home).notes()['R']['text'], 'preserved')

    def test_concurrent_builders_publish_complete_files(self) -> None:
        """Concurrent CLI writers retain all distinct events and valid views."""
        processes = [subprocess.Popen(
            ['bash', str(CLI), 'next', 'set', f'R{i}', f'note {i}'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            env=dict(os.environ, DAVE_HOME=str(self.home))) for i in range(4)]
        for process in processes:
            out, err = process.communicate(timeout=45)
            self.assertEqual(process.returncode, 0, out + err)
        self.run_cli('state')
        reader = StateReader(self.home)
        with reader.snapshot():
            self.assertEqual(len(reader.notes()), 4)
        for name in ('views/state.json', 'views/notes.json', 'render/parking-lot.md'):
            self.assertTrue((self.home / '.local/current' / name).is_file())


if __name__ == '__main__':
    unittest.main()
