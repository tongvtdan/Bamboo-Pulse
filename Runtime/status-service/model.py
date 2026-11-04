"""Metadata-only normalization and fresh, per-session status aggregation."""
import hashlib
import time
import uuid
from collections import OrderedDict

SOURCES = ('Unknown', 'SessionStart', 'UserPromptSubmit', 'PreToolUse',
           'PermissionRequest', 'PostToolUse', 'Stop', 'Synthetic')
STATES = ('UNKNOWN', 'WORKING', 'NEEDS_ATTENTION', 'TURN_ENDED', 'ERROR', 'DISCONNECTED')
MAPPING = {'SessionStart': 'UNKNOWN', 'UserPromptSubmit': 'WORKING',
           'PreToolUse': 'WORKING', 'PermissionRequest': 'NEEDS_ATTENTION',
           'PostToolUse': 'WORKING', 'Stop': 'TURN_ENDED'}
PRIORITY = {'UNKNOWN': 0, 'TURN_ENDED': 1, 'WORKING': 2, 'ERROR': 3, 'NEEDS_ATTENTION': 4}
TTL_MS = 120_000
MAX_EVENT = 2048
# Preserve the feed schema: an interrupt ends the turn without implying success.
HOOK_SOURCES = {source: source for source in MAPPING} | {'Interrupt': 'Stop'}


def identifier(value):
    # Even a malicious or accidental prompt used as an ID never leaves this adapter.
    if not isinstance(value, str) or not value or len(value) > 256:
        return None
    return hashlib.sha256(value.encode()).hexdigest()[:32]


def normalize(payload, source, now=None):
    if not isinstance(payload, dict) or source not in HOOK_SOURCES:
        return None
    if payload.get('hook_event_name', source) != source:
        return None
    session = identifier(payload.get('session_id'))
    if not session:
        return None
    turn = identifier(payload.get('turn_id'))
    if source == 'Interrupt' and turn is None:
        return None
    tool = None if source == 'Interrupt' else identifier(payload.get('tool_use_id'))
    event_id = (hashlib.sha256(f'{session}:{turn}:{source}:{tool}'.encode()).hexdigest()[:32]
                if tool or (turn and source in ('UserPromptSubmit', 'Stop', 'Interrupt')) else uuid.uuid4().hex)
    return {'version': 1, 'provider': 'codex', 'session_id': session, 'turn_id': turn,
            'event_id': event_id, 'source': HOOK_SOURCES[source], 'state': MAPPING[HOOK_SOURCES[source]],
            'timestamp_ms': int(time.time() * 1000) if now is None else now,
            'freshness_ms': TTL_MS, 'synthetic': False}


def valid_event(event, wall_ms):
    keys = {'version', 'provider', 'session_id', 'turn_id', 'event_id', 'source',
            'state', 'timestamp_ms', 'freshness_ms', 'synthetic'}
    if not isinstance(event, dict) or set(event) != keys:
        return False
    def hex_id(value):
        return isinstance(value, str) and len(value) == 32 and all(c in '0123456789abcdef' for c in value)
    return (type(event['version']) is int and event['version'] == 1 and event['provider'] == 'codex'
            and hex_id(event['session_id']) and hex_id(event['event_id'])
            and (event['turn_id'] is None or hex_id(event['turn_id']))
            and type(event['synthetic']) is bool
            and ((event['synthetic'] and event['source'] == 'Synthetic' and event['state'] in STATES)
                 or (not event['synthetic'] and event['source'] in MAPPING
                     and event['state'] == MAPPING[event['source']]))
            and type(event['timestamp_ms']) is int and wall_ms - TTL_MS <= event['timestamp_ms'] <= wall_ms + 1000
            and type(event['freshness_ms']) is int and event['freshness_ms'] == TTL_MS)


