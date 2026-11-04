"""Read complete pseudonymous permission snapshots; never handles decisions."""
import json
import hashlib
import os
from pathlib import Path
import stat
from permission_status import PermissionStatus, hex_id, LEASE_MS
from desktop_cohort import births, MAX_WRITERS, slot_state, WRITER_KEYS

MAX_FILE = 65536


class PermissionSource:
    def __init__(self, path):
        self.path = Path(path).absolute()
        self.tracker = PermissionStatus()
        self.source = None
        self.last_sequence = 0
        self.cohort_identity = None
        self.cohort_records = {}
        self.cohort_retired = None
        self.process_cache = ({}, frozenset(), None)

    def project(self, *args):
        return self.tracker.project(*args)

    def poll(self, visible, wall_ms, now):
        try:
            directory = self.path.parent.lstat()
            if (not stat.S_ISDIR(directory.st_mode) or directory.st_uid != os.getuid()
                    or stat.S_IMODE(directory.st_mode) != 0o700):
                raise ValueError('unsafe source directory')
            if self.path.with_name('conflict.json').exists():
                raise ValueError('multiple runtime owners')
            fd = os.open(self.path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(fd, 'rb') as file:
                info = os.fstat(file.fileno())
                if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                        or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > MAX_FILE):
                    raise ValueError('unsafe source file')
                raw = file.read(MAX_FILE + 1)
            if len(raw) > MAX_FILE:
                raise ValueError('oversize snapshot')
            value = json.loads(raw)
            if isinstance(value, dict) and value.get('version') in (2, 3):
                self.poll_cohort(value, visible, wall_ms, now)
                return
            if (not isinstance(value, dict) or set(value) != {'version', 'source_id', 'pid',
                    'sequence', 'timestamp_ms', 'available', 'pending'} or
                    type(value['version']) is not int or value['version'] != 1 or
                    not hex_id(value['source_id']) or type(value['pid']) is not int or value['pid'] <= 1 or
                    type(value['sequence']) is not int or not 0 < value['sequence'] <= 0xffffffff or
                    type(value['timestamp_ms']) is not int or
                    not wall_ms - LEASE_MS < value['timestamp_ms'] <= wall_ms or
                    value['available'] is not True or not isinstance(value['pending'], list) or visible is None):
                raise ValueError('unavailable snapshot')
            os.kill(value['pid'], 0)
            source = (value['source_id'], value['pid'])
            if self.source != source:
                if self.source is not None:
                    try:
                        os.kill(self.source[1], 0)
                    except ProcessLookupError:
                        pass
                    else:
                        raise ValueError('previous source still alive')
                self.tracker.unavailable()
                self.tracker = PermissionStatus()
                self.source, self.last_sequence = source, 0
            if value['sequence'] < self.last_sequence:
                raise ValueError('reordered source')
            # Validate every entry before filtering; catalog admission cannot hide
            # malformed or conflicting source state.
            check = PermissionStatus()
            all_sessions = set()
            for entry in value['pending']:
                if not isinstance(entry, dict):
                    raise ValueError('invalid pending entry')
                all_sessions.add(entry.get('session_id'))
            full = {key: value[key] for key in ('version', 'sequence', 'timestamp_ms', 'pending')}
            if not check.accept(full, all_sessions, wall_ms, now):
                raise ValueError('invalid complete set')
            owners = visible if isinstance(visible, dict) else {key: key for key in visible}
            admitted = [dict(x, session_id=owners[x['session_id']])
                        for x in value['pending'] if x['session_id'] in owners]
            filtered = {**full, 'pending': admitted}
            if value['sequence'] == self.last_sequence:
                # Do not renew the lease for a cached file. Re-evaluate catalog
                # removal conservatively instead of keeping an archived request.
                if self.tracker.pending != frozenset(tuple(x[k] for k in ('session_id','turn_id','request_id'))
                                                     for x in filtered['pending']):
                    raise ValueError('catalog changed before source refresh')
                return
            if not self.tracker.accept(filtered, set(owners.values()), wall_ms, now):
                raise ValueError('rejected permission snapshot')
            self.last_sequence = value['sequence']
        except (OSError, ValueError, TypeError, KeyError, RecursionError):
            self.tracker.unavailable()


    def poll_cohort(self, value, visible, wall_ms, now):
        retired = slot_state(value)
        if (set(value) != {'version', 'source_id', 'app_pid', 'app_birth', 'sequence', 'timestamp_ms', 'writers'} | ({'retired'} if retired is not None else set()) or
                type(value['version']) is not int or not hex_id(value['source_id']) or
                type(value['app_pid']) is not int or value['app_pid'] <= 1 or not hex_id(value['app_birth']) or
                type(value['sequence']) is not int or not 0 < value['sequence'] <= 0xffffffff or
                type(value['timestamp_ms']) is not int or not wall_ms - LEASE_MS < value['timestamp_ms'] <= wall_ms or
                not isinstance(value['writers'], list) or not 0 < len(value['writers']) <= MAX_WRITERS or visible is None):
            raise ValueError('invalid cohort envelope')
        identity = (value['source_id'], value['app_pid'], value['app_birth'])
        same = identity == self.cohort_identity
        if same and ((retired is None) != (self.cohort_retired is None) or
                     (retired is not None and any(a < b for a, b in zip(retired, self.cohort_retired)))):
            raise ValueError('registry version or retirement rollback')
        records, pids, pending, captures = {}, {value['app_pid']}, [], []
        writer_pids = set()
        for item in value['writers']:
            if (not isinstance(item, dict) or set(item) != WRITER_KEYS | ({'slot', 'generation'} if retired is not None else set()) or
                    not hex_id(item['source_id']) or item['source_id'] in records or
                    type(item['pid']) is not int or item['pid'] <= 1 or item['pid'] == value['app_pid'] or
                    item['pid'] in writer_pids or not hex_id(item['birth']) or
                    type(item['sequence']) is not int or not 0 < item['sequence'] <= 0xffffffff or
                    type(item['timestamp_ms']) is not int or not 0 <= item['timestamp_ms'] <= value['timestamp_ms'] or
                    type(item['available']) is not bool or type(item['closed']) is not bool or
                    not isinstance(item['pending'], list)):
                raise ValueError('invalid producer envelope')
            writer_pids.add(item['pid']);pids.add(item['pid'])
            if (type(item['child_pid']) is not int or item['child_pid'] <= 1 or
                    item['child_pid'] in (item['pid'], value['app_pid']) or not hex_id(item['child_birth'])):
                raise ValueError('producer not initialized')
            pids.add(item['child_pid'])
            records[item['source_id']] = item
            previous = self.cohort_records.get(item['source_id']) if identity == self.cohort_identity else None
            if previous and any(item[key] != previous[key] for key in
                                (('pid', 'birth', 'child_pid', 'child_birth', 'slot', 'generation')
                                 if retired is not None else ('pid', 'birth', 'child_pid', 'child_birth'))):
                raise ValueError('producer transport identity changed')
            if previous and (item['sequence'] < previous['sequence'] or item['timestamp_ms'] < previous['timestamp_ms'] or
                    ((item['sequence'] == previous['sequence'] or previous['closed']) and item != previous)):
                raise ValueError('producer replay or reopened close')
            if item['closed']:
                if item['available'] is not True or item['pending']:
                    raise ValueError('invalid producer retirement')
                continue
            if item['available'] is not True or not wall_ms - LEASE_MS < item['timestamp_ms'] <= wall_ms:
                raise ValueError('unavailable producer')
            check = PermissionStatus()
            sessions = {entry.get('session_id') for entry in item['pending'] if isinstance(entry, dict)}
            full = {'version': 1, 'sequence': item['sequence'], 'timestamp_ms': item['timestamp_ms'], 'pending': item['pending']}
            if not check.accept(full, sessions, wall_ms, now):
                raise ValueError('invalid producer complete set')
            for entry in item['pending']:
                key = hashlib.sha256((item['source_id'] + ':' + entry['request_id']).encode()).hexdigest()[:32]
                pending.append({**entry, 'request_id': key})
            captures.append(item['timestamp_ms'])
        removed = {key: item for key, item in self.cohort_records.items() if same and key not in records}
        for item in removed.values():
            if retired is None or retired[item['slot']] < item['generation']:
                raise ValueError('producer omitted without clean retirement')
            pids.update((item['pid'], item['child_pid']))
        cached, cached_pids, checked = self.process_cache
        if checked is None or not 0 <= now - checked < 250 or cached_pids != frozenset(pids):
            cached = births(pids)
            self.process_cache = (cached, frozenset(pids), now)
        if cached.get(value['app_pid']) != value['app_birth']:
            raise ValueError('desktop generation ended')
        for item in removed.values():
            if cached.get(item['pid']) == item['birth'] or cached.get(item['child_pid']) == item['child_birth']:
                raise ValueError('retired transport still alive')
        for item in records.values():
            if item['closed']:
                if cached.get(item['child_pid']) == item['child_birth']:
                    raise ValueError('retired child still alive')
            elif cached.get(item['pid']) != item['birth'] or cached.get(item['child_pid']) != item['child_birth']:
                raise ValueError('producer or child lost')
        if self.cohort_identity != identity:
            if self.cohort_identity:
                old = self.cohort_identity
                old_pids = {old[1], *(x['pid'] for x in self.cohort_records.values()),
                            *(x['child_pid'] for x in self.cohort_records.values())}
                old_live = births(old_pids)
                if old_live.get(old[1]) == old[2] or any(old_live.get(x['pid']) == x['birth'] or
                        old_live.get(x['child_pid']) == x['child_birth'] for x in self.cohort_records.values()):
                    raise ValueError('old cohort still alive')
            elif self.source is not None:
                try:
                    os.kill(self.source[1], 0)
                except ProcessLookupError:
                    pass
                else:
                    raise ValueError('old source still alive')
            self.tracker = PermissionStatus();self.last_sequence = 0
            self.cohort_identity = identity;self.source = identity[:2]
            self.cohort_records = {}
            self.cohort_retired = retired
        if not captures or len(pending) > 256:
            raise ValueError('no live complete producer set')
        if value['sequence'] < self.last_sequence:
            raise ValueError('reordered aggregate')
        if same and value['sequence'] == self.last_sequence and (records != self.cohort_records or retired != self.cohort_retired):
            raise ValueError('changed cached aggregate')
        check = PermissionStatus()
        complete = {'version': 1, 'sequence': value['sequence'], 'timestamp_ms': min(captures), 'pending': pending}
        if not check.accept(complete, {entry['session_id'] for entry in pending}, wall_ms, now):
            raise ValueError('invalid aggregate complete set')
        owners = visible if isinstance(visible, dict) else {key: key for key in visible}
        admitted = [dict(entry, session_id=owners[entry['session_id']]) for entry in pending if entry['session_id'] in owners]
        full = {'version': 1, 'sequence': value['sequence'], 'timestamp_ms': min(captures), 'pending': admitted}
        if value['sequence'] == self.last_sequence:
            if self.tracker.pending != frozenset(tuple(x[k] for k in ('session_id','turn_id','request_id')) for x in admitted):
                raise ValueError('cached aggregate changed')
            return
        if not self.tracker.accept(full, set(owners.values()), wall_ms, now):
            raise ValueError('aggregate projection rejected')
        self.last_sequence = value['sequence']
        self.cohort_records = records
        self.cohort_retired = retired
