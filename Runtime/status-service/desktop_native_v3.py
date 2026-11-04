#!/usr/bin/env python3
"""Opt-in desktop stdio observer. Never produces or changes an RPC decision."""
import json
import hashlib
import fcntl
import os
from pathlib import Path
import queue
import select
import signal
import stat
import subprocess
import sys
import threading
import time
import uuid
from model import identifier
from async_questions import AsyncQuestions
from desktop_cohort import CohortWriter, birth, private_write
from permission_status import MAX_REQUESTS
from desktop_json_stream import JsonFrames, FrameError
from desktop_diagnostics import Diagnostics, FailureSignal, SCHEMA_REASONS, signal_failure

REAL_CLI = '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'
APPROVALS = frozenset(('item/commandExecution/requestApproval',
                      'item/fileChange/requestApproval', 'item/permissions/requestApproval'))
INTERACTIVE = frozenset(('item/tool/requestUserInput', 'tool/requestUserInput', 'mcpServer/elicitation/request'))
MAX_LINE = 8 * 1024 * 1024
MAX_FILE = 65536
QUEUE_WAIT = .25  # Bounded backpressure; actual timeout still latches UNKNOWN.


def rpc_id(value):
    return ((type(value) is int and -(2**63) <= value < 2**63) or
            (isinstance(value, str) and 0 < len(value) <= 256))


class Pending:
    def __init__(self):
        self.pending = {}
        self.buffer = JsonFrames(MAX_LINE)
        self.client_buffer = JsonFrames(MAX_LINE)
        self.questions = AsyncQuestions()
        self.available = True
        self.failure = None

    def fail(self, reason, side='none'):
        if self.failure is None:
            self.failure = (reason, side)
        self.available = False

    def feed(self, chunk, client=False):
        if not self.available:
            return
        buffer = self.client_buffer if client else self.buffer
        side = 'client' if client else 'server'
        try:
            for message in buffer.feed(chunk):
                if client:
                    self.questions.client(message)
                else:
                    self.observe(message)
                if len(self.pending) + len(self.questions.pending) > MAX_REQUESTS:
                    raise ValueError('too many attention requests')
        except FrameError as error:
            self.fail(error.reason, side)
        except (ValueError, TypeError, KeyError, RecursionError, UnicodeError) as error:
            key = error.args[0] if error.args and isinstance(error.args[0], str) else None
            self.fail(SCHEMA_REASONS.get(key, 'INVALID_METADATA'), side)
        if not self.available:
            self.buffer.clear()
            self.client_buffer.clear()
            self.pending.clear()
            self.questions.pending.clear()
            self.questions.clients.clear()

    def entries(self):
        return [*self.pending.values(), *self.questions.pending.values()]

    def observe(self, message):
        if not isinstance(message, dict):
            raise ValueError('non-object RPC')
        self.questions.server(message)
        method = message.get('method')
        if not isinstance(method, str):
            return
        params = message.get('params')
        if 'id' in message and method in APPROVALS | INTERACTIVE:
            if not rpc_id(message['id']) or not isinstance(params, dict):
                raise ValueError('invalid approval')
            session, turn = identifier(params.get('threadId')), identifier(params.get('turnId'))
            if not session or (not turn and not (method == 'mcpServer/elicitation/request' and params.get('turnId') is None)):
                raise ValueError('missing approval identity')
            key = json.dumps(message['id'], separators=(',', ':'))
            value = {'session_id': session, 'turn_id': turn, 'request_id': hashlib.sha256(key.encode()).hexdigest()[:32]}
            if key in self.pending and self.pending[key] != value:
                raise ValueError('ambiguous approval identity')
            self.pending[key] = value
            if len(self.pending) > MAX_REQUESTS:
                raise ValueError('too many approvals')
        elif 'id' in message and (method.endswith('/requestApproval') or
                                  method in ('execCommandApproval', 'applyPatchApproval')):
            raise ValueError('unsupported approval schema')
        elif method == 'serverRequest/resolved':
            if (not isinstance(params, dict) or not rpc_id(params.get('requestId'))
                    or not identifier(params.get('threadId'))):
                raise ValueError('invalid resolution')
            key = json.dumps(params['requestId'], separators=(',', ':'))
            old = self.pending.get(key)
            if old:
                if old['session_id'] != identifier(params['threadId']):
                    raise ValueError('resolution identity mismatch')
                del self.pending[key]



