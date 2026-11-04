#!/usr/bin/env python3
"""Best-effort observer: no policy decisions, stdout, or serial-port access."""
import fcntl
import json
import os
import select
import socket
import stat
import sys
import time
from pathlib import Path
from model import MAX_EVENT, normalize


def socket_path():
    env_sock = os.environ.get('BAMBOOX_STATUS_SOCKET')
    return Path(env_sock if env_sock else str(Path.home() / '.local/state/bamboox-status/events.sock'))


def publish(event, path=None):
    if event is None:
        return False
    data = json.dumps(event, separators=(',', ':')).encode()
    if len(data) > MAX_EVENT:
        return False
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as client:
            client.setblocking(False)
            client.sendto(data, str(path or socket_path()))
        return True
    except (OSError, ValueError):
        return False


def diagnostic(source, outcome, timestamp_ms=None):
    # Temporary opt-in metadata only. Never log input, IDs, errors or content.
    root = Path.home() / '.local/state/bamboox-status'
    try:
        marker = root / 'hook-diagnostics.enabled'
        m = marker.lstat()
        if not stat.S_ISREG(m.st_mode) or m.st_uid != os.getuid() or m.st_mode & 0o077:
            return
        if source not in ('SessionStart', 'UserPromptSubmit', 'PreToolUse',
                          'PermissionRequest', 'PostToolUse', 'Stop', 'Interrupt'):
            source = 'Unknown'
        allowed = {'started', 'stdin_timeout', 'input_too_large', 'invalid_input',
                   'normalization_rejected', 'delivered', 'delivery_failed'}
        if outcome not in allowed:
            return
        record = (json.dumps({'timestamp_ms': int(time.time() * 1000) if timestamp_ms is None else timestamp_ms,
                              'hook': source, 'outcome': outcome}) + '\n').encode()
        fd = os.open(root / 'hook-diagnostics.jsonl',
                     os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                return
            # Never wait for another producer; the complete record must fit under its lock.
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if os.fstat(fd).st_size + len(record) <= 1024 * 1024:
                os.write(fd, record)
        finally:
            os.close(fd)
    except (OSError, ValueError):
        pass


def main():
    # Bound stdin too: a broken producer must not hold the agent indefinitely.
    source = sys.argv[1] if len(sys.argv) == 2 else ''
    started_ms = int(time.time() * 1000)
    outcome = 'stdin_timeout'
    deadline = time.monotonic() + .060
    raw = bytearray()
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([sys.stdin.fileno()], [], [], max(0, deadline - time.monotonic()))
            if not ready:
                return
            chunk = os.read(sys.stdin.fileno(), min(8192, 65537 - len(raw)))
            if not chunk:
                event = normalize(json.loads(raw), source)
                outcome = ('normalization_rejected' if event is None else
                           'delivered' if publish(event) else 'delivery_failed')
                return
            raw.extend(chunk)
            if len(raw) > 65536:
                outcome = 'input_too_large'
                return
    except (OSError, ValueError, TypeError, RecursionError):
        outcome = 'invalid_input'
    finally:
        # Delivery/input handling finishes before optional diagnostic filesystem I/O.
        diagnostic(source, 'started', timestamp_ms=started_ms)
        diagnostic(source, outcome)


if __name__ == '__main__':
    main()
