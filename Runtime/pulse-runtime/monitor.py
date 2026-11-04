"""Pulse-only read-only feed. No device, execution, or approval methods."""
import fcntl
import json
import os
from pathlib import Path
import selectors
import signal
import socket
import stat
import time
import uuid

from model import MAX_EVENT, Reducer, valid_event
from now_snapshot import NowSnapshot
from permission_source import PermissionSource
from session_catalog import SessionCatalog


def private_directory(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('UNSAFE_DIRECTORY')


class Monitor:
    def __init__(self, home):
        self.catalog = SessionCatalog(home / '.codex/state_5.sqlite')
        self.permissions = PermissionSource(home / 'Library/Application Support/BambooPulse/Observer/desktop.json')
        self.reducer = Reducer(permissions=self.permissions)
        self.snapshot = NowSnapshot()
        self.generation = uuid.uuid4().hex
        self.sequence = 0

    def refresh(self):
        now = int(time.monotonic() * 1000)
        wall = int(time.time() * 1000)
        visible = self.catalog.snapshot(now)
        for key in list(self.reducer.sessions):
            if visible is None or key[1] not in visible:
                del self.reducer.sessions[key]
        self.permissions.poll(self.catalog.permission_owners(now), wall, now)
        value = self.snapshot.capture(self.reducer, self.catalog, now, wall,
                                      self.reducer.snapshot(now, wall),
                                      self.reducer.activity_snapshot(now, wall), include_chat_links=True)
        deadline = self.permissions.tracker.deadline
        value['monitoring_available'] = value['monitoring_available'] and deadline is not None and now < deadline
        if not value['monitoring_available']:
            value['sessions'] = []
        return value

    def event(self, raw):
        if len(raw) > MAX_EVENT:
            return
        try:
            event = json.loads(raw)
            now, wall = int(time.monotonic() * 1000), int(time.time() * 1000)
            visible = self.catalog.snapshot(now, force=True)
            if (valid_event(event, wall) and not event['synthetic']
                    and visible is not None and event['session_id'] in visible):
                self.reducer.accept(event, wall, now)
        except (ValueError, TypeError, KeyError, RecursionError):
            pass

    def respond(self, request):
        if (not isinstance(request, dict) or set(request) != {'id', 'method', 'params'}
                or not isinstance(request['id'], str) or not 0 < len(request['id']) <= 128):
            raise ValueError('INVALID_REQUEST')
        value = self.refresh()
        if request['method'] == 'getActivityNow' and request['params'] == {}:
            self.sequence += 1
            rows = [{k: v for k, v in row.items() if k != 'thread_id'} for row in value['sessions']]
            result = dict(version=1, generation=self.generation, sequence=self.sequence,
                          timestamp_ms=value['timestamp_ms'], valid_for_ms=value['valid_for_ms'],
                          monitoring_available=value['monitoring_available'], sessions=rows, bar=None)
        elif (request['method'] == 'getActivityChatLink' and isinstance(request['params'], dict)
              and set(request['params']) == {'session_id'}
              and isinstance(request['params']['session_id'], str)):
            selected = request['params']['session_id']
            row = next((r for r in value['sessions'] if r['id'] == selected and r['remaining_ms'] > 0), None)
            result = dict(version=1, session_id=selected, thread_id=row['thread_id'] if row else None)
        else:
            raise ValueError('UNSUPPORTED_METHOD')
        return json.dumps({'id': request['id'], 'result': result}, separators=(',', ':')).encode() + b'\n'


def run(home=None, endpoint=None, events=None):
    home = Path.home() if home is None else Path(home)
    endpoint = Path(endpoint or f'/tmp/bamboo-pulse-{os.getuid()}/feed.sock')
    events = Path(events or home / '.local/state/bamboox-status/events.sock')
    private_directory(endpoint.parent)
    private_directory(events.parent)
    monitor = Monitor(home)
    lock = os.open(events.parent / 'service.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    sockets, paths = [], []
    clients = {}
    parent = os.getppid()
    def stop(*_):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        lock_info = os.fstat(lock)
        if not stat.S_ISREG(lock_info.st_mode) or lock_info.st_uid != os.getuid() or lock_info.st_mode & 0o077:
            raise ValueError('UNSAFE_LOCK')
        raw = os.pread(lock, 4096, 0)
        previous = json.loads(raw) if raw else {}
        with selectors.DefaultSelector() as selector:
            for path, kind in ((endpoint, socket.SOCK_STREAM), (events, socket.SOCK_DGRAM)):
                # Never remove another process's endpoint, including stale/unknown sockets.
                if os.path.lexists(path):
                    info = path.lstat()
                    if (not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid()
                            or previous.get(str(path)) != [info.st_dev, info.st_ino]):
                        raise ValueError('ENDPOINT_CONFLICT')
                    path.unlink()
                fd = socket.socket(socket.AF_UNIX, kind)
                sockets.append(fd)
                fd.bind(str(path))
                paths.append((path, path.lstat().st_ino))
                info = path.lstat()
                previous[str(path)] = [info.st_dev, info.st_ino]
                record = json.dumps(previous).encode()
                os.pwrite(lock, record, 0)
                os.ftruncate(lock, len(record))
                os.fsync(lock)
                os.chmod(path, 0o600)
                if kind == socket.SOCK_STREAM:
                    fd.listen(8)
                fd.setblocking(False)
                selector.register(fd, selectors.EVENT_READ)
            server, receiver = sockets
            while os.getppid() == parent:
                for key, _ in selector.select(.1):
                    fd = key.fileobj
                    if fd is receiver:
                        for _ in range(64):
                            try:
                                monitor.event(receiver.recv(MAX_EVENT + 1))
                            except BlockingIOError:
                                break
                    elif fd is server:
                        client, _ = server.accept()
                        client.setblocking(False)
                        if len(clients) >= 16:
                            client.close()
                            continue
                        clients[client] = (bytearray(), time.monotonic() + 2)
                        selector.register(client, selectors.EVENT_READ)
                    else:
                        raw, _ = clients[fd]
                        try:
                            chunk = fd.recv(4096)
                            raw.extend(chunk)
                            if not chunk or len(raw) > 4096:
                                raise ValueError('FRAME_BOUNDS')
                            if b'\n' in raw:
                                if not raw.endswith(b'\n') or raw.count(b'\n') != 1:
                                    raise ValueError('FRAME_INVALID')
                                response = monitor.respond(json.loads(raw))
                                fd.settimeout(.2)
                                fd.sendall(response)
                                raise ValueError('COMPLETE')
                        except (OSError, ValueError, TypeError, KeyError, RecursionError):
                            selector.unregister(fd)
                            fd.close()
                            del clients[fd]
                for fd, (_, deadline) in list(clients.items()):
                    if time.monotonic() >= deadline:
                        selector.unregister(fd)
                        fd.close()
                        del clients[fd]
    except KeyboardInterrupt:
        pass
    finally:
        for fd in [*clients, *sockets]:
            fd.close()
        for path, inode in paths:
            if path.exists() and path.lstat().st_ino == inode:
                path.unlink()
        os.close(lock)
