"""Private metadata fan-in for the stdio runtimes of one desktop launch."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import time
import uuid
from permission_status import MAX_REQUESTS, hex_id

MAX_WRITERS = 32
MAX_FILE = 65536
MAX_SEQUENCE = 0xffffffff
WRITER_KEYS = {'source_id', 'pid', 'birth', 'child_pid', 'child_birth', 'sequence',
               'timestamp_ms', 'available', 'closed', 'pending'}


def new_registry(cohort, app_pid, app_birth):
    return {'version': 3, 'source_id': cohort, 'app_pid': app_pid, 'app_birth': app_birth,
            'sequence': 0, 'timestamp_ms': 0, 'writers': [], 'retired': [0] * MAX_WRITERS}


def slot_state(root):
    """Version 3 certifies clean retirement with bounded per-slot high-water marks."""
    if type(root.get('version')) is not int or root['version'] not in (2, 3):
        raise ValueError('unsupported registry version')
    if root['version'] == 2:
        return None
    if (set(root) != {'version', 'source_id', 'app_pid', 'app_birth', 'sequence',
                     'timestamp_ms', 'writers', 'retired'} or
            not isinstance(root['retired'], list) or len(root['retired']) != MAX_WRITERS or
            any(type(n) is not int or not 0 <= n < MAX_SEQUENCE for n in root['retired']) or
            type(root['sequence']) is not int or not 0 <= root['sequence'] <= MAX_SEQUENCE or
            sum(root['retired']) > root['sequence'] or
            not isinstance(root['writers'], list) or len(root['writers']) > MAX_WRITERS):
        raise ValueError('invalid slot registry')
    slots, sources = set(), set()
    for item in root['writers']:
        if (not isinstance(item, dict) or set(item) != WRITER_KEYS | {'slot', 'generation'} or
                not hex_id(item['source_id']) or item['source_id'] in sources or
                type(item['slot']) is not int or not 0 <= item['slot'] < MAX_WRITERS or
                item['slot'] in slots or type(item['generation']) is not int or
                item['generation'] != root['retired'][item['slot']] + 1):
            raise ValueError('invalid producer slot')
        slots.add(item['slot']); sources.add(item['source_id'])
    return tuple(root['retired'])


def reclaim_slots(root):
    """Caller holds writer.lock. Never infer clean closure from process death."""
    candidates = [item for item in root['writers'] if item.get('closed') is True]
    for item in candidates:
        if (item['available'] is not True or item['pending'] != [] or
                not hex_id(item['birth']) or not hex_id(item['child_birth']) or
                any(type(item[k]) is not int or item[k] <= 1 for k in ('pid', 'child_pid')) or
                item['pid'] == item['child_pid'] or
                type(item['sequence']) is not int or not 0 < item['sequence'] <= MAX_SEQUENCE or
                type(item['timestamp_ms']) is not int or
                not 0 < item['timestamp_ms'] <= root['timestamp_ms']):
            raise ValueError('invalid closed producer')
    live = births({pid for item in candidates for pid in (item['pid'], item['child_pid'])})
    retired = list(root['retired'])
    removed = set()
    for item in candidates:
        if live.get(item['pid']) != item['birth'] and live.get(item['child_pid']) != item['child_birth']:
            retired[item['slot']] = item['generation']
            removed.add(item['source_id'])
    return {**root, 'retired': retired,
            'writers': [item for item in root['writers'] if item['source_id'] not in removed]}


def births(pids):
    pids = sorted({pid for pid in pids if type(pid) is int and pid > 1})
    if not pids:
        return {}
    try:
        result = subprocess.run(['/bin/ps', '-p', ','.join(map(str, pids)), '-o', 'pid=,lstart='],
                                capture_output=True, text=True, timeout=2,
                                env={**os.environ, 'LC_ALL': 'C'})
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValueError('process inspection unavailable') from error
    if result.returncode == 1 and not result.stdout.strip() and not result.stderr.strip():
        return {}
    if result.returncode != 0 or result.stderr.strip() or not result.stdout.strip():
        raise ValueError('process inspection failed')
    found = {}
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2 or not parts[0].isdigit() or int(parts[0]) not in pids or int(parts[0]) in found:
            raise ValueError('ambiguous process identity')
        try:
            time.strptime(parts[1], '%a %b %d %H:%M:%S %Y')
        except ValueError as error:
            raise ValueError('invalid process birth time') from error
        found[int(parts[0])] = hashlib.sha256(parts[1].encode()).hexdigest()[:32]
    return found


def birth(pid):
    return births([pid]).get(pid)


def app_pids(app):
    # pgrep excludes ancestors by default, including the app hosting this tool.
    try:
        result = subprocess.run(['/bin/ps', '-axo', 'pid=,comm='], capture_output=True,
                                text=True, timeout=2, env={**os.environ, 'LC_ALL': 'C'})
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValueError('app inspection unavailable') from error
    if result.returncode != 0 or result.stderr.strip() or not result.stdout.strip():
        raise ValueError('app inspection failed')
    found = []
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2 or not parts[0].isdigit():
            raise ValueError('ambiguous app process')
        if parts[1] == app:
            found.append(int(parts[0]))
    return found


def private_read(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as file:
        info = os.fstat(file.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or
                stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > MAX_FILE):
            raise ValueError('unsafe cohort snapshot')
        try:
            value = json.loads(file.read(MAX_FILE + 1))
        except (ValueError, RecursionError) as error:
            raise ValueError('invalid cohort snapshot') from error
    return value


def private_write(path, value):
    data = json.dumps(value, separators=(',', ':')).encode()
    if len(data) > MAX_FILE:
        raise ValueError('cohort snapshot exceeded')
    temp = path.with_name('.' + uuid.uuid4().hex + '.tmp')
    try:
        fd = os.open(temp, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as file:
            file.write(data)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


class CohortWriter:
    def __init__(self, path, cohort, app_pid, app_birth):
        self.path = Path(path)
        if not hex_id(cohort) or birth(app_pid) != app_birth:
            raise ValueError('invalid desktop generation')
        self.cohort, self.app_pid, self.app_birth = cohort, app_pid, app_birth
        self.source_id, self.pid = uuid.uuid4().hex, os.getpid()
        self.birth = birth(self.pid)
        self.sequence, self.child_pid, self.child_birth = 0, None, None
        self.slot, self.generation = None, None
        if self.birth is None:
            raise ValueError('missing producer identity')
        self.lock = os.open(self.path.with_name('writer.lock'),
                            os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
        info = os.fstat(self.lock)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or
                stat.S_IMODE(info.st_mode) != 0o600):
            os.close(self.lock)
            raise ValueError('unsafe registry lock')
        try:
            self.publish(False, [], required=True)
        except BaseException:
            os.close(self.lock)
            raise

    def poison(self):
        try:
            private_write(self.path.with_name('conflict.json'), {'conflict': True})
        except (OSError, ValueError):
            pass

    def attach(self, child_pid):
        if self.child_pid is not None:
            raise ValueError('child already attached')
        self.child_pid, self.child_birth = child_pid, birth(child_pid)
        if self.child_birth is None:
            raise ValueError('missing child identity')
        self.publish(False, [], required=True)

    def publish(self, available, pending, closed=False, required=False):
        deadline = time.monotonic() + (2 if required else 0)
        while True:
            try:
                fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    if required:
                        self.poison()
                        raise ValueError('registry lock timeout')
                    return False
                time.sleep(.01)
        try:
            try:
                root = private_read(self.path)
            except FileNotFoundError:
                root = None
            if root is not None and not isinstance(root, dict):
                raise ValueError('invalid registry')
            if root is not None and root.get('source_id') != self.cohort:
                raise ValueError('explicit desktop generation handoff required')
            if root is None:
                if (self.sequence or os.fstat(self.lock).st_size or
                        self.path.with_name('launch.json').exists() or
                        self.path.with_name('conflict.json').exists()):
                    raise ValueError('lost registry requires review')
                root = new_registry(self.cohort, self.app_pid, self.app_birth)
            slots = slot_state(root)
            if (root.get('app_pid') != self.app_pid or
                    root.get('app_birth') != self.app_birth or not isinstance(root.get('writers'), list)):
                raise ValueError('cohort identity mismatch')
            if os.fstat(self.lock).st_size == 0:
                # Survives registry loss, including a fresh producer/reader restart.
                os.write(self.lock, b'initialized\n')
                os.fsync(self.lock)
            required = WRITER_KEYS | ({'slot', 'generation'} if slots is not None else set())
            if (type(root.get('sequence')) is not int or not 0 <= root['sequence'] < 0xffffffff or
                    any(not isinstance(item, dict) or set(item) != required or
                        not isinstance(item['pending'], list) for item in root['writers'])):
                raise ValueError('malformed producer registry')
            old = next((x for x in root['writers'] if x.get('source_id') == self.source_id), None)
            if old is None and self.sequence:
                raise ValueError('registered producer missing')
            if old and slots is not None and (old['slot'], old['generation']) != (self.slot, self.generation):
                raise ValueError('producer slot changed')
            if old and (old['pid'] != self.pid or old['birth'] != self.birth or
                    (old['child_pid'] is not None and (old['child_pid'] != self.child_pid or old['child_birth'] != self.child_birth))):
                raise ValueError('producer identity changed')
            if old and (old['closed'] or old['sequence'] != self.sequence):
                raise ValueError('producer lifecycle conflict')
            if closed and (not available or pending or self.child_birth is None):
                raise ValueError('invalid clean close')
            sequence = self.sequence + 1
            capture = int(time.time() * 1000)
            value = {'source_id': self.source_id, 'pid': self.pid, 'birth': self.birth,
                     'child_pid': self.child_pid, 'child_birth': self.child_birth,
                     'sequence': sequence, 'timestamp_ms': capture, 'available': available,
                     'closed': closed, 'pending': pending}
            if slots is not None:
                if old is None and len(root['writers']) == MAX_WRITERS:
                    root = reclaim_slots(root)
                occupied = {item['slot'] for item in root['writers']}
                slot = old['slot'] if old else next((n for n in range(MAX_WRITERS) if n not in occupied), None)
                if slot is None:
                    raise ValueError('cohort capacity exceeded')
                value.update(slot=slot, generation=root['retired'][slot] + 1)
            writers = [x for x in root['writers'] if x.get('source_id') != self.source_id] + [value]
            if len(writers) > MAX_WRITERS or sum(len(x['pending']) for x in writers) > MAX_REQUESTS:
                raise ValueError('cohort capacity exceeded')
            root = {**root, 'sequence': root['sequence'] + 1, 'timestamp_ms': capture, 'writers': writers}
            if slots is not None:
                slot_state(root)
            private_write(self.path, root)
            self.sequence = sequence
            if slots is not None:
                self.slot, self.generation = value['slot'], value['generation']
            return True
        except (OSError, ValueError, TypeError, KeyError):
            self.poison()
            raise
        finally:
            fcntl.flock(self.lock, fcntl.LOCK_UN)


def prepare_launch_source(path, dry_run=False):
    """Only the launcher, after full quit, can move to a new app generation."""
    path = Path(path)
    if path.with_name('conflict.json').exists():
        raise ValueError('unobserved transport requires reviewed recovery')
    try:
        value = private_read(path)
    except FileNotFoundError:
        return
    if not isinstance(value, dict):
        raise ValueError('reviewed source migration required')
    slots = slot_state(value)
    if (set(value) != {'version', 'source_id', 'app_pid', 'app_birth', 'sequence', 'timestamp_ms', 'writers'} | ({'retired'} if slots is not None else set()) or
            not hex_id(value['source_id']) or
            type(value['app_pid']) is not int or value['app_pid'] <= 1 or not hex_id(value['app_birth']) or
            not isinstance(value['writers'], list) or not 0 < len(value['writers']) <= MAX_WRITERS):
        raise ValueError('reviewed source migration required')
    if (type(value['sequence']) is not int or not 0 < value['sequence'] <= 0xffffffff or
            type(value['timestamp_ms']) is not int or not 0 < value['timestamp_ms'] <= int(time.time() * 1000)):
        raise ValueError('invalid prior capture envelope')
    old = {value['app_pid']: value['app_birth']}
    sources = set()
    required = WRITER_KEYS | ({'slot', 'generation'} if slots is not None else set())
    for item in value['writers']:
        if (not isinstance(item, dict) or set(item) != required or not hex_id(item['source_id']) or
                item['source_id'] in sources or type(item['pid']) is not int or item['pid'] <= 1 or
                type(item['child_pid']) is not int or item['child_pid'] <= 1 or item['pid'] == item['child_pid'] or
                item['pid'] in old or item['child_pid'] in old or not hex_id(item['birth']) or not hex_id(item['child_birth'])):
            raise ValueError('invalid prior transport identity')
        if (item['closed'] is not True or item['available'] is not True or item['pending'] != [] or
                type(item['sequence']) is not int or not 0 < item['sequence'] <= 0xffffffff or
                type(item['timestamp_ms']) is not int or not 0 < item['timestamp_ms'] <= value['timestamp_ms']):
            raise ValueError('prior incomplete capture needs review')
        sources.add(item['source_id'])
        old[item['pid']] = item['birth'];old[item['child_pid']] = item['child_birth']
    current = births(old)
    if any(current.get(pid) == expected for pid, expected in old.items()):
        raise ValueError('previous app transport still alive')
    if not hex_id(value.get('source_id')):
        raise ValueError('invalid prior generation')
    archive = path.with_name(path.name + '.previous-' + value['source_id'])
    if archive.exists():
        raise ValueError('generation archive conflict')
    if len(list(path.parent.glob(path.name + '.previous-*'))) >= 32:
        raise ValueError('pilot archive capacity exceeded')
    if not dry_run:
        os.replace(path, archive)


def initialize_launch_source(path, cohort, app_pid, app_birth):
    """Explicit full-quit launcher handoff; producers cannot recreate lost history."""
    path = Path(path)
    lock = os.open(path.with_name('writer.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(lock)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('unsafe launch lock')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if not path.exists() and (os.fstat(lock).st_size or path.with_name('launch.json').exists()):
            raise ValueError('lost registry requires review')
        if not hex_id(cohort) or type(app_pid) is not int or app_pid <= 1 or birth(app_pid) != app_birth:
            raise ValueError('invalid launch identity')
        prepare_launch_source(path)
        private_write(path, new_registry(cohort, app_pid, app_birth))
        private_write(path.with_name('launch.json'), {'version': 1, 'source_id': cohort,
                                                    'app_pid': app_pid, 'app_birth': app_birth})
    finally:
        os.close(lock)
