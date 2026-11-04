"""Reset a disposable fixture home while preserving its original configuration."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from setup import Setup, directory, read, hooks, startup


def check_stopped():
    result = subprocess.run(['/bin/ps', '-axo', 'uid=,pid=,command='],
                            check=True, capture_output=True, text=True, timeout=3)
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) != 3 or not parts[0].isdigit() or not parts[1].isdigit():
            raise ValueError('PROCESS_CHECK_FAILED')
        if int(parts[0]) != os.getuid() or int(parts[1]) == os.getpid():
            continue
        command = parts[2]
        if ('/Applications/ChatGPT.app/Contents/MacOS/ChatGPT' in command or
                '/Applications/Bamboo Pulse.app/Contents/MacOS/Bamboo Pulse' in command or
                '/PulseRuntime/python/' in command):
            raise ValueError('QUIT_CHATGPT_AND_PULSE_FIRST')


def reset(home, payload):
    home = Path(home).resolve()
    if home.parent != Path('/private/tmp') or home == Path.home().resolve():
        raise ValueError('FIXTURE_HOME_REQUIRED')
    setup = Setup(home, payload)
    check_stopped()
    if os.path.lexists(home / '.local/state/bamboox-status/events.sock'):
        raise ValueError('EVENT_SOCKET_REMAINS_REVIEW_REQUIRED')
    with setup.locked():
        setup.recover()
        state = setup.status()['state']
        if state not in ('CONFIGURED', 'UPDATE_REQUIRED', 'NOT_CONFIGURED'):
            raise ValueError('CONFIGURATION_CHANGED')
        if state == 'NOT_CONFIGURED':
            profile = read(setup.targets['profile']) or b''
            config = hooks.validate_configuration(json.loads(
                read(setup.targets['hooks']) or b'{}', object_pairs_hook=hooks.unique))
            if (b'# BEGIN Bamboo Pulse desktop startup v1' in profile or
                    startup.BEGIN.encode() in profile or
                    any(hooks.ours(entry, source, setup.commands())
                        for source in setup.commands()
                        for entry in config.get('hooks', {}).get(source, []))):
                raise ValueError('UNRECORDED_SETUP_REVIEW_REQUIRED')
        backup = home / 'Desktop' / ('BambooPulse-test-backup-' + time.strftime('%Y%m%d-%H%M%S'))
        if backup.exists():
            raise ValueError('BACKUP_EXISTS')
        directory(backup, home)
        for name, path in setup.targets.items():
            raw = read(path)
            if raw is not None:
                (backup / (name + '.before')).write_bytes(raw)
        # Preserve every test setup artifact before removing known configuration.
        if setup.state.exists():
            shutil.copytree(setup.state, backup / 'setup-before', symlinks=True)
    if state != 'NOT_CONFIGURED':
        setup.remove()
    # Recheck after removal before archiving evidence. All moves are reversible.
    check_stopped()
    with setup.locked():
        if setup.status()['state'] != 'NOT_CONFIGURED':
            raise ValueError('SETUP_CHANGED')
        # Historical metadata is archived, never interpreted as resolved requests.
        for path in sorted((home / '.codex').glob('pulsestick-permissions*')):
            directory(path, home)
            path.rename(backup / path.name)
        if setup.observer_dir.exists():
            setup.directory_identity()
        # Moving the complete state retains the disabled receipt and lock as evidence.
        setup.state.rename(backup / 'setup-after')
    print('Pulse setup reset. Backup saved to ' + str(backup))
