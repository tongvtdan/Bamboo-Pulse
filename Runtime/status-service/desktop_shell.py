#!/usr/bin/env python3
"""App-scoped exports for the desktop's captured login-shell environment."""
import fcntl
import os
from pathlib import Path
import shlex
import signal
import stat
import subprocess
import sys
import time
import uuid

from desktop_cohort import births, private_read, private_write, prepare_launch_source, MAX_WRITERS, slot_state, new_registry
from desktop_launcher import APP
from permission_status import hex_id

BEGIN = '# BEGIN PulseStick desktop startup v1'
END = '# END PulseStick desktop startup v1'
SAFE_RUNNER = 'import os,runpy,sys; p=sys.argv[1]; sys.argv=sys.argv[1:]; sys.path.append(os.path.dirname(p)); runpy.run_path(p,run_name="__main__")'


def profile_block(helper):
    command = shlex.quote(str(Path(helper).resolve()))
    interpreter = shlex.quote(str(Path(helper).resolve().parent.parent / 'python/bin/python3'))
    return (f'\n{BEGIN}\n'
            'if [[ ${CODEX_SHELL-} == 1 && ! -t 0 ]]; then\n'
            f'  pulsestick_desktop_exports=$({interpreter} -I -S -B -c {shlex.quote(SAFE_RUNNER)} {command} --shell-env 2>/dev/null)\n'
            '  eval "$pulsestick_desktop_exports"\n'
            '  unset pulsestick_desktop_exports\n'
            f'fi\n{END}\n')


def direct_collector_app():
    """The helper's immediate shell must itself be owned by the native app."""
    if os.environ.get('CODEX_SHELL') != '1' or os.isatty(0):
        return None
    shell = os.getppid()
    result = subprocess.run(['/bin/ps', '-p', str(shell), '-o', 'pid=,ppid=,comm='],
                            capture_output=True, text=True, timeout=.5)
    parts = result.stdout.strip().split(None, 2)
    if (result.returncode != 0 or result.stderr.strip() or len(parts) != 3 or
            not parts[0].isdigit() or int(parts[0]) != shell or not parts[1].isdigit()):
        raise ValueError('collector process unavailable')
    if parts[2] != '/bin/zsh':
        return None
    app = int(parts[1])
    result = subprocess.run(['/bin/ps', '-p', str(app), '-o', 'pid=,comm='],
                            capture_output=True, text=True, timeout=.5)
    parts = result.stdout.strip().split(None, 1)
    if result.returncode != 0 or result.stderr.strip() or len(parts) != 2:
        raise ValueError('app process unavailable')
    if not parts[0].isdigit() or int(parts[0]) != app or parts[1] != APP:
        return None
    identities = births([shell, app])
    if shell not in identities or app not in identities:
        raise ValueError('collector identity unavailable')
    return app, identities[app], shell, identities[shell]


def context_value(path):
    try:
        value = private_read(path)
    except FileNotFoundError:
        return None
    if (not isinstance(value, dict) or set(value) != {'version', 'source_id', 'app_pid', 'app_birth'} or
            value['version'] != 1 or type(value['version']) is not int or
            not hex_id(value['source_id']) or type(value['app_pid']) is not int or
            value['app_pid'] <= 1 or not hex_id(value['app_birth'])):
        raise ValueError('invalid launch context')
    return value


def clean_retired_root(root):
    if (type(root['sequence']) is not int or not 0 < root['sequence'] <= 0xffffffff or
            type(root['timestamp_ms']) is not int or not 0 < root['timestamp_ms'] <= int(time.time() * 1000) or
            not 0 < len(root['writers']) <= MAX_WRITERS):
        raise ValueError('invalid prior capture envelope')
    for writer in root['writers']:
        if (not isinstance(writer, dict) or writer.get('pending') != [] or
                writer.get('closed') is not True or writer.get('available') is not True or
                type(writer.get('sequence')) is not int or not 0 < writer['sequence'] <= 0xffffffff or
                type(writer.get('timestamp_ms')) is not int or not 0 < writer['timestamp_ms'] <= root['timestamp_ms']):
            raise ValueError('prior incomplete capture needs review')


