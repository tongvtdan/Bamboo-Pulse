"""Nonapproving projection of complete, authoritative pending-request snapshots.

No hook or IPC producer is installed here. The owner runtime adapter must supply
the complete pending set with stable, pseudonymous request/session/turn IDs.
"""
import hashlib

LEASE_MS = 5000
MAX_REQUESTS = 256
MAX_SESSIONS = 128
MAX_SEQUENCE = 0xffffffff


def hex_id(value):
    return isinstance(value, str) and len(value) == 32 and all(c in '0123456789abcdef' for c in value)


class PermissionStatus:
    def __init__(self):
        self.sequence = 0
        self.pending = frozenset()
        self.deadline = None
        self.timestamp = None
        self.last_now = None
        self.event_id = None

    def unavailable(self):
        # Loss is unknown, never an inferred approval or resolution. Retain the
        # sequence floor so delayed snapshots cannot restore old knowledge.
        self.pending = frozenset()
        self.deadline = None
        self.timestamp = None
        self.event_id = None

    def accept(self, snapshot, visible, wall_ms, now):
        if visible is None:
            self.unavailable()
            return False
        if (not isinstance(snapshot, dict) or
                set(snapshot) != {'version', 'sequence', 'timestamp_ms', 'pending'} or
                type(snapshot['version']) is not int or snapshot['version'] != 1 or
                type(snapshot['sequence']) is not int or
                not self.sequence < snapshot['sequence'] <= MAX_SEQUENCE or
                type(snapshot['timestamp_ms']) is not int or
                not wall_ms - LEASE_MS < snapshot['timestamp_ms'] <= wall_ms or
                not isinstance(snapshot['pending'], list) or len(snapshot['pending']) > MAX_REQUESTS):
            return False
        pending = set()
        for request in snapshot['pending']:
            if (not isinstance(request, dict) or
                    set(request) != {'session_id', 'turn_id', 'request_id'} or
                    not hex_id(request['session_id']) or not hex_id(request['request_id']) or
                    (request['turn_id'] is not None and not hex_id(request['turn_id'])) or
                    request['session_id'] not in visible):
                return False
            key = (request['session_id'], request['turn_id'], request['request_id'])
            if key in pending:
                return False
            pending.add(key)
        if len({key[0] for key in pending}) > MAX_SESSIONS:
            return False
        if self.last_now is not None and now < self.last_now:
            self.unavailable()
            return False
        self.pending = frozenset(pending)
        self.sequence = snapshot['sequence']
        self.timestamp = snapshot['timestamp_ms']
        self.deadline = now + LEASE_MS - (wall_ms - self.timestamp)
        self.last_now = now
        self.event_id = hashlib.sha256(
            f'permission-snapshot:{self.sequence}:{self.timestamp}'.encode()).hexdigest()[:32]
        return True

    def project(self, activity, now, wall_ms, active_sessions):
        if self.last_now is not None and now < self.last_now:
            self.unavailable()
        self.last_now = now
        if self.deadline is not None and wall_ms is not None:
            # Wall time also bounds freshness during macOS sleep. A later clock
            # rollback cannot rejuvenate knowledge already declared unavailable.
            if wall_ms < self.timestamp:
                self.unavailable()
            else:
                self.deadline = min(self.deadline, now + max(0, LEASE_MS - (wall_ms - self.timestamp)))
        if self.deadline is None or now >= self.deadline:
            self.unavailable()
            return {'state': 'UNKNOWN', 'sessions': 0, 'events': activity['events'],
                    'age_ms': 0, 'remaining_ms': 0, 'source': 'Unknown',
                    'synthetic': False, 'event_id': None}
        if not self.pending:
            if not activity['remaining_ms']:
                return activity
            # A cached working/ended cue must not outlive our knowledge that
            # permissions are clear. New source snapshots also renew its key so
            # downstream event deduplication cannot suppress this shorter lease.
            return {**activity, 'remaining_ms': min(activity['remaining_ms'], self.deadline - now),
                    'event_id': hashlib.sha256(
                        f'{activity["event_id"]}:{self.event_id}'.encode()).hexdigest()[:32]}
        sessions = set(active_sessions) | {key[0] for key in self.pending}
        if len(sessions) > MAX_SESSIONS:
            self.unavailable()
            return self.project(activity, now, wall_ms, ())
        remaining = self.deadline - now
        return {'state': 'NEEDS_ATTENTION', 'sessions': len(sessions), 'events': activity['events'],
                'age_ms': LEASE_MS - remaining, 'remaining_ms': remaining,
                'source': 'PermissionRequest', 'synthetic': False, 'event_id': self.event_id}
