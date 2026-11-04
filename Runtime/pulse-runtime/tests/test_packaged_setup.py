"""Run against a staged payload, using disposable homes and local fixture sockets."""
import json
import os
from pathlib import Path
import socket
import sqlite3
import uuid
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

payload = Path(os.environ['PULSE_TEST_PAYLOAD']).resolve()
sys.path.insert(0, str(payload / 'status-service'))
import setup


class FreshSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir='/private/tmp')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.setup = setup.Setup(self.home, payload)
        self.cli = self.home / 'codex'
        self.cli.write_bytes(b'fixture')
        self.cli.chmod(0o700)

    def test_install_repeat_remove_preserve_user_config(self):
        hooks = self.setup.targets['hooks']
        hooks.parent.mkdir()
        original = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'echo fixture'}]}]}}
        hooks.write_text(json.dumps(original))
        profile = self.setup.targets['profile']
        profile.write_bytes(b'# existing profile\n')
        self.setup.install(self.cli)
        self.assertEqual(self.setup.install(self.cli)['state'], 'CONFIGURED')
        self.setup.remove()
        self.assertEqual(profile.read_bytes(), b'# existing profile\n')
        self.assertEqual(json.loads(hooks.read_bytes()), original)

    def test_reenable_after_real_observer_directory_created(self):
        self.setup.install(self.cli)
        self.setup.observer_dir.mkdir(mode=0o700)
        self.setup.remove()
        self.assertEqual(self.setup.status()['state'], 'NOT_CONFIGURED')
        self.assertEqual(self.setup.install(self.cli)['state'], 'CONFIGURED')
        self.setup.remove()
        self.setup.observer_dir.rename(self.home / 'original')
        self.setup.observer_dir.mkdir(mode=0o700)
        with self.assertRaisesRegex(ValueError, 'EXISTING_OBSERVER'):
            self.setup.install(self.cli)

    def test_payload_update_requires_matching_config_and_preserves_it(self):
        self.setup.install(self.cli)
        receipt = json.loads(self.setup.receipt.read_bytes())
        receipt['payload_id'] = 'previous-review'
        self.setup.receipt.write_text(json.dumps(receipt))
        before = {key: path.read_bytes() for key, path in self.setup.targets.items()}
        self.assertEqual(self.setup.status()['state'], 'UPDATE_REQUIRED')
        self.assertEqual(self.setup.install(self.cli)['state'], 'CONFIGURED')
        self.assertEqual(before, {key: path.read_bytes() for key, path in self.setup.targets.items()})
        receipt['block'] = 'foreign startup block'
        self.setup.receipt.write_text(json.dumps(receipt))
        self.assertEqual(self.setup.status()['state'], 'CONFIGURATION_CHANGED')
        with self.assertRaisesRegex(ValueError, 'CONFIGURATION_CHANGED'):
            self.setup.install(self.cli)

    def test_legacy_update_preserves_observer_evidence_and_foreign_hooks(self):
        self.setup.install(self.cli)
        profile = self.setup.targets['profile']
        legacy = setup.startup.profile_block(self.setup.helper, self.setup.interpreter).encode()
        profile.write_bytes(profile.read_bytes().replace(self.setup.block(), legacy))
        receipt = json.loads(self.setup.receipt.read_bytes())
        receipt.update(payload_id='review4', block=legacy.decode())
        self.setup.receipt.write_text(json.dumps(receipt))
        old = self.home / '.codex/pulsestick-permissions'
        old.mkdir(mode=0o700)
        (old / 'desktop.json').write_bytes(b'old unresolved evidence')
        hooks_before = self.setup.targets['hooks'].read_bytes()
        self.assertEqual(self.setup.install(self.cli)['state'], 'CONFIGURED')
        self.assertEqual(self.setup.targets['hooks'].read_bytes(), hooks_before)
        self.assertEqual((old / 'desktop.json').read_bytes(), b'old unresolved evidence')
        self.assertNotIn(b'PulseStick', profile.read_bytes())
        self.assertFalse(self.setup.observer_dir.exists())

    def test_duplicate_hooks_reject_update(self):
        self.setup.install(self.cli)
        path = self.setup.targets['hooks']
        config = json.loads(path.read_bytes())
        source = next(iter(config['hooks']))
        config['hooks'][source].append(config['hooks'][source][0])
        path.write_text(json.dumps(config))
        before = path.read_bytes()
        with self.assertRaisesRegex(ValueError, 'CONFIGURATION_CHANGED'):
            self.setup.install(self.cli)
        self.assertEqual(path.read_bytes(), before)

    def test_update_receipt_failure_rolls_back(self):
        self.setup.install(self.cli)
        receipt = json.loads(self.setup.receipt.read_bytes())
        receipt['payload_id'] = 'previous-review'
        self.setup.receipt.write_text(json.dumps(receipt))
        before = self.setup.receipt.read_bytes()
        original = setup.write
        def fail(path, data, home):
            if path == self.setup.receipt and data != before:
                raise OSError('fixture update interruption')
            original(path, data, home)
        with patch.object(setup, 'write', fail), self.assertRaises(OSError):
            self.setup.install(self.cli)
        self.assertEqual(self.setup.receipt.read_bytes(), before)
        self.assertEqual(self.setup.status()['state'], 'UPDATE_REQUIRED')

    def test_packaged_shell_uses_bamboo_observer_path(self):
        import runpy
        with patch('desktop_shell_core.main') as main, patch('pathlib.Path.home', return_value=self.home):
            runpy.run_path(str(payload / 'status-service/desktop_shell.py'), run_name='__main__')
        main.assert_called_once_with(self.home / 'Library/Application Support/BambooPulse/Observer/desktop.json')

    def test_receiptless_existing_hooks_rejected_without_duplication(self):
        self.setup.install(self.cli)
        self.setup.receipt.unlink()
        self.setup.targets['profile'].write_bytes(b'')
        raw = self.setup.targets['hooks'].read_bytes()
        with self.assertRaisesRegex(ValueError, 'UNRECORDED_HOOKS'):
            self.setup.install(self.cli)
        self.assertEqual(self.setup.targets['hooks'].read_bytes(), raw)

    def test_symlink_parent_blocks_update_and_removal(self):
        self.setup.install(self.cli)
        codex = self.home / '.codex'
        codex.rename(self.home / 'foreign')
        codex.symlink_to(self.home / 'foreign', target_is_directory=True)
        before = (self.home / 'foreign/hooks.json').read_bytes()
        for operation in (self.setup.status, self.setup.install, self.setup.remove):
            with self.assertRaisesRegex(ValueError, 'UNSAFE_DIRECTORY'):
                operation()
        self.assertEqual((self.home / 'foreign/hooks.json').read_bytes(), before)

    def test_test_reset_preserves_foreign_configuration(self):
        import reset_fixture
        self.setup.targets['hooks'].parent.mkdir()
        foreign = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'echo keep'}]}]}}
        self.setup.targets['hooks'].write_text(json.dumps(foreign))
        self.setup.targets['profile'].write_bytes(b'# keep my shell\n')
        self.setup.install(self.cli)
        observer = self.setup.observer_dir
        observer.mkdir(mode=0o700)
        (observer / 'desktop.json').write_bytes(b'pending history')
        with patch.object(reset_fixture, 'check_stopped'):
            reset_fixture.reset(self.home, payload)
        self.assertEqual(self.setup.status()['state'], 'NOT_CONFIGURED')
        self.assertFalse(self.setup.state.exists())
        backups = list((self.home / 'Desktop').glob('BambooPulse-test-backup-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'setup-after/Observer/desktop.json').read_bytes(), b'pending history')
        config = json.loads(self.setup.targets['hooks'].read_bytes())
        self.assertEqual(config, foreign)
        self.assertEqual(self.setup.targets['profile'].read_bytes(), b'# keep my shell\n')

    def test_reset_rejects_orphan_hooks_before_mutation(self):
        import reset_fixture
        self.setup.install(self.cli)
        self.setup.receipt.unlink()
        before = self.setup.targets['hooks'].read_bytes()
        with patch.object(reset_fixture, 'check_stopped'), self.assertRaisesRegex(
                ValueError, 'UNRECORDED_SETUP_REVIEW_REQUIRED'):
            reset_fixture.reset(self.home, payload)
        self.assertEqual(self.setup.targets['hooks'].read_bytes(), before)
        self.assertFalse((self.home / 'Desktop').exists())

    def test_interrupt_rolls_back_exact_preimages(self):
        original = setup.write
        def fail(path, data, home):
            if path == self.setup.receipt:
                raise OSError('fixture: interrupted before commit')
            original(path, data, home)
        with patch.object(setup, 'write', fail), self.assertRaises(OSError):
            self.setup.install(self.cli)
        for path in self.setup.targets.values():
            self.assertFalse(path.exists())
        self.assertEqual(self.setup.status()['state'], 'NOT_CONFIGURED')

    def test_foreign_setup_rejected(self):
        self.setup.targets['profile'].write_text('# BEGIN PulseStick desktop startup v1\n')
        with self.assertRaises(ValueError):
            self.setup.install(self.cli)
        self.assertFalse(self.setup.targets['hooks'].exists())

    def test_attention_and_navigation_require_fresh_matching_observation(self):
        from monitor import Monitor
        from model import identifier
        thread = str(uuid.uuid4())
        codex = self.home / '.codex'
        source = self.home / 'Library/Application Support/BambooPulse/Observer/desktop.json'
        source.parent.mkdir(parents=True, mode=0o700)
        codex.mkdir(exist_ok=True)
        with sqlite3.connect(codex / 'state_5.sqlite') as db:
            db.execute('create table threads(id,title,source,archived,agent_role,agent_path,thread_source)')
            db.execute("insert into threads values(?, 'Fixture', 'vscode', 0, null, null, 'user')", (thread,))
            db.execute('create table thread_spawn_edges(parent_thread_id,child_thread_id)')
        session = identifier(thread)
        row = {'session_id': session, 'turn_id': identifier('turn'), 'request_id': identifier('request')}
        observation = dict(version=1, source_id='a'*32, pid=os.getpid(), sequence=1,
                           timestamp_ms=int(time.time()*1000), available=True, pending=[row])
        source.write_text(json.dumps(observation))
        source.chmod(0o600)
        monitor = Monitor(self.home)
        def query(method, params):
            return json.loads(monitor.respond(dict(id='fixture', method=method, params=params)))['result']
        result = query('getActivityNow', {})
        self.assertEqual(result['sessions'][0]['state'], 'NEEDS_ATTENTION')
        self.assertEqual(query('getActivityChatLink', {'session_id': session})['thread_id'], thread)
        source.unlink()
        self.assertFalse(query('getActivityNow', {})['monitoring_available'])
        self.assertIsNone(query('getActivityChatLink', {'session_id': session})['thread_id'])

    def test_only_desktop_child_enters_observer(self):
        import desktop_bridge
        with patch.dict(os.environ, {'BAMBOOX_PERMISSION_APP_PID': str(os.getppid()),
                                     'BAMBOOX_PERMISSION_COHORT': 'a' * 32}), \
                patch.object(desktop_bridge.observer, 'main') as enter:
            desktop_bridge.main()
            enter.assert_called_once()

    def test_nested_diagnostic_forwards_without_touching_observer_registry(self):
        source = self.home / 'desktop.json'
        from desktop_cohort import birth, new_registry, private_write
        (self.home / '.codex').mkdir()
        app_pid = os.getppid()
        app_birth = birth(app_pid)
        private_write(source, new_registry('a' * 32, app_pid, app_birth))
        fixture = source.read_bytes()
        env = {**os.environ, 'HOME': str(self.home), 'CODEX_HOME': str(self.home / '.codex'),
               'BAMBOOX_PERMISSION_SOURCE': str(source), 'BAMBOOX_PERMISSION_COHORT': 'a' * 32,
               'BAMBOOX_PERMISSION_APP_PID': str(app_pid), 'BAMBOOX_PERMISSION_APP_BIRTH': app_birth}
        command = [str(payload / 'status-service/codex-desktop-wrapper'), 'app-server']
        request = {'id': 1, 'method': 'initialize',
                   'params': {'clientInfo': {'name': 'pulse_test', 'version': '1'}}}
        with subprocess.Popen(command, cwd=self.home, env=env, stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as proc:
            try:
                proc.stdin.write(json.dumps(request) + '\n')
                proc.stdin.flush()
                import select
                self.assertTrue(select.select([proc.stdout], [], [], 10)[0])
                self.assertIn('result', json.loads(proc.stdout.readline()))
            finally:
                proc.terminate()
                proc.wait(timeout=5)
        self.assertEqual(source.read_bytes(), fixture)
        self.assertFalse(source.with_name('writer.lock').exists())
        self.assertFalse(source.with_name('conflict.json').exists())

    def test_packaged_monitor_recovers_after_kill(self):
        endpoint = self.home / 'pulse/feed.sock'
        events = self.home / 'events/events.sock'
        program = 'import sys,pathlib;sys.path.insert(0,sys.argv[1]);import monitor;monitor.run(*sys.argv[2:])'
        for attempt in range(2):
            child = subprocess.Popen([str(payload/'python/bin/python3'), '-I', '-S', '-B', '-c',
                                      program, str(payload/'status-service'), str(self.home), str(endpoint), str(events)])
            try:
                for _ in range(100):
                    try:
                        with socket.socket(socket.AF_UNIX) as client:
                            client.settimeout(1)
                            client.connect(str(endpoint))
                            client.sendall(b'{"id":"fixture","method":"getActivityNow","params":{}}\n')
                            response = json.loads(client.makefile('rb').readline())
                        break
                    except (FileNotFoundError, ConnectionRefusedError):
                        time.sleep(.03)
                else:
                    self.fail('monitor did not respond')
                self.assertEqual(response['id'], 'fixture')
                self.assertFalse(response['result']['monitoring_available'])
                self.assertIsNone(response['result']['bar'])
            finally:
                child.kill() if attempt == 0 else child.terminate()
                child.wait(timeout=3)


if __name__ == '__main__':
    unittest.main()
