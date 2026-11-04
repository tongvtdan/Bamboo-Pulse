"""Metadata-only lifecycle for the desktop's asynchronous question cards."""
from collections import OrderedDict
import hashlib
import json
from model import identifier
from permission_status import MAX_REQUESTS

OPEN = '<send_user_message_question_reply>'
CLOSE = '</send_user_message_question_reply>'
MAX_HISTORY = 4096


def question_key(text):
    if not isinstance(text, str) or len(text) > 2048:
        return None
    try:
        value = json.loads(text)
    except ValueError:
        return None
    if (not isinstance(value, list) or len(value) != 3 or value[0] != 'request_user_input_async'
            or not identifier(value[1]) or type(value[2]) is not int or not 0 <= value[2] < MAX_REQUESTS
            or json.dumps(value, separators=(',', ':'), ensure_ascii=False) != text):
        return None
    return hashlib.sha256(('async:' + text).encode()).hexdigest()[:32]


def reply_keys(content):
    if (not isinstance(content, list) or len(content) != 1 or not isinstance(content[0], dict)
            or content[0].get('type') != 'text' or not isinstance(content[0].get('text'), str)):
        return frozenset()
    text = content[0]['text'].strip()
    if not text.startswith(OPEN) or not text.endswith(CLOSE):
        return frozenset()
    try:
        value = json.loads(text[len(OPEN):-len(CLOSE)])
    except ValueError:
        return frozenset()
    rows = value if isinstance(value, list) else [value]
    if (not 0 < len(rows) <= MAX_REQUESTS or any(not isinstance(row, dict) or
            not all(isinstance(row.get(key), str) for key in ('questionItemId', 'question', 'answer'))
            for row in rows)):
        return frozenset()
    return frozenset(key for row in rows if (key := question_key(row['questionItemId'])))


class AsyncQuestions:
    def __init__(self):
        self.pending = {}
        self.answered = OrderedDict()
        self.interrupted = OrderedDict()
        self.clients = {}

    def remember(self, history, key):
        history[key] = None
        if len(history) > MAX_HISTORY:
            raise ValueError('question lifecycle history exceeded')

    def resolve(self, session, keys):
        for key in keys:
            identity = (session, key)
            self.remember(self.answered, identity)
            self.pending.pop(identity, None)

    def client(self, message):
        if message.get('method') not in ('turn/steer', 'turn/start'):
            return
        params = message.get('params')
        if not isinstance(params, dict):
            return
        keys = reply_keys(params.get('input'))
        if not keys:
            return
        session = identifier(params.get('threadId'))
        turn = identifier(params.get('expectedTurnId')) if message['method'] == 'turn/steer' else None
        request = message.get('id')
        if (not session or (message['method'] == 'turn/steer' and not turn) or
                not ((type(request) is int and -(2**63) <= request < 2**63) or
                     (isinstance(request, str) and 0 < len(request) <= 256))):
            raise ValueError('invalid question reply RPC identity')
        key = json.dumps(request, separators=(',', ':'))
        value = (message['method'], session, turn, keys)
        if key in self.clients and self.clients[key] != value:
            raise ValueError('conflicting reply RPC identity')
        self.clients[key] = value
        if len(self.clients) > MAX_REQUESTS:
            raise ValueError('too many unanswered reply RPCs')

    def server(self, message):
        method = message.get('method')
        if method is None and 'id' in message:
            key = json.dumps(message['id'], separators=(',', ':'))
            reply = self.clients.pop(key, None)
            if reply is None or 'error' in message:
                return
            kind, session, expected, keys = reply
            result = message.get('result')
            actual = None
            if isinstance(result, dict):
                if kind == 'turn/steer':
                    actual = identifier(result.get('turnId'))
                elif isinstance(result.get('turn'), dict):
                    actual = identifier(result['turn'].get('id'))
            if not actual or (expected is not None and expected != actual):
                raise ValueError('question reply acknowledgement mismatch')
            self.resolve(session, keys)
            return
        if method not in ('item/started', 'item/completed', 'turn/completed'):
            return
        params = message.get('params')
        if not isinstance(params, dict):
            raise ValueError('invalid question lifecycle event')
        session, turn = identifier(params.get('threadId')), identifier(params.get('turnId'))
        if method == 'turn/completed':
            data = params.get('turn')
            if isinstance(data, dict) and data.get('status') == 'interrupted':
                turn = identifier(data.get('id'))
                if not session or not turn:
                    raise ValueError('missing interrupted turn identity')
                self.remember(self.interrupted, (session, turn))
                self.resolve(session, [key for (owner, key), value in self.pending.items()
                                       if owner == session and value['turn_id'] == turn])
            return
        item = params.get('item')
        if not isinstance(item, dict):
            return
        if item.get('type') == 'agentMessage' and item.get('questions') is not None:
            questions = item['questions']
            if (not session or not turn or not identifier(item.get('id')) or
                    not isinstance(questions, list) or len(questions) > MAX_REQUESTS or
                    any(not isinstance(q, dict) or set(q) - {'title', 'options'} or
                        not isinstance(q.get('title'), str) or
                        (q.get('options') is not None and
                         (not isinstance(q['options'], list) or
                          any(not isinstance(option, str) for option in q['options'])))
                        for q in questions)):
                raise ValueError('invalid async question metadata')
            if (session, turn) in self.interrupted:
                return
            for index in range(len(questions)):
                reference = json.dumps(['request_user_input_async', item['id'], index],
                                       separators=(',', ':'), ensure_ascii=False)
                key = question_key(reference)
                identity = (session, key)
                if identity in self.answered:
                    continue
                value = {'session_id': session, 'turn_id': turn, 'request_id': key}
                if identity in self.pending and self.pending[identity] != value:
                    raise ValueError('conflicting async question identity')
                self.pending[identity] = value
            if len(self.pending) > MAX_REQUESTS:
                raise ValueError('too many async questions')
        elif item.get('type') == 'userMessage':
            keys = reply_keys(item.get('content'))
            if keys:
                if not session:
                    raise ValueError('missing accepted reply thread')
                self.resolve(session, keys)
