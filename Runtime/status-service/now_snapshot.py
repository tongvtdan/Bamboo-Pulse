"""Ephemeral display metadata from the existing reducer; never feeds routing."""
import uuid
from model import TTL_MS, identifier


class NowSnapshot:
    def __init__(self):
        self.generation = uuid.uuid4().hex
        self.sequence = 0
        self.aliases = {}

    def capture(self, reducer, catalog, now, wall, status, activity, include_chat_links=False):
        visible = catalog.snapshot(now)
        sessions = {key[1]: value for key, value in reducer.sessions.items()
                    if not key[0] and visible is not None and key[1] in visible
                    and now < value['deadline']}
        tracker = reducer.permissions.tracker if reducer.permissions else None
        lease = max(0, tracker.deadline - now) if tracker and tracker.deadline is not None else 0
        pending = ({key[0] for key in tracker.pending} & set(visible or ())) if lease else set()
        ids = sorted(set(sessions) | pending)
        available = visible is not None and len(ids) <= 128 and len(set(self.aliases) | set(ids)) <= 4096
        if not available:
            ids = []
        names = catalog.names(now, ids)
        rows = []
        for key in ids:
            if key not in self.aliases:
                self.aliases[key] = f'CX{len(self.aliases) + 1}'
            item = sessions.get(key)
            state = item['event']['state'] if item else 'UNKNOWN'
            remaining = max(0, item['deadline'] - now) if item else 0
            age = TTL_MS - remaining if item else 0
            # A hook observes a request, not its complete pending lifetime.
            if state == 'NEEDS_ATTENTION':
                state = 'UNKNOWN'
            if key in pending:
                state, remaining, age = 'NEEDS_ATTENTION', lease, 5000 - lease
            rows.append(dict(id=key, alias=self.aliases[key], name=names.get(key), state=state,
                             age_ms=age, remaining_ms=remaining))
            if include_chat_links:
                # Reuse metadata already admitted by the catalog; no additional database read.
                raw_id = catalog.raw_ids.get(key)
                try:
                    canonical = isinstance(raw_id, str) and str(uuid.UUID(raw_id)) == raw_id
                except (ValueError, AttributeError):
                    canonical = False
                rows[-1]['thread_id'] = raw_id if canonical and identifier(raw_id) == key else None
        activity_ids = [key for key, item in sessions.items()
                        if key in ids and item['event']['event_id'] == activity['event_id']]
        status_ids = sorted(pending) if available and status['state'] == 'NEEDS_ATTENTION' else activity_ids
        self.sequence += 1
        return dict(version=2 if include_chat_links else 1, generation=self.generation, sequence=self.sequence,
                    timestamp_ms=wall, valid_for_ms=2500, monitoring_available=available,
                    sessions=rows, activity_event_id=activity['event_id'],
                    status_event_id=status['event_id'], activity_contributors=activity_ids,
                    status_contributors=status_ids)
