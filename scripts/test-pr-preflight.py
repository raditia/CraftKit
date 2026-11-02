#!/usr/bin/env python3
import copy
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

HELPER = str(Path(__file__).resolve().parents[1] / 'hooks/craftkit-pr-preflight.js')


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo'
        self.repo.mkdir()
        self.env = dict(os.environ, HOME=str(self.base / 'home'))
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@invalid.local')
        (self.repo / 'tracked').write_text('original\n')
        self.git('add', 'tracked')
        self.git('commit', '-qm', 'initial')
        self.head = self.git('rev-parse', 'HEAD').strip()
        self.body = self.base / 'body.md'
        self.body.write_text('## Evidence\nhttps://github.com/org/repo/actions/runs/123\n')
        self.record = {
            'version': 1, 'head': self.head,
            'checks': [{'name': 'unit', 'result': 'pass', 'details': '3 passed'}],
            'review': {'status': 'pass', 'agent': 'reviewer', 'summary': 'No findings'},
            'evidence': [{'kind': 'test', 'url': 'https://github.com/org/repo/actions/runs/123',
                          'verified': True, 'revision': self.head, 'scenario': 'regression'}],
            'limitations': [],
        }

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True, env=self.env)

    def run_cli(self, record=None, check=False, cwd=None):
        args = ['node', HELPER, '--body', str(self.body)]
        if check:
            args.append('--check')
        else:
            source = self.base / 'input.json'
            source.write_text(json.dumps(self.record if record is None else record))
            args += ['--record', str(source)]
        return subprocess.run(args, cwd=cwd or self.repo, env=self.env, text=True, capture_output=True)

    def test_valid_record_and_private_saved_check(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('READY\n', result.stdout)
        saved = list((self.base / 'home' / '.craftkit-state' / 'pr-preflight').glob('*.json'))
        self.assertEqual(len(saved), 1)
        self.assertEqual(stat.S_IMODE(saved[0].stat().st_mode), 0o600)
        self.assertEqual(self.run_cli(check=True).returncode, 0)

    def test_missing_or_invalid_record(self):
        self.assertNotEqual(self.run_cli(check=True).returncode, 0)
        for record in [None, {}, {'version': 2}]:
            if record is None:
                source = self.base / 'invalid.json'
                source.write_text('{')
                result = subprocess.run(['node', HELPER, '--record', str(source), '--body', str(self.body)],
                                        cwd=self.repo, env=self.env, capture_output=True)
            else:
                result = self.run_cli(record)
            self.assertNotEqual(result.returncode, 0)

    def test_stale_head(self):
        self.assertEqual(self.run_cli().returncode, 0)
        self.git('commit', '--allow-empty', '-qm', 'next')
        self.assertIn('stale', self.run_cli(check=True).stderr)

    def test_dirty_tracked_and_index(self):
        (self.repo / 'tracked').write_text('changed\n')
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.git('add', 'tracked')
        self.assertNotEqual(self.run_cli().returncode, 0)

    def test_review_checks_and_evidence_required(self):
        for field, value in [('review', {}), ('checks', []), ('evidence', [])]:
            record = copy.deepcopy(self.record)
            record[field] = value
            self.assertNotEqual(self.run_cli(record).returncode, 0, field)
        record = copy.deepcopy(self.record)
        record['checks'][0]['result'] = 'blocked'
        self.assertNotEqual(self.run_cli(record).returncode, 0)

    def test_body_must_contain_evidence_and_heading(self):
        for body in ['## Evidence\nMissing URL\n', self.record['evidence'][0]['url']]:
            self.body.write_text(body)
            self.assertNotEqual(self.run_cli().returncode, 0)

    def test_invalid_evidence(self):
        for url in ['http://github.com/evidence', '/tmp/video.mp4', 'https://localhost/video',
                    'https://example.com/video', 'https://github.com/TODO']:
            record = copy.deepcopy(self.record)
            record['evidence'][0]['url'] = url
            self.body.write_text('## Evidence\n' + url)
            self.assertNotEqual(self.run_cli(record).returncode, 0, url)
        self.body.write_text('## Evidence\n' + self.record['evidence'][0]['url'])
        for key, value in [('verified', False), ('revision', 'old'), ('scenario', '')]:
            record = copy.deepcopy(self.record)
            record['evidence'][0][key] = value
            self.assertNotEqual(self.run_cli(record).returncode, 0, key)

    def test_documented_limitation(self):
        self.record['evidence'] = []
        self.record['limitations'] = ['Incomplete: runtime video unavailable; simulator cannot start.']
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.body.write_text('## Evidence\n' + self.record['limitations'][0])
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('INCOMPLETE: draft PR only', result.stdout)

    def test_blocked_checks_require_documented_limitations_and_remain_incomplete(self):
        detail = 'Incomplete: simulator smoke test failed to launch.'
        self.record['checks'].append({'name': 'runtime', 'result': 'blocked', 'details': detail})
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.record['limitations'] = [detail]
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.body.write_text('## Evidence\n' + self.record['evidence'][0]['url'] + '\n' + detail)
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('INCOMPLETE: draft PR only', result.stdout)
        self.record['checks'] = [self.record['checks'][1]]
        self.assertEqual(self.run_cli().returncode, 0)
        self.record['checks'] = []
        self.assertNotEqual(self.run_cli().returncode, 0)

    def test_cross_repository_record_rejected_even_same_head(self):
        self.assertEqual(self.run_cli().returncode, 0)
        saved = next((self.base / 'home' / '.craftkit-state' / 'pr-preflight').glob('*.json'))
        record = json.loads(saved.read_text())
        other = self.base / 'other'
        subprocess.check_call(['git', 'clone', '-q', str(self.repo), str(other)], env=self.env)
        self.assertNotEqual(self.run_cli(record, cwd=other).returncode, 0)
        self.assertNotEqual(self.run_cli(check=True, cwd=other).returncode, 0)


if __name__ == '__main__':
    unittest.main()