def atomic_snapshot(path, value):
    data = json.dumps(value, separators=(',', ':')).encode()
    if len(data) > MAX_FILE:
        raise ValueError('oversize snapshot')
    temporary = path.with_name('.' + uuid.uuid4().hex + '.tmp')
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as file:
            file.write(data)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def observe_stream(inbox, failed, stopped, path, source_id, cohort=None, ended=None, clean_exit=None,
                   unavailable_committed=None, retirement_committed=None, diagnostics=None):
    state, sequence, last_publish = Pending(), 0, 0
    last_available = None
    diagnostics = diagnostics or Diagnostics(path, cohort.source_id if cohort else source_id)
    def report(reason=None, side='none', latched=False):
        if reason is None:
            if state.failure:
                reason, side = state.failure
                latched = True
            elif ended and ended.is_set():
                reason, side = getattr(ended, 'failure', None) or ('TRANSPORT_EOF', 'none')
                latched = True
            elif state.buffer or state.client_buffer:
                reason = 'PARTIAL_FRAME'
                side = 'both' if state.buffer and state.client_buffer else 'server' if state.buffer else 'client'
            elif not inbox.empty():
                reason = 'OBSERVATION_BACKLOG'
            else:
                reason = 'AVAILABLE'
        diagnostics.record(reason, side, latched, sequence)
    def consume(entry):
        side, chunk = entry if isinstance(entry, tuple) else ('server', entry)
        if failed.is_set():
            state.fail(*(getattr(failed, 'failure', None) or ('TRANSPORT_LOST', 'none')))
        state.feed(chunk, client=side == 'client')
        if state.failure:
            report()
    try:
        while not stopped.is_set():
            try:
                consume(inbox.get(timeout=.25))
                drain_until = time.monotonic() + .02
                while time.monotonic() < drain_until:
                    consume(inbox.get_nowait())
            except queue.Empty:
                pass
            if failed.is_set():
                state.fail(*(getattr(failed, 'failure', None) or ('TRANSPORT_LOST', 'none')))
                state.buffer.clear()
                state.client_buffer.clear()
                report()
            if not cohort and path.with_name('conflict.json').exists():
                state.fail('SOURCE_CONFLICT')
            available = (state.available and not state.buffer and not state.client_buffer
                         and inbox.empty() and not (ended and ended.is_set()))
            # Availability changes must not wait for the steady-state heartbeat.
            if available == last_available and time.monotonic() - last_publish < .25:
                continue
            last_publish = time.monotonic()
            sequence += 1
            published = True
            if cohort:
                published = cohort.publish(available, state.entries() if available else [])
            else:
                atomic_snapshot(path, {'version': 1, 'source_id': source_id, 'pid': os.getpid(),
                    'sequence': sequence, 'timestamp_ms': int(time.time() * 1000),
                    'available': available, 'pending': state.entries() if available else []})
            if not published and state.failure is None:
                report('SNAPSHOT_BUSY')
            else:
                report()
            if published:
                last_available = available
            if published and not available and unavailable_committed is not None:
                unavailable_committed.set()
    except (OSError, ValueError):
        # Observation failure must not affect the app transport. Its last lease expires.
        report('SNAPSHOT_WRITE_FAILED', latched=True)
    finally:
        try:
            if cohort:
                try:
                    while True:
                        consume(inbox.get_nowait())
                except queue.Empty:
                    pass
                closed = bool(clean_exit and clean_exit.is_set() and not failed.is_set() and
                              state.available and not state.buffer and not state.client_buffer and not state.entries())
                report()
                cohort.publish(closed, [], closed=closed, required=True)
            else:
                atomic_snapshot(path, {'version': 1, 'source_id': source_id, 'pid': os.getpid(),
                    'sequence': sequence + 1, 'timestamp_ms': int(time.time() * 1000),
                    'available': False, 'pending': []})
            if retirement_committed is not None:
                retirement_committed.set()
        except (OSError, ValueError):
            report('SNAPSHOT_WRITE_FAILED', latched=True)


