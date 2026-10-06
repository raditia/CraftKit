#!/usr/bin/env python3
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
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
        self.verify(response='Process exited with code 0\nFinal output:\nAll checks passed.')
        self.assertEqual(self.hook('Stop'), {})

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

    def test_gate_off_does_not_inject_or_block(self):
        self.env['CRAFTKIT_GATE'] = 'off'
        self.assertEqual(self.hook('SessionStart'), {})
        self.assertEqual(self.hook('UserPromptSubmit'), {})
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
        (rules / 'using-agent-skills.md').write_text((REPO / 'rules/using-agent-skills.md').read_text())
        context = self.hook('SessionStart')['hookSpecificOutput']['additionalContext']
        self.assertIn('native Codex agents', context)
        self.assertNotIn('~/.claude.json', context)
        self.assertLess(len(context), 2500)

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
                  tool_input={'agent_type': 'fe-review', 'message': 'review a.js'})
        self.denied(self.patch('c.js'))
        self.hook('PreToolUse', tool_name='spawn_agent', turn_id='main-turn', tool_use_id='rw',
                  tool_input={'message': 'edit c.js; verify: bash check.sh'})
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
                  tool_input={'message': 'edit c.js; verify: bash check.sh'})
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
                              for name in ('craftkit_inject_list', 'craftkit_strip_frontmatter', 'craftkit_render_injected'))
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
