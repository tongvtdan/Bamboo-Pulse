"""Fresh-user Pulse setup. Fixed targets, explicit consent, no shared service."""
import base64
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import stat
import sys
import tempfile

import desktop_startup_setup as startup
import install as hooks
from model import HOOK_SOURCES

LIMIT = 262144


def read(path, limit=LIMIT):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o022 or info.st_size > limit):
            raise ValueError('UNSAFE_FILE')
        raw = stream.read(limit + 1)
    if len(raw) > limit:
        raise ValueError('FILE_TOO_LARGE')
    return raw


def directory(path, home):
    if path == home:
        return
    directory(path.parent, home)
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
        raise ValueError('UNSAFE_DIRECTORY')


def write(path, data, home):
    directory(path.parent, home)
    mode = stat.S_IMODE(path.lstat().st_mode) if os.path.lexists(path) else 0o600
    # Revalidate the file before replacing it. Caller holds the setup writer lock.
    read(path)
    fd, temp = tempfile.mkstemp(prefix='.pulse-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
        parent = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(parent)
        finally:
            os.close(parent)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


class Setup:
    def __init__(self, home, payload):
        self.home, self.payload = Path(home), Path(payload)
        self.state = self.home / 'Library/Application Support/BambooPulse'
        self.targets = {'profile': self.home / '.zshrc', 'hooks': self.home / '.codex/hooks.json'}
        self.receipt = self.state / 'setup.json'
        self.journal = self.state / 'transaction.json'
        self.observer_dir = self.state / 'Observer'
        self.helper = self.payload / 'status-service/desktop_shell.py'
        self.interpreter = self.payload / 'python/bin/python3'

    def commands(self):
        return {source: ' '.join(shlex.quote(x) for x in (
            str(self.interpreter), '-I', '-S', '-B', '-c', startup.SAFE_RUNNER,
            str(self.payload / 'status-service/hook.py'), source)) for source in HOOK_SOURCES}

    @contextmanager
    def locked(self):
        directory(self.state, self.home)
        fd = os.open(self.state / 'setup.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                raise ValueError('UNSAFE_LOCK')
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            yield
        finally:
            os.close(fd)

    def payload_id(self):
        manifest = json.loads((self.payload / 'manifest.json').read_bytes())
        if set(manifest) != {'version', 'files'} or manifest['version'] != 1:
            raise ValueError('PAYLOAD_MANIFEST_INVALID')
        for relative, expected in manifest['files'].items():
            path = self.payload / relative
            if (Path(relative).is_absolute() or '..' in Path(relative).parts
                    or not path.resolve().is_relative_to(self.payload.resolve())
                    or hashlib.sha256(path.read_bytes()).hexdigest() != expected):
                raise ValueError('PAYLOAD_CHANGED')
        for name in ('status-service/setup.py', 'status-service/monitor.py', 'python/bin/python3'):
            if name not in manifest['files']:
                raise ValueError('PAYLOAD_INCOMPLETE')
        return hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()

    def block(self):
        return startup.profile_block(self.helper, self.interpreter).replace(
            'PulseStick desktop startup v1', 'Bamboo Pulse desktop startup v1').encode()

    def validate_parents(self):
        for target in (*self.targets.values(), self.receipt):
            path = target.parent
            while path != self.home:
                try:
                    info = path.lstat()
                except FileNotFoundError:
                    path = path.parent
                    continue
                if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                        or info.st_mode & 0o022):
                    raise ValueError('UNSAFE_DIRECTORY')
                path = path.parent

    def status(self):
        self.validate_parents()
        if read(self.journal, limit=2 * 1024 * 1024) is not None:
            return {'state': 'RECOVERY_REQUIRED'}
        raw = read(self.receipt)
        if raw is None:
            return {'state': 'NOT_CONFIGURED'}
        value = json.loads(raw)
        if value.get('state') == 'DISABLED' and value.get('version') == 1:
            return {'state': 'NOT_CONFIGURED'}
        identity = self.payload_id()
        block = value['block'].encode()
        expected = self.block()
        legacy = startup.profile_block(self.helper, self.interpreter).encode()
        if value.get('version') != 1 or block not in (expected, legacy):
            return {'state': 'CONFIGURATION_CHANGED'}
        profile = read(self.targets['profile']) or b''
        config = hooks.validate_configuration(json.loads(read(self.targets['hooks']) or b'{}', object_pairs_hook=hooks.unique))
        configured = (profile.count(block) == 1 and
                      profile.count(b'# BEGIN Bamboo Pulse desktop startup v1') +
                      profile.count(startup.BEGIN.encode()) == 1) and all(
            sum(hooks.ours(entry, source, self.commands()) for entry in config.get('hooks', {}).get(source, [])) == 1
            for source in HOOK_SOURCES)
        if not configured:
            return {'state': 'CONFIGURATION_CHANGED'}
        return {'state': 'CONFIGURED' if value.get('payload_id') == identity and block == expected else 'UPDATE_REQUIRED'}

    def recover(self):
        raw = read(self.journal, limit=2 * 1024 * 1024)
        if raw is None:
            return
        value = json.loads(raw)
        if set(value) != {'version', 'changes', 'receipt'} or value['version'] != 1 or set(value['changes']) != set(self.targets):
            raise ValueError('JOURNAL_INVALID')
        entries = [(self.targets[key], entry) for key, entry in value['changes'].items()]
        entries.append((self.receipt, value['receipt']))
        decoded = []
        for path, entry in entries:
            if set(entry) != {'before', 'after'}:
                raise ValueError('JOURNAL_INVALID')
            before = None if entry['before'] is None else base64.b64decode(entry['before'], validate=True)
            after = None if entry['after'] is None else base64.b64decode(entry['after'], validate=True)
            if read(path) not in (before, after):
                raise ValueError('RECOVERY_CONFLICT')
            decoded.append((path, before))
        for path, before in reversed(decoded):
            if before is None:
                path.unlink(missing_ok=True)
            else:
                write(path, before, self.home)
        self.journal.unlink()

    def install(self, cli=startup.CODEX_CLI):
        with self.locked():
            self.recover()
            identity = self.payload_id()
            status = self.status()['state']
            if status == 'CONFIGURED':
                return {'state': 'CONFIGURED'}
            if status == 'UPDATE_REQUIRED':
                # Explicit install consent also authorizes this payload update.
                # Revalidate startup dependencies and preserve exact user config.
                startup.prepare(self.targets['profile'], self.helper, self.interpreter, cli)
                before = read(self.receipt)
                receipt = json.loads(before)
                receipt['payload_id'] = identity
                old_block = receipt['block'].encode()
                receipt['block'] = self.block().decode()
                changes = {}
                for key, path in self.targets.items():
                    raw = read(path)
                    changes[key] = (raw, raw.replace(old_block, self.block(), 1) if key == 'profile' else raw)
                self.apply(changes, before, json.dumps(receipt).encode())
                return {'state': 'CONFIGURED'}
            if status != 'NOT_CONFIGURED':
                raise ValueError(status)
            previous = read(self.receipt)
            disabled = json.loads(previous) if previous else {}
            # Fresh setup never adopts another runtime's metadata or event socket.
            if (os.path.lexists(self.home / '.local/state/bamboox-status/events.sock')
                    or (os.path.lexists(self.observer_dir) and
                        self.directory_identity() != disabled.get('observer_directory'))):
                raise ValueError('EXISTING_OBSERVER')
            for path in self.targets.values():
                directory(path.parent, self.home)
            before_profile, _, _, _ = startup.prepare(
                self.targets['profile'], self.helper, self.interpreter, cli)
            block = self.block()
            before_hooks = read(self.targets['hooks'])
            config = hooks.validate_configuration(json.loads(before_hooks or b'{}', object_pairs_hook=hooks.unique))
            groups = config.setdefault('hooks', {})
            if any(hooks.ours(entry, source, self.commands())
                   for source in HOOK_SOURCES for entry in groups.get(source, [])):
                raise ValueError('UNRECORDED_HOOKS')
            for source in HOOK_SOURCES:
                groups.setdefault(source, []).append({'hooks': [{'type': 'command',
                    'command': self.commands()[source], 'timeout': 1}]})
            if before_profile and (b'# BEGIN Bamboo Pulse desktop startup v1' in before_profile or block in before_profile):
                raise ValueError('EXISTING_OBSERVER')
            if len((before_profile or b'') + block) > LIMIT:
                raise ValueError('FILE_TOO_LARGE')
            after_hooks = hooks.serialized_configuration(config)
            receipt = json.dumps({'version': 1, 'payload_id': identity, 'block': block.decode()}).encode()
            self.apply({'profile': (before_profile, (before_profile or b'') + block),
                        'hooks': (before_hooks, after_hooks)}, previous, receipt)
        return {'state': 'CONFIGURED'}

    def apply(self, changes, prior_receipt, receipt):
        def encode(data):
            return None if data is None else base64.b64encode(data).decode()
        def entry(before, after):
            return {'before': encode(before), 'after': encode(after)}
        journal = {'version': 1, 'changes': {k: entry(*pair) for k, pair in changes.items()},
                   'receipt': entry(prior_receipt, receipt)}
        write(self.journal, json.dumps(journal).encode(), self.home)
        try:
            operations = [(self.targets[k], *pair) for k, pair in changes.items()]
            for path, before, after in [*operations, (self.receipt, prior_receipt, receipt)]:
                if read(path) != before:
                    raise ValueError('CONFIGURATION_CHANGED')
                if after is None:
                    path.unlink(missing_ok=True)
                else:
                    write(path, after, self.home)
            self.journal.unlink()
        except BaseException:
            self.recover()
            raise

    def directory_identity(self):
        info = self.observer_dir.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise ValueError('UNSAFE_OBSERVER_DIRECTORY')
        return [info.st_dev, info.st_ino]

    def remove(self):
        with self.locked():
            self.recover()
            if self.status()['state'] not in ('CONFIGURED', 'UPDATE_REQUIRED'):
                raise ValueError('CONFIGURATION_CHANGED')
            receipt = read(self.receipt)
            profile = read(self.targets['profile'])
            block = json.loads(receipt)['block'].encode()
            if profile.count(block) != 1:
                raise ValueError('CONFIGURATION_CHANGED')
            raw = read(self.targets['hooks'])
            config = hooks.validate_configuration(json.loads(raw, object_pairs_hook=hooks.unique))
            for source in HOOK_SOURCES:
                entries = config['hooks'][source]
                owned = [item for item in entries if hooks.ours(item, source, self.commands())]
                if len(owned) != 1:
                    raise ValueError('CONFIGURATION_CHANGED')
                entries.remove(owned[0])
                if not entries:
                    del config['hooks'][source]
            # The initial install required this location to be absent. Retain
            # its identity across disable so a foreign directory still blocks setup.
            disabled = {'version': 1, 'state': 'DISABLED', 'observer_directory':
                        self.directory_identity() if os.path.lexists(self.observer_dir) else None}
            self.apply({'profile': (profile, profile.replace(block, b'', 1)),
                        'hooks': (raw, hooks.serialized_configuration(config))}, receipt, json.dumps(disabled).encode())
        return {'state': 'NOT_CONFIGURED'}



def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('status', 'install', 'monitor', 'remove'):
        raise SystemExit(2)
    setup = Setup(Path.home(), Path(__file__).resolve().parent.parent)
    try:
        if sys.argv[1] == 'monitor':
            if setup.status()['state'] != 'CONFIGURED':
                raise ValueError('SETUP_REQUIRED')
            from monitor import run
            run()
            return
        result = {'install': setup.install, 'remove': setup.remove, 'status': setup.status}[sys.argv[1]]()
        print(json.dumps(result))
    except ValueError as error:
        if str(error) == 'EXISTING_OBSERVER' and sys.argv[1] == 'install':
            print(json.dumps({'state': 'EXISTING_OBSERVER'}))
            return
        print(json.dumps({'state': 'SETUP_BLOCKED'}))
        raise SystemExit(1)
    except (OSError, KeyError, TypeError):
        print(json.dumps({'state': 'SETUP_BLOCKED'}))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