def forward(source, target, observer=None, close_target=None, close_source=None, stop=None):
    def enqueue(chunk):
        if not observer:
            return
        inbox, failed = observer[:2]
        side = observer[2] if len(observer) > 2 else 'server'
        try:
            if failed.is_set():
                return
            inbox.put((side, chunk), timeout=QUEUE_WAIT)
        except queue.Full:
            signal_failure(failed, 'QUEUE_OVERFLOW', side)
    try:
        while True:
            if stop is not None:
                if stop.is_set():
                    return
                if not select.select([source], [], [], .1)[0]:
                    continue
                if stop.is_set():
                    return
            chunk = os.read(source, 65536)
            if not chunk:
                return
            client = observer is not None and len(observer) > 2 and observer[2] == 'client'
            # Queue request identity before the runtime can acknowledge it. This
            # bounded admission wait absorbs scheduler pauses without dropping bytes.
            if client:
                enqueue(chunk)
            offset = 0
            while offset < len(chunk):
                offset += os.write(target, chunk[offset:])
            if not client:
                enqueue(chunk)
    except OSError:
        if observer:
            signal_failure(observer[1], 'TRANSPORT_IO_ERROR', observer[2] if len(observer) > 2 else 'server')
        return
    finally:
        if observer:
            signal_failure(observer[3] if len(observer) > 3 else observer[1],
                           'TRANSPORT_EOF', observer[2] if len(observer) > 2 else 'server')
        if close_source:
            close_source()
        try:
            close_target() if close_target else os.close(target)
        except OSError:
            pass


NOTE_EXITSTATUS = 0x04000000  # macOS sys/event.h; not exported by Python select.


class ExitWatch:
    def __init__(self, pid):
        self.pid = pid
        self.exited = False
        self.queue = select.kqueue()
        try:
            self.queue.control([select.kevent(pid, filter=select.KQ_FILTER_PROC,
                flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                fflags=select.KQ_NOTE_EXIT | NOTE_EXITSTATUS)], 0, 0)
        except BaseException:
            self.queue.close()
            raise

    def wait(self):
        events = self.queue.control(None, 1)
        if len(events) != 1:
            return False
        event = events[0]
        required = select.KQ_NOTE_EXIT | NOTE_EXITSTATUS
        self.exited = (event.ident == self.pid and event.filter == select.KQ_FILTER_PROC and
                       not event.flags & select.KQ_EV_ERROR and event.fflags & required == required and
                       (os.WIFEXITED(event.data) or os.WIFSIGNALED(event.data)))
        return self.exited and os.WIFEXITED(event.data) and os.WEXITSTATUS(event.data) == 0

    def close(self):
        self.queue.close()


def poison_source(path):
    try:
        private_write(path.with_name('conflict.json'), {'conflict': True})
    except (OSError, ValueError):
        pass


def close_fds(descriptors):
    for descriptor in descriptors:
        try:
            os.close(descriptor)
        except OSError:
            pass


