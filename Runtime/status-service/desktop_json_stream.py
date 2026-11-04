"""Bounded JSON-lines validation with a permission-lifecycle metadata projection.

Every byte is validated. Discarding an unneeded value never skips framing or
turns an incomplete frame into available permission knowledge.
"""
import codecs
import io
import json
import re

ALL = object()
PRESENT = object()
FIELDS = {
    'method': ALL, 'id': ALL, 'error': PRESENT,
    'params': {'threadId': ALL, 'turnId': ALL, 'requestId': ALL,
               'expectedTurnId': ALL, 'input': ({'type': ALL, 'text': ALL},),
               'item': {'id': ALL, 'type': ALL, 'questions': ALL,
                        'content': ({'type': ALL, 'text': ALL},)},
               'turn': {'id': ALL, 'status': ALL}},
    'result': {'turnId': ALL, 'turn': {'id': ALL}},
}
SPECIAL = re.compile(r'["\\\x00-\x1f]')
NUMBER = re.compile(r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\Z')
HEX = frozenset('0123456789abcdefABCDEF')


class FrameError(ValueError):
    def __init__(self, reason='INVALID_JSON'):
        super().__init__(reason)
        self.reason = reason


class JsonFrames:
    MAX_FRAME = 512 * 1024 * 1024
    MAX_DEPTH = 64
    MAX_NODES = 65536
    MAX_KEY = 1024

    def __init__(self, metadata_limit=8 * 1024 * 1024):
        self.metadata_limit = metadata_limit
        self.clear()

    def clear(self):
        self.decoder = codecs.getincrementaldecoder('utf-8')('strict')
        self.stack = []
        self.root = None
        self.done = False
        self.size = self.kept = self.nodes = 0
        self.token = None
        self.parts = []
        self.string_buffer = None
        self.token_size = 0
        self.escape = 0

    def __bool__(self):
        return self.size != 0

    def _spec(self):
        if not self.stack:
            if self.done:
                raise FrameError()
            return FIELDS
        top = self.stack[-1]
        if top['state'] not in ('value', 'value_or_end'):
            raise FrameError()
        spec = top['spec']
        if spec is ALL:
            return ALL
        if isinstance(spec, tuple) and top['kind'] == '[':
            return spec[0]
        return spec.get(top.get('key')) if isinstance(spec, dict) and top['kind'] == '{' else None

    def _value(self, value, spec):
        if spec is PRESENT:
            value = None
        if not self.stack:
            self.root, self.done = value, True
            return
        top = self.stack[-1]
        if top['kind'] == '{':
            if spec is not None:
                key = top['key']
                if key in top['value']:
                    raise FrameError()  # Ambiguous selected metadata is never last-wins.
                self._count(len(key.encode('utf-8')))
                top['value'][key] = value
            top['state'] = 'comma_or_end'
        else:
            if spec is not None:
                top['value'].append(value)
            top['state'] = 'comma_or_end'

    def _count(self, amount):
        self.kept += amount
        if self.kept > self.metadata_limit:
            raise FrameError('FRAME_LIMIT')

    def _append(self, text):
        if self.keep:
            raw = text.encode('utf-8')
            self.token_size += len(text)
            if self.key:
                if self.token_size > self.MAX_KEY:
                    raise FrameError('FRAME_LIMIT')
            else:
                self._count(len(raw))
            self.string_buffer.write(raw)

    def _string_end(self):
        value = json.loads(self.string_buffer.getvalue()) if self.keep else None
        self.string_buffer = None
        self.token = None
        if self.key:
            self.stack[-1]['key'] = value
            self.stack[-1]['state'] = 'colon'
        else:
            self._value(value, self.spec)

    def _atom_end(self):
        text = ''.join(self.parts)
        if text not in ('true', 'false', 'null') and not NUMBER.fullmatch(text):
            raise FrameError()
        value = json.loads(text) if self.spec is not None and self.spec is not PRESENT else None
        self.parts = []
        self.token = None
        self._value(value, self.spec)

    def _text(self, text):
        i = 0
        while i < len(text):
            char = text[i]
            if self.token == 'string':
                if self.escape:
                    self._append(char)
                    if self.escape == -1:
                        if char == 'u':
                            self.escape = 4
                        elif char in '"\\/bfnrt':
                            self.escape = 0
                        else:
                            raise FrameError()
                    else:
                        if char not in HEX:
                            raise FrameError()
                        self.escape -= 1
                    i += 1
                    continue
                match = SPECIAL.search(text, i)
                end = match.start() if match else len(text)
                self._append(text[i:end])
                i = end
                if match is None:
                    continue
                char = text[i]
                self._append(char)
                i += 1
                if char == '"':
                    self._string_end()
                elif char == '\\':
                    self.escape = -1
                else:
                    raise FrameError()
                continue
            if self.token == 'atom':
                if char in ' \t\r\n,]}':
                    self._atom_end()
                    continue
                self.parts.append(char)
                if len(self.parts) > 128:
                    raise FrameError('FRAME_LIMIT')
                i += 1
                continue
            if char in ' \t\r\n':
                i += 1
                continue
            top = self.stack[-1] if self.stack else None
            state = top['state'] if top else 'root'
            if char == '"':
                self.key = bool(top and top['kind'] == '{' and state in ('key', 'key_or_end'))
                self.spec = None if self.key else self._spec()
                if not self.key and self.spec is not None:
                    self.nodes += 1
                    if self.nodes > self.MAX_NODES:
                        raise FrameError('FRAME_LIMIT')
                self.keep = self.key or (self.spec is not None and self.spec is not PRESENT)
                self.token, self.parts, self.token_size = 'string', [], 0
                self.string_buffer = io.BytesIO() if self.keep else None
                self._append('"')
            elif char in '{[':
                spec = self._spec()
                if len(self.stack) >= self.MAX_DEPTH:
                    raise FrameError('FRAME_LIMIT')
                if spec is not None:
                    self.nodes += 1
                    if self.nodes > self.MAX_NODES:
                        raise FrameError('FRAME_LIMIT')
                self.stack.append({'kind': char, 'spec': spec,
                    'state': 'key_or_end' if char == '{' else 'value_or_end',
                    'value': {} if char == '{' else []})
            elif char in '}]':
                if (not top or top['kind'] != ('{' if char == '}' else '[')
                        or state not in ('key_or_end', 'value_or_end', 'comma_or_end')):
                    raise FrameError()
                self.stack.pop()
                self._value(top['value'], top['spec'])
            elif char == ':':
                if not top or state != 'colon':
                    raise FrameError()
                top['state'] = 'value'
            elif char == ',':
                if not top or state != 'comma_or_end':
                    raise FrameError()
                top['state'] = 'key' if top['kind'] == '{' else 'value'
            else:
                self.spec = self._spec()
                if self.spec is not None:
                    self.nodes += 1
                    if self.nodes > self.MAX_NODES:
                        raise FrameError('FRAME_LIMIT')
                self.token, self.parts = 'atom', [char]
            i += 1

    def feed(self, chunk):
        for part in self._lines(chunk):
            self.size += len(part)
            if self.size > self.MAX_FRAME:
                raise FrameError('FRAME_LIMIT')
            try:
                self._text(self.decoder.decode(part))
                if part.endswith(b'\n'):
                    self._text(self.decoder.decode(b'', final=True))
                    if not self.done or self.stack or self.token is not None:
                        raise FrameError()
                    message = self.root
                    if not isinstance(message, dict):
                        raise FrameError('RPC_NOT_OBJECT')
                    self.clear()
                    yield message
            except UnicodeError as error:
                raise FrameError() from error

    @staticmethod
    def _lines(chunk):
        # Only LF terminates JSONL. str/bytes.splitlines also splits raw controls.
        start = 0
        while start < len(chunk):
            end = chunk.find(b'\n', start)
            end = len(chunk) if end < 0 else end + 1
            yield chunk[start:end]
            start = end