def generation(source, app, app_birth):
    """Caller holds writer.lock; no producer can race source archival."""
    context_path = source.with_name('launch.json')
    context = context_value(context_path)
    if source.with_name('conflict.json').exists():
        raise ValueError('prior conflict needs review')
    try:
        root = private_read(source)
    except FileNotFoundError:
        root = None
    same = context is not None and (context['app_pid'], context['app_birth']) == (app, app_birth)
    if root is not None:
        if not isinstance(root, dict):
            raise ValueError('invalid source identity')
        slots = slot_state(root)
        if (set(root) != {'version', 'source_id', 'app_pid', 'app_birth', 'sequence', 'timestamp_ms', 'writers'} | ({'retired'} if slots is not None else set()) or
                not hex_id(root['source_id']) or type(root['app_pid']) is not int or root['app_pid'] <= 1 or
                not hex_id(root['app_birth']) or not isinstance(root['writers'], list)):
            raise ValueError('invalid source identity')
        if (root['app_pid'], root['app_birth']) == (app, app_birth):
            if context is not None and (not same or context['source_id'] != root['source_id']):
                raise ValueError('launch/source mismatch')
            cohort = root['source_id']
        else:
            if same:
                raise ValueError('launch/source mismatch')
            if context is not None and (context['app_pid'], context['app_birth'], context['source_id']) != (root['app_pid'], root['app_birth'], root['source_id']):
                raise ValueError('prior launch/source mismatch')
            # A restored card is not proven resolved merely because its process died.
            clean_retired_root(root)
            prepare_launch_source(source)
            cohort = uuid.uuid4().hex
    elif context is not None or source.with_name('writer.lock').stat().st_size:
        raise ValueError('prior source lost')
    else:
        cohort = uuid.uuid4().hex
    if root is None or (root['app_pid'], root['app_birth']) != (app, app_birth):
        # No live producer yet: readers reject this empty envelope as UNKNOWN.
        # Its durable presence distinguishes first startup from lost history.
        private_write(source, new_registry(cohort, app, app_birth))
    private_write(context_path, {'version': 1, 'source_id': cohort,
                                'app_pid': app, 'app_birth': app_birth})
    return cohort


def app_exports(source, wrapper, identity):
    app, app_birth, shell, shell_birth = identity
    source, wrapper = Path(source), Path(wrapper)
    source.parent.mkdir(mode=0o700, exist_ok=True)
    info = source.parent.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or
            stat.S_IMODE(info.st_mode) != 0o700 or wrapper.is_symlink() or
            not wrapper.is_file() or not os.access(wrapper, os.X_OK)):
        raise ValueError('unsafe startup installation')
    lock = os.open(source.with_name('writer.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(lock)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('unsafe startup lock')
        until = time.monotonic() + .25
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= until:
                    raise
                time.sleep(.01)
        live = births([app, shell])
        if live.get(app) != app_birth or live.get(shell) != shell_birth:
            raise ValueError('collector identity changed')
        cohort = generation(source, app, app_birth)
    finally:
        os.close(lock)
    values = {'CODEX_CLI_PATH': str(wrapper), 'BAMBOOX_PERMISSION_SOURCE': str(source),
              'BAMBOOX_PERMISSION_COHORT': cohort, 'BAMBOOX_PERMISSION_APP_PID': str(app),
              'BAMBOOX_PERMISSION_APP_BIRTH': app_birth}
    return '\n'.join(f'export {key}={shlex.quote(value)}' for key, value in values.items())


def main(source=None):
    if sys.argv[1:] != ['--shell-env']:
        return
    def deadline(signum, frame):
        raise TimeoutError('startup budget exceeded')
    signal.signal(signal.SIGALRM, deadline)
    signal.setitimer(signal.ITIMER_REAL, 2)
    source = Path(source) if source is not None else Path.home() / '.codex/pulsestick-permissions/desktop.json'
    verified = False
    try:
        identity = direct_collector_app()
        if identity is None:
            return
        verified = True
        output = app_exports(source, Path(__file__).resolve().with_name('codex-desktop-wrapper'), identity)
        print(output)
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError, TimeoutError):
        if verified:
            try:
                info = source.parent.lstat()
                if stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700:
                    private_write(source.with_name('conflict.json'), {'conflict': True})
            except (OSError, ValueError):
                pass
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)


if __name__ == '__main__':
    main()
