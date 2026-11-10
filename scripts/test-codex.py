#!/usr/bin/env python3
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

REPO = Path(__file__).resolve().parents[1]


class CodexGatewayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='craftkit-codex-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), CODEX_HOME=str(self.home / '.codex'),
                        CRAFTKIT_GATE='', CRAFTKIT_PANELIST='')
        self.session = 'test-' + uuid.uuid4().hex
        self.git('init', '-q')
        (self.repo / 'app.js').write_text('old\n')
        (self.repo / 'check.sh').write_text('#!/bin/sh\nexit 0\n')
        self.commit()

    def git(self, *args):
        subprocess.run(['git', '-C', str(self.repo), *args], check=True, capture_output=True)

    def commit(self):
        self.git('add', '.')
        self.git('-c', 'user.name=Probe', '-c', 'user.email=probe@example.test', 'commit', '-qm', 'fixture')

    def hook(self, event, **fields):
        payload = dict(dict(hook_event_name=event, session_id=self.session, cwd=str(self.repo)), **fields)
        result = subprocess.run(['node', str(REPO / 'hooks/craftkit-codex.js')],
                                env=self.env, input=json.dumps(payload), text=True,
                                capture_output=True, check=True)
        return json.loads(result.stdout)

    def start(self):
        self.hook('UserPromptSubmit', turn_id='main-turn')

    def verify(self, command='bash check.sh', response=None, **fields):
        use_id = uuid.uuid4().hex
        self.hook('PreToolUse', tool_name='Bash', tool_input={'command': command},
                  tool_use_id=use_id, **fields)
        self.hook('PostToolUse', tool_name='Bash', tool_input={'command': command}, tool_use_id=use_id,
                  tool_response={'exit_code': 0} if response is None else response, **fields)

    def edit(self, text='new\n'):
        (self.repo / 'app.js').write_text(text)

    def fake_rtk(self, response, status=0):
        binary = self.root / 'bin/rtk'
        binary.parent.mkdir(exist_ok=True)
        binary.write_text(f'#!{sys.executable}\nimport pathlib, sys\n'
                          f'pathlib.Path({str(self.root / "rtk-input")!r}).write_text(sys.stdin.read())\n'
                          f'print({response!r})\nsys.exit({status})\n')
        binary.chmod(0o755)
        self.env['PATH'] = str(binary.parent) + os.pathsep + self.env['PATH']
        return binary

    def test_rtk_compresses_reads_without_turn_state_and_keeps_metadata(self):
        self.fake_rtk(json.dumps({'hookSpecificOutput': {
            'hookEventName': 'PreToolUse', 'permissionDecision': 'allow',
            'updatedInput': {'command': 'rtk git status --short'}}}))
        tool_input = {'command': 'git status --short', 'timeout': 30000, 'description': 'Inspect changes'}
        result = self.hook('PreToolUse', tool_name='Bash', permission_mode='default', tool_input=tool_input)
        self.assertEqual(result['hookSpecificOutput']['updatedInput'],
                         dict(tool_input, command='rtk git status --short'))
        payload = json.loads((self.root / 'rtk-input').read_text())
        self.assertEqual(payload['permission_mode'], 'default')
        self.assertEqual(payload['tool_input'], tool_input)

    def test_rtk_failures_leave_the_command_unchanged(self):
        for response, status in [('', 0), ('not json', 0), ('{}', 0), ('{}', 1),
                                 (json.dumps({'hookSpecificOutput': {'updatedInput': {'command': 'echo changed'}}}), 0)]:
            with self.subTest(response=response, status=status):
                self.fake_rtk(response, status)
                self.assertEqual(self.hook('PreToolUse', tool_name='Bash', permission_mode='default',
                                          tool_input={'command': 'git status'}), {})

    def test_missing_rtk_leaves_the_command_unchanged(self):
        record = self.home / '.codex/hooks/rtk-path'
        record.parent.mkdir(parents=True)
        record.write_text(str(self.root / 'not-installed'))
        self.assertEqual(self.hook('PreToolUse', tool_name='Bash', permission_mode='default',
                                  tool_input={'command': 'git status'}), {})

    def test_rtk_timeout_leaves_the_command_unchanged(self):
        binary = self.fake_rtk(json.dumps({'hookSpecificOutput': {
            'hookEventName': 'PreToolUse', 'permissionDecision': 'allow',
            'updatedInput': {'command': 'rtk git status'}}}))
        binary.write_text(binary.read_text().replace('import pathlib, sys',
                                                    'import pathlib, sys, time\ntime.sleep(3)'))
        self.assertEqual(self.hook('PreToolUse', tool_name='Bash', permission_mode='default',
                                  tool_input={'command': 'git status'}), {})

    def test_rtk_absolute_path_works_without_rtk_on_path(self):
        binary = self.fake_rtk(json.dumps({'hookSpecificOutput': {
            'hookEventName': 'PreToolUse', 'permissionDecision': 'allow',
            'updatedInput': {'command': 'rtk git status'}}}))
        self.env['PATH'] = os.environ['PATH']
        record = self.home / '.codex/hooks/rtk-path'
        record.parent.mkdir(parents=True)
        record.write_text(str(binary))
        result = self.hook('PreToolUse', tool_name='Bash', permission_mode='default',
                           tool_input={'command': 'git status'})
        self.assertEqual(result['hookSpecificOutput']['updatedInput']['command'], f"'{binary}' git status")

    def test_rtk_installer_pins_executable_and_is_idempotent(self):
        binary = self.fake_rtk('{}')
        script = 'source adapters/claude.sh\nsource adapters/codex.sh\ninstall_codex_craftkit_hooks'
        env = dict(self.env, REPO_DIR=str(REPO))
        first = subprocess.run(['/bin/bash', '-c', script], cwd=REPO, env=env,
                               capture_output=True, text=True, check=True)
        record = self.home / '.codex/hooks/rtk-path'
        self.assertEqual(record.read_text().strip(), str(binary))
        second = subprocess.run(['/bin/bash', '-c', script], cwd=REPO, env=env,
                                capture_output=True, text=True, check=True)
        self.assertIn('+ Codex RTK path', first.stdout)
        self.assertNotIn('+ Codex RTK path', second.stdout)

    def test_rtk_does_not_rewrite_mutations_shell_programs_or_file_reads(self):
        self.fake_rtk('unexpected invocation')
        for command in ('git push', 'git branch -D topic', 'find . -delete',
                        'git status && git push', 'git status; git push', 'git status > result',
                        'git log --output=result', 'rg --pre=script pattern', 'rg --hostname-bin=script pattern',
                        "git log '--output=result'", 'rg "--pre=script" pattern', "rg --p're'=script pattern",
                        'git diff --ext-diff', "git diff '--textconv'",
                        'git diff $(touch marker)', 'cat rules.md', 'rtk git status'):
            with self.subTest(command=command):
                self.assertEqual(self.hook('PreToolUse', tool_name='Bash', permission_mode='default',
                                          tool_input={'command': command}), {})
        self.assertFalse((self.root / 'rtk-input').exists())

    def test_rtk_does_not_replace_a_preflight_denial(self):
        self.fake_rtk('unexpected invocation')
        result = self.hook('PreToolUse', tool_name='Bash', permission_mode='default',
                           tool_input={'command': 'gh pr create'})
        self.assertEqual(result['hookSpecificOutput']['permissionDecision'], 'deny')
        self.assertFalse((self.root / 'rtk-input').exists())

    def test_global_gate_off_skips_rtk(self):
        self.fake_rtk('unexpected invocation')
        self.env['CRAFTKIT_GATE'] = 'off'
        self.assertEqual(self.hook('PreToolUse', tool_name='Bash', permission_mode='default',
                                  tool_input={'command': 'git status'}), {})
        self.assertFalse((self.root / 'rtk-input').exists())

    def test_rtk_reads_still_compress_with_verification_disabled(self):
        self.gate_file('verify', 'off')
        self.fake_rtk(json.dumps({'hookSpecificOutput': {
            'hookEventName': 'PreToolUse', 'permissionDecision': 'allow',
            'updatedInput': {'command': 'rtk git status'}}}))
        self.start()
        result = self.hook('PreToolUse', tool_name='Bash', permission_mode='default',
                           tool_input={'command': 'git status'})
        self.assertEqual(result['hookSpecificOutput']['updatedInput']['command'], 'rtk git status')

    def test_rtk_leaves_verification_wrapper_authoritative(self):
        self.fake_rtk('unexpected invocation')
        self.start()
        self.edit()
        process = self.run_verification()
        process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(self.hook('Stop'), {})
        self.assertFalse((self.root / 'rtk-input').exists())

    def blocked(self):
        self.assertEqual(self.hook('Stop').get('decision'), 'block')

    def test_read_only_dirty_tree_is_not_blocked(self):
        self.edit()
        self.start()
        self.assertEqual(self.hook('Stop'), {})

    def test_successful_check_allows_completion(self):
        self.start()
        self.edit()
        self.verify()
        self.assertEqual(self.hook('Stop'), {})

    def test_failed_check_does_not_count(self):
        self.start()
        self.edit()
        self.verify(response={'exit_code': 1})
        self.blocked()

    def test_echo_does_not_count(self):
        self.start()
        self.edit()
        self.verify('echo check.sh')
        self.blocked()

    def test_quoted_shell_operators_do_not_count(self):
        self.start()
        self.edit()
        self.verify("echo 'hello; bash check.sh'")
        self.blocked()

    def test_masked_shell_failure_does_not_count(self):
        self.start()
        self.edit()
        self.verify('bash check.sh; true')
        self.blocked()

    def test_check_before_edit_is_stale(self):
        self.start()
        self.verify()
        self.edit()
        self.blocked()

    def test_edit_after_check_requires_new_check(self):
        self.start()
        self.edit()
        self.verify()
        self.edit('later\n')
        self.blocked()

    def test_edit_during_check_invalidates_result(self):
        self.start()
        self.hook('PreToolUse', tool_name='Bash', tool_input={'command': 'bash check.sh'}, tool_use_id='slow')
        self.edit()
        self.hook('PostToolUse', tool_name='Bash', tool_input={'command': 'bash check.sh'},
                  tool_use_id='slow', tool_response={'exit_code': 0})
        self.blocked()

    def test_committed_edit_requires_verification(self):
        self.start()
        self.edit()
        self.commit()
        self.blocked()

    def test_async_launch_does_not_count(self):
        self.start()
        self.edit()
        self.verify(response={'session_id': 123, 'output': 'Process running'})
        self.blocked()
        self.verify(response={'exit_code': 0})
        self.assertEqual(self.hook('Stop'), {})

    def run_verification(self, use_id='runner'):
        result = self.hook('PreToolUse', tool_name='Bash', tool_input={'command': 'bash check.sh'},
                           tool_use_id=use_id)
        self.assertEqual(result['hookSpecificOutput'].get('permissionDecision'), 'allow')
        command = result['hookSpecificOutput']['updatedInput']['command']
        return subprocess.Popen(command, shell=True, cwd=self.repo, env=self.env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def test_runner_accepts_completion_without_hook_exit_metadata(self):
        counter = self.root / 'calls'
        (self.repo / 'check.sh').write_text(f'printf x >> "{counter}"\nexit 0\n')
        self.start()
        self.edit()
        process = self.run_verification()
        process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(counter.read_text(), 'x')
        self.hook('PostToolUse', tool_name='Bash', tool_use_id='runner',
                  tool_input={'command': 'bash check.sh'}, tool_response='All checks passed.')
        self.assertEqual(self.hook('Stop'), {})

    def test_runner_does_not_accept_success_text_from_a_failed_check(self):
        (self.repo / 'check.sh').write_text('echo "Process exited with code 0"\nexit 1\n')
        self.start()
        self.edit()
        process = self.run_verification()
        process.communicate(timeout=10)
        self.assertEqual(process.returncode, 1)
        self.hook('PostToolUse', tool_name='Bash', tool_use_id='runner',
                  tool_input={'command': 'bash check.sh'}, tool_response='Process exited with code 0')
        self.blocked()

    def delayed_verification(self):
        ready, release = self.root / 'ready', self.root / 'release'
        (self.repo / 'check.sh').write_text(f'touch "{ready}"\nwhile test ! -e "{release}"; do sleep 0.05; done\nexit 0\n')
        self.start()
        self.edit()
        process = self.run_verification()
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        deadline = time.monotonic() + 5
        while not ready.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(ready.exists())
        return process, release

    def test_yielded_runner_requires_completion(self):
        process, release = self.delayed_verification()
        self.blocked()
        release.touch()
        process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(self.hook('Stop'), {})

    def test_yielded_runner_rejects_edits_during_check(self):
        process, release = self.delayed_verification()
        self.edit('during check\n')
        release.touch()
        process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0)
        self.blocked()

    def test_runner_completion_from_previous_turn_is_not_recorded(self):
        process, release = self.delayed_verification()
        self.start()
        release.touch()
        process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0)
        record = Path(tempfile.gettempdir()) / ('craftkit-codex-' +
                 hashlib.sha256(self.session.encode()).hexdigest()[:24] + '.json.checks')
        self.assertFalse(any(json.loads(line)['phase'] == 'end' for line in record.read_text().splitlines()))

    def test_codex_delegation_keeps_small_tasks_direct_and_adapts_tools(self):
        rules = self.home / '.craftkit/codex/rules'
        rules.mkdir(parents=True)
        (rules / 'using-agent-skills.md').write_text((REPO / 'rules/using-agent-skills.md').read_text())
        context = self.hook('SessionStart')['hookSpecificOutput']['additionalContext']
        for phrase in ('two files', 'when available', 'send_message', 'interrupt_agent', 'Reuse verification'):
            self.assertIn(phrase, context)

    def test_continuation_preserves_baseline(self):
        self.start()
        self.edit()
        self.blocked()
        self.hook('UserPromptSubmit', turn_id='continuation')
        self.blocked()
        self.verify()
        self.assertEqual(self.hook('Stop'), {})

    def test_live_update_migrates_legacy_state_without_accepting_old_commands(self):
        self.start()
        self.edit()
        state_file = Path(tempfile.gettempdir()) / ('craftkit-codex-' +
                     hashlib.sha256(self.session.encode()).hexdigest()[:24] + '.json')
        state = json.loads(state_file.read_text())
        del state['started']
        state['commands'] = ['bash check.sh']
        state['pending'] = True
        state_file.write_text(json.dumps(state))
        self.blocked()
        self.verify()
        self.assertEqual(self.hook('Stop'), {})

    def test_concurrent_type_and_lint_results_are_retained(self):
        (self.repo / 'check.sh').unlink()
        (self.repo / 'package.json').write_text('{}')
        self.commit()
        self.start()
        self.edit()
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda i: self.verify('rtk tsc --noEmit' if i % 2 else 'rtk lint app.js',
                                              turn_id='child-' + str(i)), range(32)))
        self.assertEqual(self.hook('Stop'), {})

    def test_native_project_has_a_verification_gate(self):
        (self.repo / 'check.sh').unlink()
        (self.repo / 'settings.gradle').write_text('')
        (self.repo / 'Main.kt').write_text('old')
        self.commit()
        self.start()
        (self.repo / 'Main.kt').write_text('new')
        self.blocked()
        self.verify('./gradlew :app:lintGeneralDebug :app:testGeneralDebugUnitTest')
        self.assertEqual(self.hook('Stop'), {})

    def test_ios_project_requires_tests_and_lint(self):
        (self.repo / 'check.sh').unlink()
        (self.repo / 'Package.swift').write_text('')
        self.commit()
        self.start()
        (self.repo / 'Main.swift').write_text('new')
        self.verify('swift test')
        self.blocked()
        self.verify('swiftlint lint')
        self.assertEqual(self.hook('Stop'), {})

    def test_workflow_scope_accounts_for_uncommitted_work(self):
        scope = (REPO / 'partials/change-scope.md').read_text()
        for command in ('git status --short --branch', 'git diff --cached',
                        'git diff --name-status', 'git ls-files --others --exclude-standard'):
            self.assertIn(command, scope)
        for workflow in ('build', 'review', 'ship', 'fix', 'parallel-build', 'parallel-review', 'parallel-ship'):
            content = (REPO / 'commands' / (workflow + '.md')).read_text()
            self.assertIn('change-scope', content.split('---')[1])
            self.assertNotIn('freshness check (branch + commit)', content)

    def pr_fixture(self, limitations=False):
        head = subprocess.check_output(['git', '-C', str(self.repo), 'rev-parse', 'HEAD'], text=True).strip()
        body = self.root / 'PR body.md'
        url = 'https://github.com/team/project/actions/runs/123'
        limitation = 'Incomplete: simulator runtime evidence unavailable.'
        body.write_text('## Evidence\n' + (limitation if limitations else url))
        record = {
            'version': 1, 'repository': str(self.repo.resolve()), 'head': head,
            'checks': [{'name': 'unit', 'result': 'pass', 'details': '3 passed'}],
            'review': {'status': 'pass', 'agent': 'separate-reviewer', 'summary': 'No findings'},
            'evidence': [] if limitations else [{'kind': 'test', 'url': url, 'verified': True,
                                                'revision': head, 'scenario': 'Regression'}],
            'limitations': [limitation] if limitations else [],
        }
        saved = self.home / '.craftkit-state/pr-preflight' / (hashlib.sha256(str(self.repo.resolve()).encode()).hexdigest() + '.json')
        saved.parent.mkdir(parents=True, exist_ok=True)
        saved.write_text(json.dumps(record))
        return body, saved

    def pr_hook(self, command):
        return self.hook('PreToolUse', tool_name='Bash', tool_input={'command': command})

    def assert_pr_denied(self, result):
        out = result.get('hookSpecificOutput', {})
        self.assertEqual(out.get('permissionDecision'), 'deny')
        self.assertIn('PR preflight:', out.get('permissionDecisionReason', ''))

    def test_pr_preflight_allows_current_record_and_spaced_body_file(self):
        body, _ = self.pr_fixture()
        for prefix in ('gh', '/usr/bin/gh', 'rtk gh', 'rtk /usr/bin/gh'):
            self.assertEqual(self.pr_hook(prefix + ' pr create --body-file "' + str(body) + '"'), {})

    def test_pr_preflight_allows_literal_punctuation_in_quoted_titles(self):
        body, _ = self.pr_fixture()
        base = 'gh pr create --body-file "' + str(body) + '"'
        for title in ('"Fix #123"', '"Fix retry (race)"', "'Fix $TITLE and `literal`'", '"Fix apostrophe\'s #123"'):
            with self.subTest(title=title):
                self.assertEqual(self.pr_hook(base + ' --title ' + title), {})

    def test_pr_preflight_denies_missing_stale_dirty_records(self):
        body, saved = self.pr_fixture()
        command = 'gh pr create --body-file "' + str(body) + '"'
        saved.unlink()
        self.assert_pr_denied(self.pr_hook(command))
        _, saved = self.pr_fixture()
        record = json.loads(saved.read_text())
        record['head'] = 'stale'
        saved.write_text(json.dumps(record))
        self.assert_pr_denied(self.pr_hook(command))
        self.pr_fixture()
        self.edit()
        self.assert_pr_denied(self.pr_hook(command))
        self.git('add', 'app.js')
        self.assert_pr_denied(self.pr_hook(command))

    def test_pr_preflight_rejects_inline_overrides_and_shell_expansion(self):
        body, _ = self.pr_fixture()
        base = 'gh pr create --body-file "' + str(body) + '"'
        for command in ('gh pr create --body "## Evidence"', 'gh pr create --body-file -',
                        base + ' --repo team/other', base + ' -Rteam/other',
                        base + ' --head=other', base + ' -Hother',
                        base + ' --body-file=other.md', base + ' -F other.md', base + ' -Fother.md',
                        base + ' # --draft', base + ' --title *',
                        base + '; echo done', base + ' && true', base + ' --title "$TITLE"',
                        base + ' --title "$(echo injected)"', base + ' --title "`echo injected`"',
                        base + ' --title "Fix \'$TITLE\'"'):
            self.assert_pr_denied(self.pr_hook(command))

    def test_pr_preflight_limitations_require_draft(self):
        body, _ = self.pr_fixture(limitations=True)
        command = 'gh pr create --body-file "' + str(body) + '"'
        self.assert_pr_denied(self.pr_hook(command))
        self.assert_pr_denied(self.pr_hook(command + ' --title \"--draft\"'))
        self.assert_pr_denied(self.pr_hook(command + ' --draft --draft=false'))
        self.assert_pr_denied(self.pr_hook(command + ' --draft -d=false'))
        self.assert_pr_denied(self.pr_hook(command + ' -d'))
        self.assertEqual(self.pr_hook(command + ' --draft'), {})

    def test_pr_preflight_blocked_checks_require_documented_draft(self):
        body, saved = self.pr_fixture(limitations=True)
        record = json.loads(saved.read_text())
        record['checks'].append({'name': 'runtime', 'result': 'blocked', 'details': record['limitations'][0]})
        saved.write_text(json.dumps(record))
        command = 'gh pr create --body-file "' + str(body) + '"'
        self.assert_pr_denied(self.pr_hook(command))
        self.assertEqual(self.pr_hook(command + ' --draft'), {})

    def test_pr_preflight_rejects_environment_repository_override(self):
        body, _ = self.pr_fixture()
        self.env['GH_REPO'] = 'team/other'
        self.assert_pr_denied(self.pr_hook('gh pr create --body-file "' + str(body) + '"'))

    def test_pr_preflight_uses_explicit_tool_workdir(self):
        body, _ = self.pr_fixture()
        other = self.root / 'other'
        subprocess.run(['git', 'clone', '-q', str(self.repo), str(other)], check=True, capture_output=True)
        command = 'gh pr create --body-file "' + str(body) + '"'
        self.assert_pr_denied(self.hook('PreToolUse', tool_name='exec_command',
                                       tool_input={'cmd': command, 'workdir': str(other)}))

    def test_pr_preflight_missing_helper_denies(self):
        body, _ = self.pr_fixture()
        hook = self.root / 'isolated-hook'
        hook.mkdir()
        for name in ('craftkit-codex.js', 'craftkit-platform.js'):
            (hook / name).write_text((REPO / 'hooks' / name).read_text())
        payload = {'hook_event_name': 'PreToolUse', 'session_id': self.session, 'cwd': str(self.repo),
                   'tool_name': 'Bash', 'tool_input': {'command': 'gh pr create --body-file "' + str(body) + '"'}}
        result = subprocess.run(['node', str(hook / 'craftkit-codex.js')], input=json.dumps(payload),
                                env=self.env, text=True, capture_output=True, check=True)
        self.assert_pr_denied(json.loads(result.stdout))

    def test_pr_preflight_non_pr_and_gate_off_unchanged(self):
        for command in ('gh pr view 123', 'echo gh pr create', 'git status --short'):
            self.assertEqual(self.pr_hook(command), {})
        self.env['CRAFTKIT_GATE'] = 'off'
        self.assertEqual(self.pr_hook('gh pr create --body inline'), {})

    def test_pr_preflight_installer_migrates_only_managed_matchers(self):
        config = self.home / '.codex/hooks.json'
        config.parent.mkdir(parents=True)
        script = '_resolve_node_bin() { command -v node; }\nsource adapters/codex.sh\ninstall_codex_craftkit_hooks'
        env = dict(self.env, REPO_DIR=str(REPO))
        for previous in ('Bash', 'Bash|apply_patch|spawn_agent', 'apply_patch'):
            config.write_text(json.dumps({'hooks': {'PreToolUse': [{'matcher': previous, 'hooks': [
                {'type': 'command', 'command': 'user-hook'},
                {'type': 'command', 'command': 'node old/craftkit-codex.js'}]}]}}))
            subprocess.run(['/bin/bash', '-c', script], cwd=REPO, env=env, check=True, capture_output=True)
            first = config.read_text()
            subprocess.run(['/bin/bash', '-c', script], cwd=REPO, env=env, check=True, capture_output=True)
            self.assertEqual(config.read_text(), first)
            groups = json.loads(first)['hooks']['PreToolUse']
            managed = [g for g in groups for h in g['hooks'] if 'craftkit-codex.js' in h['command']]
            self.assertEqual(len(managed), 1)
            expected = previous if previous == 'apply_patch' else 'Bash|exec_command|apply_patch|spawn_agent'
            self.assertEqual(managed[0]['matcher'], expected)
            self.assertEqual([g['matcher'] for g in groups for h in g['hooks'] if h['command'] == 'user-hook'], [previous])

    def test_fresh_session_loads_generic_pr_routing(self):
        rules = self.home / '.craftkit/codex/rules'
        rules.mkdir(parents=True)
        (rules / 'using-agent-skills.md').write_text((REPO / 'rules/using-agent-skills.md').read_text())
        context = self.hook('SessionStart')['hookSpecificOutput']['additionalContext']
        self.assertIn('pr-message', context)
        self.assertIn('pr-followup', context)
        skill = self.home / '.agents/skills/pr-followup/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text((REPO / 'skills/pr-followup/SKILL.md').read_text())
        prompt_context = self.hook('UserPromptSubmit', prompt='$pr-followup inspect this PR')['hookSpecificOutput']['additionalContext']
        self.assertIn('$pr-followup: read ' + str(skill), prompt_context)

    def test_pr_capabilities_and_generated_guide_have_no_team_defaults(self):
        subprocess.run(['/bin/bash', '-c', 'source adapters/codex.sh\n_rebuild_codex_agents_md'],
                       cwd=REPO, env=self.env, capture_output=True, check=True)
        sources = [REPO / name for name in ('hooks/craftkit-pr-preflight.js', 'commands/pr-message.md',
                                            'skills/pr-followup/SKILL.md', 'rules/using-agent-skills.md')]
        sources.append(self.home / '.codex/AGENTS.md')
        for source in sources:
            content = source.read_text().lower()
            for team_default in ('gtr-team', 'traveloka', 'meegle', 'larksuite.com', 'gt-bus-train'):
                self.assertNotIn(team_default, content, str(source))
        guide = sources[-1].read_text()
        self.assertNotIn('development-workflow', guide)
        self.assertIn('pr-message', guide)
        self.assertIn('pr-followup', guide)

    def test_gate_off_does_not_inject_or_block(self):
        self.env['CRAFTKIT_GATE'] = 'off'
        self.assertEqual(self.hook('SessionStart'), {})
        self.assertEqual(self.hook('UserPromptSubmit'), {})
        self.assertEqual(self.hook('PreToolUse', tool_name='Bash', tool_use_id='off',
                                   tool_input={'command': 'bash check.sh'}), {})
        self.edit()
        self.assertEqual(self.hook('Stop'), {})

    def test_skill_request_is_a_pointer_not_a_second_body(self):
        skill = self.home / '.agents/skills/fixture-command/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('Exact command body from installed skill')
        result = self.hook('UserPromptSubmit', prompt='/fixture-command run this')
        context = result['hookSpecificOutput']['additionalContext']
        self.assertIn(str(skill), context)
        self.assertNotIn('Exact command body', context)

    def test_codex_rule_bridge_omits_claude_routing(self):
        rules = self.home / '.craftkit/codex/rules'
        rules.mkdir(parents=True)
        # As installed: sync.sh drops the CRAFTKIT-GATE-* marker lines while every gate is on.
        source = (REPO / 'rules/using-agent-skills.md').read_text().splitlines(True)
        (rules / 'using-agent-skills.md').write_text(''.join(
            line for line in source if not line.startswith(('<!-- BEGIN CRAFTKIT-GATE-', '<!-- END CRAFTKIT-GATE-'))))
        context = self.hook('SessionStart')['hookSpecificOutput']['additionalContext']
        self.assertIn('native Codex agents', context)
        self.assertNotIn('~/.claude.json', context)
        self.assertLess(len(context), 4500)

    def test_codex_model_routing_is_task_scoped_and_keeps_quality_gates(self):
        rules = self.home / '.craftkit/codex/rules'
        rules.mkdir(parents=True)
        (rules / 'using-agent-skills.md').write_text((REPO / 'rules/using-agent-skills.md').read_text())
        context = self.hook('SessionStart')['hookSpecificOutput']['additionalContext']
        for phrase in ("Keep the coordinator's model", 'runtime-listed cheaper model',
                       'correctness/security reviews', 'Honor user/profile pins',
                       'information are unavailable, inherit', 'fork_turns: none',
                       'retain all verification gates', 'verify cheaper-agent output'):
            self.assertIn(phrase, context)
        self.assertNotIn('gpt-', context)
        self.assertNotIn('Keep the configured model;', context)

    def test_codex_advice_protocol_reaches_coordinator(self):
        rules = self.home / '.craftkit/codex/rules'
        rules.mkdir(parents=True)
        (rules / 'using-agent-skills.md').write_text((REPO / 'rules/using-agent-skills.md').read_text())
        context = ' '.join(self.hook('SessionStart')['hookSpecificOutput']['additionalContext'].split())
        for phrase in ('ADVICE_REQUEST', 'ADVICE_RESPONSE', '2 failed hypotheses',
                       'next suitable stronger runtime-listed model', 'no stronger model is available',
                       'slots are full', 'escalation', 'Lower reasoning effort is not a cheaper model'):
            self.assertIn(phrase, context)

    def test_agent_contract_allows_explicit_escalation_and_requires_model(self):
        self.assertEqual(self.agent_spawn('escalation', model='runtime-stronger-model'), {})
        for model in (None, '', '  '):
            with self.subTest(model=model):
                self.assertEqual(self.agent_spawn('escalation', model=model)
                                 ['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_codex_model_policy_does_not_reach_other_tools(self):
        script = '''source adapters/claude.sh
CLAUDE_RULES_DIR="$HOME/claude-rules"; CLAUDE_MD="$HOME/CLAUDE.md"; CLAUDE_COMMANDS_DIR="$HOME/cmds"
install_claude_rule using-agent-skills rules/using-agent-skills.md
source adapters/gemini.sh
GEMINI_SKILLS_DIR="$HOME/gemini"; GEMINI_MD="$HOME/GEMINI.md"
install_gemini_rule using-agent-skills rules/using-agent-skills.md
source adapters/cursor.sh
CURSOR_RULES_DIR="$HOME/cursor"
install_cursor_rule using-agent-skills rules/using-agent-skills.md
'''
        subprocess.run(['/bin/bash', '-c', script], cwd=REPO, env=self.env,
                       check=True, capture_output=True)
        for name in ('CLAUDE.md', 'GEMINI.md', 'cursor/using-agent-skills.mdc'):
            content = (self.home / name).read_text()
            self.assertIn('Use the everyday model by default', content)
            self.assertNotIn('For subagents, choose a runtime-listed cheaper model', content)
            self.assertNotIn('Honor user/profile pins', content)
            self.assertNotIn('MODEL: <reason>', content)
            self.assertNotIn('ADVICE_REQUEST', content)

    def agent_spawn(self, reason='implementation', **fields):
        tool_input = dict(fork_turns='none', message=f'MODEL: {reason} - scoped task\nEdit app.js; verify: bash check.sh')
        tool_input.update(fields)
        return self.hook('PreToolUse', tool_name='spawn_agent', tool_input=tool_input,
                         turn_id='main-turn', tool_use_id='spawn')

    def test_agent_contract_requires_isolation_even_before_prompt(self):
        for fork in (None, 'all', ''):
            with self.subTest(fork=fork):
                out = self.agent_spawn(fork_turns=fork)['hookSpecificOutput']
                self.assertEqual(out['permissionDecision'], 'deny')
                self.assertIn('fork_turns: none', out['permissionDecisionReason'])
        self.assertEqual(self.agent_spawn(), {})

    def test_agent_contract_requires_decision_and_task_packet(self):
        for message in ('edit app.js', '', None, 'MODEL: unknown - task\nReview app.js',
                        'MODEL: implementation - \nEdit app.js',
                        'MODEL: implementation - scoped task\n  '):
            with self.subTest(message=message):
                self.assertEqual(self.agent_spawn(message=message)['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_agent_contract_bounded_work_requires_model_and_preserves_pins(self):
        for model in (None, '', '  '):
            with self.subTest(model=model):
                out = self.agent_spawn('bounded', model=model)['hookSpecificOutput']
                self.assertEqual(out['permissionDecision'], 'deny')
                self.assertIn('runtime-listed cheaper model', out['permissionDecisionReason'])
        self.assertEqual(self.agent_spawn('bounded', model='runtime-cheaper-model'), {})
        for reason in ('user-pin', 'profile-pin'):
            self.assertEqual(self.agent_spawn(reason), {})
            self.assertEqual(self.agent_spawn(reason, model='runtime-pinned-model'), {})

    def test_agent_contract_preserves_inheritance_for_quality_and_unavailable_models(self):
        for reason in ('implementation', 'critical-review', 'unavailable'):
            with self.subTest(reason=reason):
                self.assertEqual(self.agent_spawn(reason), {})
                self.assertEqual(self.agent_spawn(reason, model='override')['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_agent_contract_off_paths_preserve_old_spawn_behavior(self):
        self.gate_file('routing', 'off')
        self.assertEqual(self.agent_spawn(message='legacy task', fork_turns='all'), {})
        self.assertEqual(self.agent_spawn('escalation'), {})
        self.gate_file('routing', 'on')
        for variable in ('CRAFTKIT_GATE', 'CRAFTKIT_PANELIST'):
            self.env[variable] = 'off' if variable == 'CRAFTKIT_GATE' else '1'
            self.assertEqual(self.agent_spawn(message='legacy task', fork_turns='all'), {})
            self.env[variable] = ''

    def test_agent_contract_does_not_intercept_other_tools(self):
        self.assertEqual(self.hook('PreToolUse', tool_name='other_spawn_agent', tool_input={}), {})
        self.assertEqual(self.hook('PostToolUse', tool_name='spawn_agent', tool_input={}), {})

    def test_agent_contract_denial_cannot_disarm_director(self):
        self.env['CRAFTKIT_DELEGATE'] = 'on'
        self.patch('a.js')
        self.patch('b.js')
        self.assertEqual(self.agent_spawn(fork_turns='all')['hookSpecificOutput']['permissionDecision'], 'deny')
        self.denied(self.patch('c.js'))

    def test_agent_routing_off_does_not_disable_verification(self):
        self.gate_file('routing', 'off')
        self.start()
        self.edit()
        self.assertEqual(self.hook('Stop')['decision'], 'block')

    def test_generic_node_repo_does_not_load_evpmr(self):
        (self.repo / 'package.json').write_text('{}')
        rules = self.home / '.craftkit/codex/rules'
        rules.mkdir(parents=True)
        (rules / 'fe-rules.md').write_text((REPO / 'rules/fe-rules.md').read_text())
        self.assertNotIn('Layer constraints', json.dumps(self.hook('SessionStart')))
        (self.repo / 'package.json').write_text('{"dependencies":{"react":"*"}}')
        self.assertIn('Layer constraints', json.dumps(self.hook('SessionStart')))

    def test_managed_guide_refreshes_without_rule_changes(self):
        rules = self.home / '.craftkit/codex/rules'
        rules.mkdir(parents=True)
        (rules / 'fixture.md').write_text('unchanged rule')
        guide = self.home / '.codex/AGENTS.md'
        guide.parent.mkdir()
        guide.write_text('User guidance\n<!-- BEGIN CRAFTKIT (managed: do not edit manually) -->\nold guide\n<!-- END CRAFTKIT -->\n')
        script = 'source adapters/claude.sh\nsource adapters/codex.sh\nfinalize_codex'
        subprocess.run(['/bin/bash', '-c', script], cwd=REPO,
                       env=dict(self.env, REPO_DIR=str(REPO), CRAFTKIT_DASHBOARD_ON='0'),
                       capture_output=True, check=True)
        content = guide.read_text()
        self.assertIn('User guidance', content)
        self.assertNotIn('old guide', content)
        self.assertIn('parallel', content)

    def test_dashboard_recovers_missing_codex_subagent_stop(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('dashboard', REPO / 'scripts/dashboard.py')
        dashboard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dashboard)
        dashboard.DIR = str(self.home / 'events')
        dashboard.CODEX_SESSIONS = str(self.home / 'sessions')
        events = Path(dashboard.DIR)
        events.mkdir()
        log = events / 'parent.jsonl'
        log.write_text(json.dumps(dict(ts=time.time(), src='codex', e='SubagentStart',
                                       aid='child', type='worker')) + '\n')
        agents = events / 'parent.agents'
        agents.mkdir()
        (agents / 'child').write_text('worker')
        sessions = Path(dashboard.CODEX_SESSIONS) / '2026' / '10' / '13'
        sessions.mkdir(parents=True)
        transcript = sessions / 'rollout-date-child.jsonl'
        def record(kind):
            return json.dumps(dict(type='event_msg', payload=dict(type=kind, completed_at=time.time()))) + '\n'
        self.assertIn('child', dashboard.live_agents('parent', time.time()))
        dashboard.CODEX_TASKS.clear()
        transcript.write_text(record('task_started'))
        self.assertIn('child', dashboard.live_agents('parent', time.time()))
        with transcript.open('a') as f:
            f.write(record('task_complete'))
        self.assertNotIn('child', dashboard.live_agents('parent', time.time(), count_only=True))
        self.assertTrue(dashboard.load(str(log))['agents']['child']['end'])
        with transcript.open('a') as f:
            f.write(record('task_started'))
        self.assertIn('child', dashboard.live_agents('parent', time.time()))
        transcript.unlink()
        self.assertIn('child', dashboard.live_agents('parent', time.time()))
        transcript.write_text('malformed\n')
        self.assertIn('child', dashboard.live_agents('parent', time.time()))
        log.write_text(log.read_text().replace('codex', 'claude'))
        dashboard.META.clear()
        transcript.write_text(record('task_complete'))
        self.assertIn('child', dashboard.live_agents('parent', time.time()))

    def test_dashboard_session_end_timeout_is_capped_and_migrated(self):
        config = self.home / '.codex/hooks.json'
        script = 'source adapters/claude.sh\nsource adapters/codex.sh\ninstall_codex_dashboard_hook'
        env = dict(self.env, REPO_DIR=str(REPO), CRAFTKIT_DASHBOARD_ON='1')

        def install():
            subprocess.run(['/bin/bash', '-c', script], cwd=REPO, env=env,
                           capture_output=True, check=True)
            return json.loads(config.read_text())

        data = install()
        for event, groups in data['hooks'].items():
            self.assertEqual(groups[0]['hooks'][0]['timeout'], 3 if event == 'SessionEnd' else 5)
        managed = data['hooks']['SessionEnd'][0]['hooks'][0]
        managed['timeout'] = 5
        managed['custom'] = 'preserve'
        foreign = {'type': 'command', 'command': 'their-hook', 'timeout': 2}
        data['hooks']['SessionEnd'][0]['hooks'].append(foreign)
        config.write_text(json.dumps(data))

        migrated = install()
        hooks = migrated['hooks']['SessionEnd'][0]['hooks']
        self.assertEqual(hooks, [dict(managed, timeout=3), foreign])
        before = config.read_bytes()
        install()
        self.assertEqual(config.read_bytes(), before)
        env['CRAFTKIT_DASHBOARD_ON'] = '0'
        disabled = install()
        self.assertEqual(disabled['hooks'], {'SessionEnd': [{'hooks': [foreign]}]})

    def patch(self, *files, turn='main-turn', body=None, **fields):
        # Absolute, because the fixture repo sits under the temp dir the gate ignores as throwaway.
        if body is None:
            body = ''.join('*** Update File: /fixture/' + f + '\n@@\n-old\n+new\n' for f in files)
        self.env.setdefault('CRAFTKIT_DELEGATE', 'on')
        return self.hook('PreToolUse', tool_name='apply_patch', turn_id=turn, tool_use_id=uuid.uuid4().hex,
                         tool_input={'command': '*** Begin Patch\n' + body + '*** End Patch\n'}, **fields)

    def test_delegate_gate_is_opt_in_for_codex(self):
        self.env['CRAFTKIT_DELEGATE'] = ''
        self.assertEqual(self.patch('a.js'), {})
        self.assertEqual(self.patch('b.js'), {})
        self.env['CRAFTKIT_DELEGATE'] = 'on'
        self.env['CRAFTKIT_GATE'] = 'off'
        self.assertEqual(self.patch('c.js'), {})

    def gate_file(self, name, value):
        state = self.home / '.craftkit-state'
        state.mkdir(exist_ok=True)
        (state / ('gate-' + name)).write_text(value + '\n')

    def test_director_config_overrides_delegate_env(self):
        self.env['CRAFTKIT_DELEGATE'] = ''
        self.gate_file('director', 'on')
        self.patch('a.js')
        self.patch('b.js')
        self.denied(self.patch('c.js'))
        self.env['CRAFTKIT_DELEGATE'] = 'on'
        self.gate_file('director', 'off')
        self.assertEqual(self.patch('d.js', turn='t2'), {})
        self.assertEqual(self.patch('e.js', turn='t2'), {})
        self.assertEqual(self.patch('f.js', turn='t2'), {})

    def test_verify_gate_off_never_blocks(self):
        self.gate_file('verify', 'off')
        self.start()
        self.edit()
        self.assertEqual(self.hook('Stop'), {})
        self.assertEqual(self.hook('PreToolUse', tool_name='Bash', tool_input={'command': 'bash check.sh'},
                                   tool_use_id='v'), {})
        self.gate_file('verify', 'on')
        self.start()
        self.edit('newer\n')
        self.blocked()

    def test_prompt_context_respects_gate_states(self):
        for routing in ('on', 'off'):
            for verify in ('on', 'off'):
                with self.subTest(routing=routing, verify=verify):
                    self.gate_file('routing', routing)
                    self.gate_file('verify', verify)
                    context = self.hook('UserPromptSubmit')['hookSpecificOutput']['additionalContext']
                    self.assertEqual('Follow installed Codex skill routing.' in context, routing == 'on')
                    self.assertEqual('After edits, run' in context, verify == 'on')
                    if routing == 'off':
                        self.assertEqual(context, 'CraftKit: ' + (
                            'After edits, run the project verification command and report its result.'
                            if verify == 'on' else ''))

    def test_prompt_reminder_references_the_full_session_routing_contract(self):
        expected = (
            'CraftKit: Follow installed Codex skill routing. '
            'After edits, run the project verification command and report its result.'
        )
        self.assertEqual(self.hook('UserPromptSubmit')['hookSpecificOutput']['additionalContext'], expected)
        rules = self.home / '.craftkit/codex/rules'
        rules.mkdir(parents=True)
        (rules / 'using-agent-skills.md').write_text((REPO / 'rules/using-agent-skills.md').read_text())
        context = self.hook('SessionStart')['hookSpecificOutput']['additionalContext']
        for phrase in ('Classify task intent', 'Announce the selected', 'full rule referenced',
                       'parallel-build', 'parallel-review', 'parallel-ship', 'Before reporting completion'):
            self.assertIn(phrase, context)

    def test_explicit_skill_pointer_survives_disabled_routing(self):
        self.gate_file('routing', 'off')
        self.gate_file('verify', 'off')
        skill = self.home / '.agents/skills/fixture-command/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('fixture command')
        context = self.hook('UserPromptSubmit', prompt='$fixture-command')['hookSpecificOutput']['additionalContext']
        self.assertIn(str(skill), context)
        self.assertNotIn('classify this request', context)

    def test_delegate_rename_counts_the_destination_once(self):
        self.assertEqual(self.patch(body='*** Update File: /fixture/a.ts\n*** Move to: /fixture/b.ts\n@@\n-x\n+y\n'), {})
        self.assertEqual(self.patch('b.ts'), {})
        self.assertEqual(self.patch('c.ts'), {})

    def test_delegate_denied_edit_does_not_lock_the_first_file(self):
        self.patch('a.js')
        self.patch('b.js')
        self.denied(self.patch('c.ts'))
        self.assertEqual(self.patch('a.js'), {})

    def test_delegate_read_only_spawn_does_not_disarm(self):
        agents = self.home / '.codex/agents'
        agents.mkdir(parents=True)
        (agents / 'fe-review.toml').write_text('# CraftKit managed agent\nname = "fe-review"\nsandbox_mode = "read-only"\n')
        self.patch('a.js')
        self.patch('b.js')
        self.hook('PreToolUse', tool_name='spawn_agent', turn_id='main-turn', tool_use_id='ro',
                  tool_input={'agent_type': 'fe-review', 'fork_turns': 'none',
                              'message': 'MODEL: critical-review - correctness\nreview a.js'})
        self.denied(self.patch('c.js'))
        self.hook('PreToolUse', tool_name='spawn_agent', turn_id='main-turn', tool_use_id='rw',
                  tool_input={'fork_turns': 'none', 'message': 'MODEL: implementation - source change\nedit c.js; verify: bash check.sh'})
        self.assertEqual(self.patch('c.js'), {})

    def test_delegate_record_clears_on_new_prompt(self):
        self.patch('a.js')
        record = Path(tempfile.gettempdir()) / ('craftkit-codex-' +
                      hashlib.sha256(self.session.encode()).hexdigest()[:24] + '.json.delegate')
        self.assertTrue(record.exists())
        self.start()
        self.assertFalse(record.exists())

    def test_delegate_patch_headers_only_parse_in_a_patch(self):
        self.patch('a.js')
        self.patch('b.js')
        self.assertEqual(self.hook('PreToolUse', tool_name='Bash', turn_id='main-turn', tool_use_id='h',
                                   tool_input={'command': 'cat <<EOF\n*** Update File: /fixture/c.js\nEOF'}), {})

    def test_delegate_relative_paths_and_deletes_count(self):
        self.assertEqual(self.patch(body='*** Add File: src/a.js\n+x\n', cwd='/fixture/repo'), {})
        self.assertEqual(self.patch(body='*** Update File: src/a.js\n@@\n-x\n+y\n', cwd='/fixture/repo'), {})
        self.assertEqual(self.patch(body='*** Add File: src/c.js\n+x\n', cwd='/fixture/repo'), {})
        self.denied(self.patch(body='*** Delete File: src/b.js\n', cwd='/fixture/repo'))

    def denied(self, result):
        out = result.get('hookSpecificOutput', {})
        self.assertEqual(out.get('permissionDecision'), 'deny')
        self.assertIn('spawn_agent', out.get('permissionDecisionReason', ''))

    def test_delegate_gate_denies_third_source_file(self):
        self.assertEqual(self.patch('app.js'), {})
        self.assertEqual(self.patch('app.js'), {})
        self.assertEqual(self.patch('docs/plan.md'), {})
        self.assertEqual(self.patch('src/b.ts'), {})
        self.denied(self.patch('src/c.kt'))
        self.denied(self.patch('src/d.swift'))
        self.assertEqual(self.patch('src/b.ts', turn='next-turn'), {})

    def test_delegate_gate_counts_one_patch_and_shell_writes(self):
        self.denied(self.patch('a.js', 'b.js', 'c.js'))
        self.assertEqual(self.patch('a.js', turn='t2'), {})
        self.assertEqual(self.patch('b.js', turn='t2'), {})
        self.denied(self.hook('PreToolUse', tool_name='Bash', turn_id='t2', tool_use_id='s',
                              tool_input={'command': "sed -i '' 's/a/b/' /fixture/src/b.swift"}))
        self.assertEqual(self.hook('PreToolUse', tool_name='Bash', turn_id='t2', tool_use_id='r',
                                   tool_input={'command': 'node /fixture/src/b.js > out.log'}), {})

    def test_delegate_gate_passes_after_spawn_subagents_and_off(self):
        self.patch('a.js')
        self.patch('b.js')
        self.hook('PreToolUse', tool_name='spawn_agent', turn_id='main-turn', tool_use_id='sp',
                  tool_input={'fork_turns': 'none', 'message': 'MODEL: implementation - source change\nedit c.js; verify: bash check.sh'})
        self.assertEqual(self.patch('c.js'), {})
        self.patch('a.js', turn='t2', agent_id='child', agent_type='worker')
        self.patch('b.js', turn='t2', agent_id='child', agent_type='worker')
        self.assertEqual(self.patch('c.js', turn='t2', agent_id='child', agent_type='worker'), {})
        self.env['CRAFTKIT_DELEGATE'] = 'off'
        self.assertEqual(self.patch('a.js', turn='t3'), {})
        self.assertEqual(self.patch('b.js', turn='t3'), {})
        self.assertEqual(self.patch('c.js', turn='t3'), {})

    def test_delegate_shell_parsing_matches_claude_gate(self):
        import re
        grab = lambda f: re.search(r'^const QUOTED = .*?^}\n', (REPO / 'hooks' / f).read_text(),
                                   re.M | re.S).group().replace('DELEGATE_EXT', 'CODE_EXT')
        self.assertEqual(grab('craftkit-codex.js'), grab('gate-delegate.js'))

    def test_agent_profiles_render_live_rules_without_claude_models(self):
        import re
        source = (REPO / 'sync.sh').read_text()
        lib = self.root / 'render.sh'
        constants = '\n'.join(line for line in source.splitlines() if line.startswith('_CRAFTKIT_INJECTED_'))
        functions = '\n'.join(re.search(r'^' + name + r'\(\) \{\n.*?^\}', source, re.M | re.S).group()
                              for name in ('craftkit_inject_list', 'craftkit_strip_frontmatter', 'craftkit_strip_gate_blocks',
                                           'craftkit_render_injected'))
        lib.write_text(constants + '\n' + functions)
        env = dict(self.env, REPO_DIR=str(REPO), RULES_DIR=str(REPO / 'rules'),
                   SKILLS_DIR=str(REPO / 'skills'), PARTIALS_DIR=str(REPO / 'partials'))
        script = 'source "$1"\nsource adapters/codex.sh\ninstall_codex_agent fe-review agents/fe-review.md'
        subprocess.run(['/bin/bash', '-c', script, 'fixture', str(lib)], cwd=REPO,
                       env=env, check=True, capture_output=True)
        profile = self.home / '.codex/agents/fe-review.toml'
        fields = dict((key, json.loads(value)) for key, value in
                      (line.split(' = ', 1) for line in profile.read_text().splitlines() if ' = ' in line))
        self.assertEqual(fields['name'], 'fe-review')
        self.assertEqual(fields['sandbox_mode'], 'read-only')
        self.assertNotIn('model', fields)
        self.assertIn('Layer constraints', fields['developer_instructions'])
        self.assertIn('not provided', fields['developer_instructions'])
        for phrase in ('ADVICE_REQUEST', 'ADVICE_RESPONSE', '2 failed hypotheses',
                       'pause the uncertain work', 'do not spawn an advisor'):
            self.assertIn(phrase, fields['developer_instructions'])
        before = profile.read_text()
        subprocess.run(['/bin/bash', '-c', script, 'fixture', str(lib)], cwd=REPO,
                       env=env, check=True, capture_output=True)
        self.assertEqual(profile.read_text(), before)
        profile.write_text('name = "foreign"\n')
        result = subprocess.run(['/bin/bash', '-c', script, 'fixture', str(lib)], cwd=REPO,
                                env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(profile.read_text(), 'name = "foreign"\n')


if __name__ == '__main__':
    unittest.main()
