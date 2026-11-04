"""Read-only admission for supported, persisted Codex desktop chats; no content."""
import os
import sqlite3
import stat
import unicodedata
from contextlib import closing
from pathlib import Path
from model import identifier

# Pinned to the installed Codex metadata schema. Unsupported schemas fail closed.
VISIBLE_TYPES = ('user', 'agent_created_thread', 'automation', 'chatgpt_handoff', 'realtime_voice')
MAX_CHATS = 4096


def catalog_path():
    return Path(os.environ.get('CODEX_HOME', Path.home() / '.codex')) / 'state_5.sqlite'


class SessionCatalog:
    def __init__(self, path=None):
        self.path = Path(path or catalog_path()).expanduser().absolute()
        self.checked_at = None
        self.visible = None
        self.raw_ids = {}
        self.owners_checked_at = None
        self.owners = None

    def snapshot(self, now, force=False):
        if not force and self.checked_at is not None and 0 <= now - self.checked_at < 1000:
            return self.visible
        self.checked_at = now
        self.visible = None
        self.raw_ids = {}
        try:
            info = self.path.lstat()
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
                return None
            with closing(sqlite3.connect(self.path.as_uri() + '?mode=ro', uri=True, timeout=.01)) as db:
                db.execute('PRAGMA query_only=ON')
                types = ','.join('?' for _ in VISIBLE_TYPES)
                # Admission reads IDs only; display names are a separate bounded lookup.
                rows = db.execute(
                    'SELECT id FROM threads WHERE source=? AND archived=0 '
                    'AND agent_role IS NULL AND agent_path IS NULL '
                    f'AND (thread_source IS NULL OR thread_source IN ({types})) LIMIT ?',
                    ('vscode', *VISIBLE_TYPES, MAX_CHATS + 1)).fetchall()
            if len(rows) > MAX_CHATS or any(identifier(row[0]) is None for row in rows):
                return None
            self.visible = frozenset(identifier(row[0]) for row in rows)
            self.raw_ids = {identifier(row[0]): row[0] for row in rows}
        except (OSError, sqlite3.Error, ValueError):
            pass
        return self.visible

    def names(self, now, wanted):
        """Names for observed visible chats only. Failure never changes admission."""
        if self.snapshot(now) is None or len(wanted) > 128:
            return {}
        ids = [self.raw_ids[key] for key in wanted if key in self.raw_ids]
        if not ids:
            return {}
        try:
            with closing(sqlite3.connect(self.path.as_uri() + '?mode=ro', uri=True, timeout=.01)) as db:
                db.execute('PRAGMA query_only=ON')
                columns = {row[1] for row in db.execute('PRAGMA table_info(threads)')}
                expression = "COALESCE(NULLIF(name,''),title)" if 'name' in columns else 'title'
                rows = db.execute(f'SELECT id, substr({expression},1,160) FROM threads WHERE id IN (' +
                                  ','.join('?' for _ in ids) + ') AND archived=0', ids).fetchall()
            result = {}
            for raw_id, name in rows:
                if isinstance(name, str):
                    name = ''.join(c for c in name if not unicodedata.category(c).startswith('C')).strip()
                    name = name.encode('utf-8')[:160].decode('utf-8', errors='ignore')
                    if name:
                        result[identifier(raw_id)] = name
            return result
        except (OSError, sqlite3.Error, ValueError):
            return {}

    def permission_owners(self, now):
        """Map visible chats and their recorded subagents to the visible ancestor."""
        visible = self.snapshot(now)
        if visible is None:
            self.owners = None
            return None
        if (self.owners_checked_at is not None and 0 <= now - self.owners_checked_at < 1000
                and self.owners is not None and set(self.owners.values()) == set(visible)):
            return self.owners
        self.owners_checked_at, self.owners = now, None
        try:
            with closing(sqlite3.connect(self.path.as_uri() + '?mode=ro', uri=True, timeout=.01)) as db:
                db.execute('PRAGMA query_only=ON')
                rows = db.execute('SELECT parent_thread_id, child_thread_id FROM thread_spawn_edges LIMIT ?',
                                  (MAX_CHATS + 1,)).fetchall()
            if len(rows) > MAX_CHATS:
                return None
            parents = {}
            for parent, child in rows:
                parent, child = identifier(parent), identifier(child)
                if not parent or not child or child in parents:
                    return None
                parents[child] = parent
            owners = {key: key for key in visible}
            for child in parents:
                node, seen = child, set()
                while node not in visible and node in parents:
                    if node in seen:
                        return None
                    seen.add(node)
                    node = parents[node]
                if node in visible:
                    owners[child] = node
            self.owners = owners
        except (OSError, sqlite3.Error, ValueError):
            pass
        return self.owners
