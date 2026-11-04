#!/usr/bin/env python3
"""Review and explicitly configure the desktop observer shell startup block."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import stat
import sys
import tempfile

CODEX_CLI = Path('/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex')
BEGIN = '# BEGIN PulseStick desktop startup v1'
END = '# END PulseStick desktop startup v1'
OBSERVER_FILES = ('desktop_shell.py', 'desktop_bridge.py', 'desktop_cohort.py',
                  'desktop_launcher.py', 'async_questions.py', 'model.py', 'permission_status.py',
                  'desktop_json_stream.py', 'desktop_diagnostics.py')
SAFE_RUNNER = 'import os,runpy,sys; p=sys.argv[1]; sys.argv=sys.argv[1:]; sys.path.append(os.path.dirname(p)); runpy.run_path(p,run_name="__main__")'


def profile_block(helper, interpreter):
    return (f'\n{BEGIN}\n'
            'if [[ ${CODEX_SHELL-} == 1 && ! -t 0 ]]; then\n'
            f'  pulsestick_desktop_exports=$({shlex.quote(str(interpreter))} -I -S -B -c {shlex.quote(SAFE_RUNNER)} {shlex.quote(str(helper))} --shell-env 2>/dev/null)\n'
            '  eval "$pulsestick_desktop_exports"\n'
            '  unset pulsestick_desktop_exports\n'
            f'fi\n{END}\n')


def read_profile(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None, 0o600
    with os.fdopen(fd, 'rb') as file:
        info = os.fstat(file.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 262144:
            raise ValueError('unsafe shell profile')
        return file.read(262145), stat.S_IMODE(info.st_mode)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_identity(path, executable=False):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as file:
        info = os.fstat(file.fileno())
        if not stat.S_ISREG(info.st_mode) or (executable and not os.access(path, os.X_OK)):
            raise ValueError('unsafe or non-executable dependency')
        raw = file.read()
    return {'path': str(path), 'sha256': digest(raw), 'mode': stat.S_IMODE(info.st_mode)}


def previous_identity(path, executable=False):
    try:
        target = path.resolve(strict=True) if executable else path
        return file_identity(target, executable=executable)
    except FileNotFoundError:
        if os.path.lexists(path):
            raise ValueError('broken previous runtime path')
        return None


def prepare(profile, helper, interpreter=None, cli=CODEX_CLI, previous_helper=None):
    if interpreter is None:
        interpreter = Path(helper).resolve().parent.parent / 'python/bin/python3'
    profile, helper, interpreter, cli = map(Path, (profile, helper, interpreter, cli))
    if not all(p.is_absolute() for p in (profile, helper, interpreter, cli)) or helper.is_symlink() or cli.is_symlink():
        raise ValueError('expected absolute profile and executable paths')
    helper = helper.resolve(strict=True)
    wrapper = helper.with_name('codex-desktop-wrapper')
    resolved_interpreter = interpreter.resolve(strict=True)
    resolved_cli = cli.resolve(strict=True)
    if helper.name != 'desktop_shell.py' or wrapper.is_symlink():
        raise ValueError('unexpected observer helper or wrapper')
    files = {name: file_identity(helper.with_name(name)) for name in OBSERVER_FILES}
    wrapper_identity = file_identity(wrapper, executable=True)
    interpreter_identity = file_identity(resolved_interpreter, executable=True)
    cli_identity = file_identity(resolved_cli, executable=True)
    expected_wrapper = ('#!/bin/sh\n'
        'bridge_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1\n'
        f'exec "$bridge_dir/../python/bin/python3" -I -S -B -c {shlex.quote(SAFE_RUNNER)} "$bridge_dir/desktop_bridge.py" "$@"\n')
    if wrapper.read_bytes() != expected_wrapper.encode():
        raise ValueError('wrapper interpreter binding changed')
    if interpreter != helper.parent.parent / 'python/bin/python3':
        raise ValueError('interpreter must be the packaged runtime')
    data, mode = read_profile(profile)
    block = profile_block(helper, interpreter).encode()
    previous = None
    if previous_helper is not None:
        text = str(previous_helper)
        old_helper = Path(text)
        if (not old_helper.is_absolute() or str(old_helper) != text or os.path.normpath(text) != text or
                any(char in text for char in '\0\r\n') or old_helper.name != 'desktop_shell.py' or old_helper == helper):
            raise ValueError('invalid previous startup helper')
        old_interpreter = old_helper.parent.parent / 'python/bin/python3'
        old_block = profile_block(old_helper, old_interpreter).encode()
        if data is None or data.count(old_block) != 1 or data.count(BEGIN.encode()) != 1 or data.count(END.encode()) != 1:
            raise ValueError('previous startup block does not match')
        previous = {'helper_invoked': str(old_helper), 'helper': previous_identity(old_helper),
                    'interpreter_invoked': str(old_interpreter), 'interpreter': previous_identity(old_interpreter, executable=True),
                    'block_sha256': digest(old_block)}
        after = data.replace(old_block, block, 1)
    else:
        if data is not None and (data.count(BEGIN.encode()) != data.count(block) or data.count(END.encode()) != data.count(block) or data.count(block) > 1):
            raise ValueError('existing startup block needs review')
        after = data if data is not None and block in data else (data or b'') + block
    identity = {'profile': str(profile), 'profile_sha256': digest(data) if data is not None else 'ABSENT',
                'profile_mode': mode, 'observer_files': files, 'wrapper': wrapper_identity,
                'bootstrap': file_identity(Path(__file__).resolve()), 'cli_invoked': str(cli), 'codex_cli': cli_identity,
                'interpreter_invoked': str(interpreter), 'interpreter': interpreter_identity,
                'block_sha256': digest(block), 'previous': previous, 'after_sha256': digest(after)}
    return data, mode, block, identity


def review_token(identity):
    return digest(json.dumps(identity, sort_keys=True, separators=(',', ':')).encode())


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def install(profile, helper, expected, interpreter=None, cli=CODEX_CLI, previous_helper=None):
    profile = Path(profile)
    before, mode, block, identity = prepare(profile, helper, interpreter, cli, previous_helper)
    if review_token(identity) != expected:
        raise ValueError('startup inputs changed since review')
    if previous_helper is None and before is not None and block in before:
        return 'ALREADY_CONFIGURED'
    if previous_helper is None:
        after = (before or b'') + block
    else:
        previous = Path(previous_helper)
        old_block = profile_block(previous, previous.parent.parent / 'python/bin/python3').encode()
        after = before.replace(old_block, block, 1)
    if digest(after) != identity['after_sha256']:
        raise ValueError('startup replacement changed')
    backup_name = None
    if before is not None:
        backup_fd, backup_name = tempfile.mkstemp(prefix='.attention-zshrc-backup-', dir=profile.parent)
        with os.fdopen(backup_fd, 'wb') as backup:
            backup.write(before); backup.flush(); os.fsync(backup.fileno())
        sync_directory(profile.parent)
    fd, temporary = tempfile.mkstemp(prefix='.attention-zshrc-', dir=profile.parent)
    try:
        with os.fdopen(fd, 'wb') as file:
            file.write(after); file.flush(); os.fsync(file.fileno())
        os.chmod(temporary, mode)
        if prepare(profile, helper, interpreter, cli, previous_helper) != (before, mode, block, identity):
            raise ValueError('startup inputs changed during setup')
        if before is None:
            os.link(temporary, profile, follow_symlinks=False)
        else:
            os.replace(temporary, profile)
        sync_directory(profile.parent)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return 'CONFIGURED; backup=' + (backup_name or 'not needed')


def main():
    if not sys.flags.isolated or not sys.flags.no_site:
        raise SystemExit('invoke with python3 -I -S -B')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true')
    parser.add_argument('--expected-review-sha256')
    parser.add_argument('--previous-helper', help='absolute helper path from the exact old managed block')
    args = parser.parse_args()
    profile = Path.home() / '.zshrc'
    helper = Path(__file__).resolve().with_name('desktop_shell.py')
    try:
        before, _, block, identity = prepare(profile, helper, previous_helper=args.previous_helper)
        if args.install:
            if not args.expected_review_sha256:
                raise ValueError('reviewed input digest required')
            print(install(profile, helper, args.expected_review_sha256, previous_helper=args.previous_helper))
        else:
            print(json.dumps({'state': 'ALREADY_CONFIGURED' if before is not None and block in before else 'READY_FOR_SETUP',
                              'review_sha256': review_token(identity), 'inputs': identity}, sort_keys=True))
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