def observe_runtime(path, runtime_pid, input_writer, output_reader, ready_writer, commit_reader):
    # This process is a child of the signed runtime, never its ancestor.
    diagnostics = Diagnostics(path, uuid.uuid4().hex)
    runtime_birth = birth(runtime_pid)
    if runtime_birth is None:
        raise ValueError('runtime identity unavailable')
    try:
        watch = ExitWatch(runtime_pid)
    except (OSError, ValueError):
        diagnostics.record('TRANSPORT_LOST', latched=True)
        raise
    try:
        cohort, source_id, diagnostics = register_observer(path)
        if cohort:
            cohort.attach(runtime_pid)
        os.write(ready_writer, b'1')
        os.close(ready_writer)
        if not select.select([commit_reader], [], [], 5)[0] or os.read(commit_reader, 1) != b'1':
            raise ValueError('runtime handoff unavailable')
        os.close(commit_reader)
        inbox, failed, stopped = queue.Queue(maxsize=32), FailureSignal(), threading.Event()
        ended, clean_exit, ingress_stop = FailureSignal(), threading.Event(), threading.Event()
        drained, exited = threading.Event(), threading.Event()
        unavailable_committed, retirement_committed = threading.Event(), threading.Event()
        def close_desktop_output():
            drained.set()
            # A native exit and pipe EOF can arrive in either order. Give the
            # exit watcher a bounded acquisition window without stranding an
            # independently closed stream from a still-live runtime.
            committed = retirement_committed if exited.wait(.25) else unavailable_committed
            if not committed.wait(3):
                poison_source(path)
            os.close(1)
        observer = threading.Thread(target=observe_stream,
            args=(inbox, failed, stopped, path, source_id, cohort, ended, clean_exit,
                  unavailable_committed, retirement_committed, diagnostics), daemon=True)
        stdin = threading.Thread(target=forward,
            args=(0, input_writer, (inbox, failed, 'client', ended)),
            kwargs={'stop': ingress_stop}, daemon=True)
        stdout = threading.Thread(target=forward,
            args=(output_reader, 1, (inbox, failed, 'server', ended)),
            kwargs={'close_source': lambda: os.close(output_reader),
                    'close_target': close_desktop_output}, daemon=True)
        observer.start()
        stdin.start()
        stdout.start()
        try:
            success = watch.wait()
        except (OSError, ValueError):
            success = False
            signal_failure(failed, 'TRANSPORT_LOST', 'none')
        if not watch.exited:
            signal_failure(failed, 'TRANSPORT_LOST', 'none')
            # Lost observation cannot close the live native input. Retain raw
            # forwarding until this exact runtime identity has disappeared.
            while True:
                try:
                    if birth(runtime_pid) != runtime_birth:
                        break
                except ValueError:
                    pass
                time.sleep(.1)
        exited.set()
        # No further client records may race the final observer drain.
        ingress_stop.set()
        stdin.join(timeout=1)
        if stdin.is_alive():
            signal_failure(failed, 'TRANSPORT_LOST', 'none')
        drained.wait()
        if success:
            clean_exit.set()
        stopped.set()
        observer.join(timeout=3)
        if observer.is_alive():
            # Never expose EOF as clean retirement after an incomplete drain.
            poison_source(path)
        stdout.join(timeout=4)
        if stdout.is_alive():
            poison_source(path)
    except (OSError, ValueError):
        diagnostics.record('INTERNAL_OBSERVATION_ERROR', latched=True)
        raise
    finally:
        watch.close()


def terminate_sidecar(pid, timeout=.5):
    """This PID is our own un-reaped fork child, never an arbitrary process."""
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    for sig in (None, signal.SIGKILL):
        if sig is not None:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                waited, _ = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                return
            except InterruptedError:
                continue
            if waited == pid:
                return
            time.sleep(.01)
    # Native startup must continue even if OS reaping is delayed. Coverage was
    # already poisoned; this path never claims clean retirement.


