"""Reversible, additive Codex hook configuration; never touches config.toml."""
import argparse
import copy
import json
import os
import shlex
import stat
import sys
import tempfile
import time
from pathlib import Path
from model import HOOK_SOURCES

LIMIT = 262144


def command(source):
    return ' '.join(shlex.quote(part) for part in
                    (sys.executable, str(Path(__file__).with_name('hook.py').resolve()), source))


def ours(entry, source=None, commands=None):
    hooks = entry.get('hooks') if isinstance(entry, dict) else None
    return (isinstance(entry, dict) and set(entry) == {'hooks'} and isinstance(hooks, list) and len(hooks) == 1
            and isinstance(hooks[0], dict)
            and set(hooks[0]) == {'type', 'command', 'timeout'}
            and type(hooks[0]['timeout']) is int and hooks[0]['timeout'] == 1
            and hooks[0].get('command') in {(commands[s] if commands is not None else command(s))
                for s in (HOOK_SOURCES if source is None else (source,))}
            and hooks[0].get('type') == 'command')


def reject_constant(value):
    raise ValueError('non-JSON numeric constant')


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate hook configuration key; no changes made')
        result[key] = value
    return result


def validate_configuration(config):
    # Validate containers everywhere, but preserve unknown fields and hook types.
    json.dumps(config, allow_nan=False)
    if not isinstance(config, dict) or not isinstance(config.get('hooks', {}), dict):
        raise ValueError('invalid hook configuration; no changes made')
    for entries in config.get('hooks', {}).values():
        if not isinstance(entries, list):
            raise ValueError('invalid hook entries; no changes made')
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get('hooks'), list):
                raise ValueError('invalid hook entry; no changes made')
            for hook in entry['hooks']:
                if not isinstance(hook, dict) or not isinstance(hook.get('type'), str) or not hook['type']:
                    raise ValueError('invalid hook type; no changes made')
                if hook['type'] == 'command':
                    if not isinstance(hook.get('command'), str) or not shlex.split(hook['command']):
                        raise ValueError('invalid hook command; no changes made')
    return config


def serialized_configuration(config):
    data = (json.dumps(config, indent=2) + '\n').encode('utf-8')
    if len(data) > LIMIT:
        raise ValueError('proposed hook configuration exceeds size limit; no changes made')
    return data


def read_configuration(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        if path.is_symlink():
            raise ValueError('refusing symlink hook configuration') from None
        return None, 0o600
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or
                info.st_mode & 0o022 or info.st_size > LIMIT):
            raise ValueError('unsafe or oversized hook configuration')
        raw = stream.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise ValueError('oversized hook configuration')
        return raw, stat.S_IMODE(info.st_mode)


def retained_commands(retained):
    identities = (retained,) if (isinstance(retained, tuple) and len(retained) == 2 and
                                all(isinstance(v, str) for v in retained)) else retained
    if (not isinstance(identities, tuple) or not 0 < len(identities) <= 8 or
            any(not isinstance(pair, tuple) or len(pair) != 2 or
                any(not isinstance(v, str) or not v or not Path(v).is_absolute() for v in pair)
                for pair in identities) or len(set(identities)) != len(identities)):
        raise ValueError('invalid retained hook identities')
    return [{source: ' '.join(shlex.quote(part) for part in
                             (python, str(Path(runtime) / 'status-service/hook.py'), source))
             for source in HOOK_SOURCES} for runtime, python in identities]


def configure(path, install, sources=None, *, retained=None):
    sources = tuple(HOOK_SOURCES if sources is None else sources)
    if not sources or len(set(sources)) != len(sources) or any(source not in HOOK_SOURCES for source in sources):
        raise ValueError('invalid hook source selection')
    commands = [None]
    if retained is not None:
        if install:
            raise ValueError('retained identities are removal-only')
        commands = retained_commands(retained)
    path = Path(path).expanduser()
    if path.is_symlink():
        raise ValueError('refusing symlink hook configuration')
    previous, mode = read_configuration(path)
    if previous is None and not install:
        return None
    config = validate_configuration(json.loads(previous, object_pairs_hook=unique,
                                              parse_constant=reject_constant) if previous is not None else {})
    config = copy.deepcopy(config)
    hooks = config.get('hooks', {})
    for source in sources:
        entries = hooks.get(source, [])
        owned = [any(ours(entry, source, selected) for selected in commands) for entry in entries]
        if install:
            if not any(owned):
                hooks[source] = [*entries, {'hooks': [{'type': 'command', 'command': command(source), 'timeout': 1}]}]
            continue
        kept = []
        for index, entry in enumerate(entries):
            if not owned[index]:
                if len(kept) != index:
                    raise ValueError('removal would move an unowned hook identity; manual review required')
                kept.append(entry)
        if not any(owned):
            continue
        if kept:
            hooks[source] = kept
        else:
            hooks.pop(source, None)
    if hooks or 'hooks' in config:
        config['hooks'] = hooks
    if previous is not None and json.loads(previous) == config:
        return None
    data = serialized_configuration(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if previous is not None:
        backup = path.with_name(path.name + f'.bamboox-backup-{time.time_ns()}')
        fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as file:
            file.write(previous)
    fd, temporary = tempfile.mkstemp(prefix='.bamboox-hooks-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as file:
            os.fchmod(file.fileno(), mode)
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        # Refuse to overwrite a configuration changed while we prepared the update.
        current, current_mode = read_configuration(path)
        if current != previous or current_mode != mode:
            raise ValueError('hook configuration changed concurrently; retry')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return backup


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Remove only exact retained hooks with current ownership rules.')
    parser.add_argument('operation', choices=('remove-retained',))
    parser.add_argument('--runtime', action='append', required=True)
    parser.add_argument('--python', action='append', required=True)
    parser.add_argument('--config', default=str(Path.home() / '.codex/hooks.json'))
    args = parser.parse_args()
    try:
        if len(args.runtime) != len(args.python):
            raise ValueError('retained runtime/interpreter counts differ')
        configure(args.config, False, retained=tuple(zip(args.runtime, args.python)))
    except (OSError, ValueError, TypeError, RecursionError) as error:
        parser.exit(1, str(error) + '\n')