class Reducer:
    def __init__(self, permissions=None):
        self.sessions = OrderedDict()
        self.seen = OrderedDict()
        self.count = 0
        self.coverage = {source: 0 for source in MAPPING}
        self.last_now = None
        # Opt in only when a supported owner-runtime adapter provides complete
        # pending-request snapshots. Legacy hooks alone cannot resolve requests.
        self.permissions = permissions

    def accept(self, event, wall_ms, monotonic_ms):
        if not valid_event(event, wall_ms):
            return False
        if not event['synthetic']:
            self.coverage[event['source']] += 1
        if event['event_id'] in self.seen:
            return False
        key = (event['synthetic'], event['session_id'])
        old = self.sessions.get(key)
        if old:
            previous = old['event']
            if event['timestamp_ms'] < previous['timestamp_ms']:
                return False
            if event['turn_id'] and event['turn_id'] != old['turn']:
                if event['turn_id'] in old['retired']:
                    return False
                if old['turn'] and event['source'] not in ('UserPromptSubmit', 'Synthetic'):
                    return False
            # Late tool completions cannot undo a recorded end of the same turn.
            if (previous['state'] == 'TURN_ENDED' and event['turn_id'] in (None, old['turn'])
                    and event['source'] in ('PreToolUse', 'PostToolUse', 'PermissionRequest')):
                return False
        retired = list(old['retired']) if old else []
        if old and old['turn'] and event['turn_id'] and event['turn_id'] != old['turn']:
            retired = (retired + [old['turn']])[-32:]
        # Preserve elapsed delivery age; socket receipt must not rejuvenate an old event.
        remaining = TTL_MS - max(0, wall_ms - event['timestamp_ms'])
        if self.permissions is None or event['source'] != 'PermissionRequest':
            self.sessions[key] = {'event': dict(event), 'receipt': monotonic_ms,
                                  'deadline': monotonic_ms + remaining, 'retired': retired,
                                  'turn': event['turn_id'] or (old['turn'] if old else None)}
            self.sessions.move_to_end(key)
            if len(self.sessions) > 128:
                self.sessions.popitem(last=False)
        self.seen[event['event_id']] = True
        if len(self.seen) > 4096:
            self.seen.popitem(last=False)
        self.count += 1
        return True

    def activity_snapshot(self, now, wall_ms=None):
        """Observed activity only; never declares permission coverage or resolution."""
        if self.last_now is not None and now < self.last_now:
            for session in self.sessions.values():
                session['deadline'] = min(session['deadline'], now)
        self.last_now = now
        if wall_ms is not None:
            # macOS monotonic time can stop during sleep. Bound by the original
            # event's wall deadline too, and retain the smaller deadline so later
            # wall-clock rollback cannot rejuvenate an expired event.
            for session in self.sessions.values():
                timestamp = session['event']['timestamp_ms']
                remaining = (max(0, TTL_MS - max(0, wall_ms - timestamp))
                             if timestamp <= wall_ms + 1000 else 0)
                session['deadline'] = min(session['deadline'], now + remaining)
        fresh = [s for s in self.sessions.values() if now < s['deadline']]
        # Live and synthetic runs cannot compete on the physical indicator.
        live = [s for s in fresh if not s['event']['synthetic']]
        fresh = live or fresh
        if not fresh:
            view = {'state': 'UNKNOWN', 'sessions': 0, 'events': self.count, 'age_ms': 0,
                    'remaining_ms': 0, 'source': 'Unknown', 'synthetic': False, 'event_id': None}
        else:
            winner = max(fresh, key=lambda s: (PRIORITY.get(s['event']['state'], 0),
                                              s['event']['timestamp_ms'], s['receipt']))
            e = winner['event']
            remaining = max(0, winner['deadline'] - now)
            view = {'state': e['state'], 'sessions': len(fresh), 'events': self.count,
                    'age_ms': TTL_MS - remaining, 'remaining_ms': remaining,
                    'source': e['source'], 'synthetic': e['synthetic'], 'event_id': e['event_id']}
        return view

    def snapshot(self, now, wall_ms=None):
        view = self.activity_snapshot(now, wall_ms)
        if self.permissions is not None:
            active = {s['event']['session_id'] for s in self.sessions.values()
                      if now < s['deadline'] and not s['event']['synthetic']}
            return self.permissions.project(view, now, wall_ms, active)
        return view