def exec_observed(path, args):
    descriptors = []
    sidecar = None
    original_input = original_output = None
    try:
        if sys.platform != 'darwin' or not hasattr(select, 'kqueue'):
            raise OSError('native exit observation unavailable')
        original_input = os.dup(0)
        original_output = os.dup(1)
        for _ in range(4):
            descriptors.extend(os.pipe())
        input_reader, input_writer, output_reader, output_writer, ready_reader, ready_writer, commit_reader, commit_writer = descriptors
        runtime_pid = os.getpid()
        sidecar = os.fork()
        if sidecar == 0:
            # Desktop tree cleanup can signal this child before the native
            # runtime completes its graceful exit. Keep observing until that
            # exit and the final drain; SIGTERM itself never proves retirement.
            # This disposition is child-only and cannot change native signals.
            signal.signal(signal.SIGTERM, lambda _signum, _frame: None)
            close_fds((input_reader, output_writer, ready_reader, commit_writer, original_input, original_output, 2))
            try:
                observe_runtime(path, runtime_pid, input_writer, output_reader, ready_writer, commit_reader)
            except BaseException:
                poison_source(path)
                os._exit(1)
            os._exit(0)
        close_fds((input_writer, output_reader, ready_writer, commit_reader))
        if not select.select([ready_reader], [], [], 5)[0] or os.read(ready_reader, 1) != b'1':
            raise OSError('observer startup unavailable')
        os.dup2(input_reader, 0)
        os.dup2(output_writer, 1)
        os.write(commit_writer, b'1')
        close_fds((input_reader, output_writer, ready_reader, commit_writer))
        # Backups are close-on-exec; retain them until native exec succeeds.
        os.execv(REAL_CLI, [REAL_CLI, *args])
    except (OSError, ValueError, AttributeError):
        Diagnostics(path, uuid.uuid4().hex).record('STARTUP_UNAVAILABLE', latched=True)
        poison_source(path)
        if original_input is not None:
            os.dup2(original_input, 0)
        if original_output is not None:
            os.dup2(original_output, 1)
        close_fds(descriptors + [fd for fd in (original_input, original_output) if fd is not None])
        if sidecar:
            terminate_sidecar(sidecar)
        os.execv(REAL_CLI, [REAL_CLI, *args])


def register_observer(path):
    cohort = None
    source_id = uuid.uuid4().hex
    if os.environ.get('BAMBOOX_PERMISSION_COHORT'):
        try:
            cohort = CohortWriter(path, os.environ['BAMBOOX_PERMISSION_COHORT'],
                                  int(os.environ['BAMBOOX_PERMISSION_APP_PID']),
                                  os.environ['BAMBOOX_PERMISSION_APP_BIRTH'])
        except (OSError, ValueError, TypeError, KeyError):
            try:
                private_write(path.with_name('conflict.json'), {'conflict': True})
            except (OSError, ValueError):
                pass
            raise ValueError('observer registration unavailable')
    else:
        try:
            lock = os.open(path.with_name('writer.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
            lock_info = os.fstat(lock)
            if (not stat.S_ISREG(lock_info.st_mode) or lock_info.st_uid != os.getuid()
                    or stat.S_IMODE(lock_info.st_mode) != 0o600):
                raise OSError('unsafe writer lock')
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            try:
                atomic_snapshot(path.with_name('conflict.json'), {'conflict': True})
            except OSError:
                pass
            raise ValueError('observer registration unavailable')
        except OSError:
            raise ValueError('observer registration unavailable')
        try:
            path.with_name('conflict.json').unlink(missing_ok=True)
        except OSError:
            raise ValueError('observer registration unavailable')
    return cohort, source_id, Diagnostics(path, cohort.source_id if cohort else source_id)


def main():
    args = sys.argv[1:]
    path_text = os.environ.get('BAMBOOX_PERMISSION_SOURCE')
    server_index = args.index('app-server') if 'app-server' in args else None
    server_args = args[server_index + 1:] if server_index is not None else []
    if (server_index is None or not path_text or
            (server_args and not server_args[0].startswith('-')) or
            any(arg.startswith('--listen=') and arg != '--listen=stdio://' for arg in server_args) or
            ('--listen' in server_args and server_args[server_args.index('--listen') + 1:] != ['stdio://'])):
        os.execv(REAL_CLI, [REAL_CLI, *args])
    path = Path(path_text)
    # The reviewed installer owns directory creation; unsafe/missing paths disable
    # observation and preserve the original runtime rather than blocking startup.
    try:
        import stat
        info = path.parent.lstat()
        if (not path.is_absolute() or not stat.S_ISDIR(info.st_mode) or
                info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700):
            raise ValueError('unsafe source directory')
    except (OSError, ValueError):
        os.execv(REAL_CLI, [REAL_CLI, *args])
    exec_observed(path, args)


if __name__ == '__main__':
    sys.exit(main())
