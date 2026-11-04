"""Bounded, metadata-only sidecar diagnostics; never permission evidence."""
import fcntl
import os
import stat
import threading
import time
from desktop_cohort import private_read, private_write
from permission_status import hex_id

# Only fixed local classifications may cross the diagnostic boundary.
SCHEMA_REASONS = {
    'non-object RPC': 'RPC_NOT_OBJECT',
    'invalid approval': 'APPROVAL_INVALID',
    'missing approval identity': 'APPROVAL_IDENTITY_MISSING',
    'ambiguous approval identity': 'APPROVAL_IDENTITY_CONFLICT',
    'unsupported approval schema': 'APPROVAL_SCHEMA_UNSUPPORTED',
    'invalid resolution': 'RESOLUTION_INVALID',
    'resolution identity mismatch': 'RESOLUTION_IDENTITY_MISMATCH',
    'too many approvals': 'REQUEST_LIMIT',
    'too many attention requests': 'REQUEST_LIMIT',
    'too many async questions': 'REQUEST_LIMIT',
    'question lifecycle history exceeded': 'QUESTION_HISTORY_LIMIT',
    'invalid question reply RPC identity': 'QUESTION_REPLY_IDENTITY_INVALID',
    'conflicting reply RPC identity': 'QUESTION_REPLY_IDENTITY_CONFLICT',
    'too many unanswered reply RPCs': 'QUESTION_REPLY_LIMIT',
    'question reply acknowledgement mismatch': 'QUESTION_REPLY_ACK_MISMATCH',
    'invalid question lifecycle event': 'QUESTION_LIFECYCLE_INVALID',
    'missing interrupted turn identity': 'QUESTION_INTERRUPT_IDENTITY_MISSING',
    'invalid async question metadata': 'QUESTION_METADATA_INVALID',
    'conflicting async question identity': 'QUESTION_IDENTITY_CONFLICT',
    'missing accepted reply thread': 'QUESTION_REPLY_THREAD_MISSING',
}
REASONS = frozenset(SCHEMA_REASONS.values()) | frozenset((
    'AVAILABLE', 'PARTIAL_FRAME', 'OBSERVATION_BACKLOG', 'INVALID_JSON', 'INVALID_METADATA', 'FRAME_LIMIT',
    'QUEUE_OVERFLOW', 'TRANSPORT_IO_ERROR', 'TRANSPORT_EOF', 'TRANSPORT_LOST',
    'SOURCE_CONFLICT', 'SNAPSHOT_BUSY', 'SNAPSHOT_WRITE_FAILED', 'REGISTRATION_FAILED',
    'CHILD_ATTACH_FAILED', 'OBSERVER_STOPPED', 'INTERNAL_OBSERVATION_ERROR',
    'STARTUP_INCOMPLETE_CAPTURE', 'STARTUP_CONTEXT_MISMATCH', 'STARTUP_CLI_CHANGED',
    'STARTUP_UNAVAILABLE'))
SIDES = frozenset(('client', 'server', 'both', 'none'))


class FailureSignal(threading.Event):
    """Forwarding threads record only the first failure, without disk I/O."""
    def __init__(self):
        super().__init__()
        self.failure = None
        self.failure_lock = threading.Lock()

    def fail(self, reason, side):
        with self.failure_lock:
            if self.failure is None:
                self.failure = (reason, side)
            self.set()


def signal_failure(event, reason, side):
    if isinstance(event, FailureSignal):
        event.fail(reason, side)
    else:
        event.set()


class Diagnostics:
    """Independent, best-effort sidecar; never used for permission admission."""
    def __init__(self, source, source_id):
        self.path = source.with_name(source.name + '.diagnostics.json')
        self.source_id = source_id
        self.first_failure = None
        self.last = None

    @staticmethod
    def valid_failure(value):
        return (isinstance(value, dict) and set(value) == {'reason', 'side', 'timestamp_ms'}
                and isinstance(value['reason'], str) and value['reason'] in REASONS
                and isinstance(value['side'], str) and value['side'] in SIDES
                and type(value['timestamp_ms']) is int and value['timestamp_ms'] >= 0)

    @classmethod
    def valid_record(cls, value):
        return (isinstance(value, dict) and set(value) == {'source_id', 'reason', 'side',
                    'latched', 'timestamp_ms', 'sequence', 'first_failure'}
                and hex_id(value['source_id']) and type(value['latched']) is bool
                and type(value['sequence']) is int and 0 <= value['sequence'] <= 0xffffffff
                and cls.valid_failure({k: value[k] for k in ('reason', 'side', 'timestamp_ms')})
                and (value['first_failure'] is None or cls.valid_failure(value['first_failure'])))

    def record(self, reason, side='none', latched=False, sequence=0):
        reason = reason if reason in REASONS else 'INTERNAL_OBSERVATION_ERROR'
        side = side if side in SIDES else 'none'
        signature = (reason, side, latched)
        if signature == self.last:
            return
        now = int(time.time() * 1000)
        if latched and self.first_failure is None:
            self.first_failure = {'reason': reason, 'side': side, 'timestamp_ms': now}
        value = {'source_id': self.source_id, 'reason': reason, 'side': side,
                 'latched': latched, 'timestamp_ms': now, 'sequence': sequence,
                 'first_failure': self.first_failure}
        lock = None
        try:
            directory = self.path.parent.lstat()
            if (not stat.S_ISDIR(directory.st_mode) or directory.st_uid != os.getuid()
                    or stat.S_IMODE(directory.st_mode) != 0o700 or not self.valid_record(value)):
                return
            lock = os.open(self.path.with_suffix('.lock'),
                           os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
            info = os.fstat(lock)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or stat.S_IMODE(info.st_mode) != 0o600):
                return
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            try:
                previous = private_read(self.path)
            except FileNotFoundError:
                previous = {'version': 1, 'producers': []}
            if (not isinstance(previous, dict) or set(previous) != {'version', 'producers'}
                    or type(previous['version']) is not int or previous['version'] != 1
                    or not isinstance(previous['producers'], list) or len(previous['producers']) > 32
                    or any(not self.valid_record(item) for item in previous['producers'])):
                return
            records = [item for item in previous['producers'] if item['source_id'] != self.source_id]
            # One fixed file, at most 32 producer records; never append RPC/event logs.
            private_write(self.path, {'version': 1, 'producers': [*records[-31:], value]})
            self.last = signature
        except (OSError, ValueError, TypeError, RecursionError):
            pass
        finally:
            if lock is not None:
                os.close(lock)
