#!/usr/bin/env python3
"""A stand-in for the T3 Code server, for testing the shell's AI panel.

Speaks what Ai.qml speaks: the HTTP reads, the websocket ticket, and Effect
RPC over /ws with the two streams. Threads and projects come from fixtures
(copies of the real server's answers); a message or a new thread starts a
scripted run: thinking, commands, an answer that arrives in pieces. A message
with "approve" in it waits for an approval, one with "question" asks one, one
with "fail" fails.

    tools/t3-mock.py <port> [fixtures dir]
    POST /test/log   the commands received so far, as JSON

Fixtures, if a directory is given: shell.json (GET /api/orchestration/shell),
projects.json (GET /api/projects) and thread-<id>.json (GET
/api/orchestration/threads/<id>), saved from a real server. Without them
there is one project and no thread. MOCK_SPEED=4 makes a run four times as
fast; MOCK_ID and MOCK_LABEL are what the server says it is, for a second
one to pair the shell with (`ai pair`). See "AI chat" in docs/decisions.md for how the panel is run against it.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

PORT = int(sys.argv[1])
FIXTURES = sys.argv[2] if len(sys.argv) > 2 else ""
SPEED = float(os.environ.get("MOCK_SPEED", "1"))

lock = threading.RLock()
projects = [{"id": "project:mock", "title": "mock", "workspaceRoot": "/tmp/t3-mock", "defaultModelSelection": None, "deletedAt": None}]
threads = {}
projections = {}
if FIXTURES:
    projects = json.load(open(os.path.join(FIXTURES, "projects.json")))["projects"]
    threads = {thread["id"]: thread for thread in json.load(open(os.path.join(FIXTURES, "shell.json")))["threads"]}
    for name in os.listdir(FIXTURES):
        if name.startswith("thread-"):
            projection = json.load(open(os.path.join(FIXTURES, name)))["projection"]
            projections[projection["thread"]["id"]] = projection
sockets = []
log = []
sequence = [1000]


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + ".%03dZ" % (time.time() % 1 * 1000)


def projection_of(thread_id):
    if thread_id not in projections:
        projections[thread_id] = {"thread": threads[thread_id], "runs": [], "turnItems": [], "runtimeRequests": []}
    return projections[thread_id]


class Socket:
    def __init__(self, connection):
        self.connection = connection
        self.write_lock = threading.Lock()
        self.shell_stream = None
        self.thread_streams = {}
        # per stream: values waiting, and whether a chunk is unacknowledged
        self.queues = {}
        self.unacked = set()

    def chunk(self, stream, values):
        with lock:
            self.queues.setdefault(stream, []).extend(values)
            self.flush(stream)

    def flush(self, stream):
        with lock:
            if stream in self.unacked or not self.queues.get(stream):
                return
            values, self.queues[stream] = self.queues[stream], []
            self.unacked.add(stream)
        self.send({"_tag": "Chunk", "requestId": stream, "values": values})

    def ack(self, stream):
        with lock:
            self.unacked.discard(stream)
        self.flush(stream)

    def send(self, payload):
        data = json.dumps(payload).encode()
        header = bytes([0x81])
        if len(data) < 126:
            header += bytes([len(data)])
        elif len(data) < 65536:
            header += bytes([126]) + struct.pack(">H", len(data))
        else:
            header += bytes([127]) + struct.pack(">Q", len(data))
        try:
            with self.write_lock:
                self.connection.sendall(header + data)
        except OSError:
            pass

    def read_exact(self, count):
        data = b""
        while len(data) < count:
            chunk = self.connection.recv(count - len(data))
            if not chunk:
                raise ConnectionError
            data += chunk
        return data

    def frames(self):
        while True:
            first, second = self.read_exact(2)
            opcode = first & 0x0F
            length = second & 0x7F
            if length == 126:
                length = struct.unpack(">H", self.read_exact(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self.read_exact(8))[0]
            mask = self.read_exact(4) if second & 0x80 else b"\0\0\0\0"
            data = bytes(byte ^ mask[index % 4] for index, byte in enumerate(self.read_exact(length)))
            if opcode == 8:
                return
            if opcode == 9:
                with self.write_lock:
                    self.connection.sendall(bytes([0x8A, len(data)]) + data)
            elif opcode == 1:
                yield json.loads(data)


def to_shell(value):
    for one in list(sockets):
        if one.shell_stream:
            one.chunk(one.shell_stream, [value])


def to_thread(thread_id, value):
    for one in list(sockets):
        stream = one.thread_streams.get(thread_id)
        if stream:
            one.chunk(stream, [value])


def event(thread_id, kind, payload):
    sequence[0] += 1
    to_thread(thread_id, {"kind": "event", "sequence": sequence[0], "event": {"type": kind, "payload": payload}})


def touch(thread_id, **changes):
    with lock:
        thread = threads[thread_id]
        thread.update(changes)
        thread["updatedAt"] = now()
        sequence[0] += 1
        to_shell({"kind": "thread.updated", "sequence": sequence[0], "thread": thread})


def put(thread_id, item):
    with lock:
        projection = projection_of(thread_id)
        item["updatedAt"] = now()
        for index, have in enumerate(projection["turnItems"]):
            if have["id"] == item["id"]:
                projection["turnItems"][index] = item
                break
        else:
            projection["turnItems"].append(item)
        event(thread_id, "turn-item.updated", item)


def item(thread_id, run_id, kind, **fields):
    with lock:
        ordinal = max([one.get("ordinal", 0) for one in projection_of(thread_id)["turnItems"]] + [0]) + 1
    made = {
        "id": "item:" + uuid.uuid4().hex, "threadId": thread_id, "runId": run_id, "ordinal": ordinal,
        "status": "completed", "title": None, "startedAt": now(), "completedAt": now(), "type": kind,
        "nativeItemRef": {"driver": "mock", "nativeId": uuid.uuid4().hex, "strength": "strong"},
    }
    made.update(fields)
    return made


ANSWER = """Here is what I found.

## Summary

The change is **small**: one function in `shell/Ai.qml` read the wrong field, so every refetch was dropped.

| Step | Result |
|---|---|
| `lint` | pass |
| `test` | pass, 311 tests |

```js
const next = body?.projection;
if (code === 200 && next?.thread?.id === wanted)
    applyProjection(next);
```

1. The HTTP answer wraps the thread in `projection`.
2. The socket's snapshot does too.

See [the notes](https://example.org/notes) for more. That is all there is to it."""


def wait(seconds):
    time.sleep(seconds / SPEED)


def run(thread_id, text, new):
    run_id = "run:" + uuid.uuid4().hex
    projection = projection_of(thread_id)
    record = {"id": run_id, "threadId": thread_id, "status": "running", "requestedAt": now(), "startedAt": now(), "completedAt": None}
    with lock:
        projection["runs"].append(record)
        event(thread_id, "run.created", record)
    touch(thread_id, status="running", activeRunId=run_id, latestRunId=run_id, latestRunRequestedAt=now(), latestUserMessageAt=now())
    put(thread_id, item(thread_id, run_id, "user_message", text=text, attachments=[], nativeItemRef=None))
    wait(0.4)
    put(thread_id, item(thread_id, run_id, "command_execution", title="Workspace ready", input="Preparing workspace", exitCode=0, nativeItemRef=None))
    wait(0.5)
    thought = item(thread_id, run_id, "reasoning", title="Thinking", text="", streaming=True, status="running")
    for piece in ["I should look at how the thread", " is fetched, and compare the answer's shape", " with what the panel expects."]:
        thought["text"] += piece
        put(thread_id, dict(thought))
        wait(0.3)
    thought.update(streaming=False, status="completed", completedAt=now())
    put(thread_id, dict(thought))
    for command in ["git status -sb | head -20", "grep -n 'body.thread' shell/Ai.qml", "pnpm run --silent test"]:
        one = item(thread_id, run_id, "command_execution", input=command, status="running", exitCode=None)
        put(thread_id, dict(one))
        wait(0.7)
        one.update(status="completed", exitCode=0, completedAt=now())
        put(thread_id, dict(one))
    put(thread_id, item(thread_id, run_id, "file_change", fileName="/mnt/data/dev/kde/kde-quickshell/shell/Ai.qml"))
    wait(0.4)
    if "approve" in text:
        request_id = "runtime-request:" + uuid.uuid4().hex
        ask = item(thread_id, run_id, "approval_request", requestId=request_id, requestKind="command", prompt="rm -rf node_modules && pnpm install --frozen-lockfile", status="waiting")
        put(thread_id, dict(ask))
        touch(thread_id, pendingRuntimeRequest={"id": request_id, "kind": "command", "createdAt": now()}, activityRunStatus="waiting")
        answered = pending.setdefault(request_id, threading.Event())
        answered.wait(600)
        ask.update(status="completed", completedAt=now())
        put(thread_id, dict(ask))
        touch(thread_id, pendingRuntimeRequest=None, activityRunStatus="running")
        wait(0.4)
    if "question" in text:
        request_id = "runtime-request:" + uuid.uuid4().hex
        ask = item(thread_id, run_id, "user_input_request", requestId=request_id, status="waiting", questions=[
            {"id": "Which way?", "header": "Route", "question": "Which way do you want to go about it?", "multiSelect": False, "options": [
                {"label": "Fix the field (Recommended)", "description": "One line: read the thread out of `projection`."},
                {"label": "Use the socket only", "description": "Drop the HTTP refetch and rely on the stream's snapshot."}]},
            {"id": "Anything else?", "header": "More", "question": "Is there anything else that bothers you?", "multiSelect": True, "options": []}])
        put(thread_id, dict(ask))
        touch(thread_id, pendingRuntimeRequest={"id": request_id, "kind": "user_input", "createdAt": now()}, activityRunStatus="waiting")
        answered = pending.setdefault(request_id, threading.Event())
        answered.wait(600)
        ask.update(status="completed", completedAt=now(), questionAnswer={"requestId": request_id, "answers": answers.get(request_id, {})})
        put(thread_id, dict(ask))
        touch(thread_id, pendingRuntimeRequest=None, activityRunStatus="running")
        wait(0.4)
    if "fail" in text:
        put(thread_id, item(thread_id, run_id, "error", title="Usage limit reached", status="failed", failure={"class": "usage_limit", "message": "Claude API rate limit reached. Try again later."}))
        finish(thread_id, record, "failed")
        return
    answer = item(thread_id, run_id, "assistant_message", text="", streaming=True, status="running")
    words = ANSWER.split(" ")
    for start in range(0, len(words), 4):
        if record["status"] != "running":
            break
        answer["text"] = " ".join(words[: start + 4])
        put(thread_id, dict(answer))
        wait(0.12)
    answer.update(streaming=False, status="completed", completedAt=now())
    put(thread_id, dict(answer))
    if record["status"] == "running":
        put(thread_id, item(thread_id, run_id, "checkpoint", checkpointId="c", files=[], nativeItemRef=None))
        finish(thread_id, record, "completed")


def finish(thread_id, record, status):
    with lock:
        record.update(status=status, completedAt=now())
        event(thread_id, "run.updated", dict(record))
    touch(thread_id, status=status, activeRunId=None, activityRunStatus=None, latestRunCompletedAt=now())


pending = {}
answers = {}


def dispatch(payload):
    kind = payload.get("type")
    thread_id = payload.get("threadId")
    log.append(payload)
    if kind == "message.dispatch":
        threading.Thread(target=run, args=(thread_id, payload["text"], False), daemon=True).start()
    elif kind == "run.interrupt":
        with lock:
            for record in projection_of(thread_id)["runs"]:
                if record["id"] == payload.get("runId") and record["status"] == "running":
                    record.update(status="interrupted", completedAt=now())
                    event(thread_id, "run.updated", dict(record))
        touch(thread_id, status="interrupted", activeRunId=None, latestRunCompletedAt=now())
    elif kind == "runtime-request.respond":
        answers[payload["requestId"]] = payload.get("answers") or {}
        pending.setdefault(payload["requestId"], threading.Event()).set()
    elif kind == "thread.visit" and thread_id in threads:
        touch(thread_id, lastVisitedAt=payload.get("visitedAt") or now())
    return {"sequence": sequence[0]}


def launch(payload):
    log.append({"type": "launchThread", **payload})
    thread_id = payload["threadId"]
    with lock:
        threads[thread_id] = {
            "id": thread_id, "projectId": payload["projectId"], "title": payload["title"], "createdBy": "user", "creationSource": "web",
            "modelSelection": payload["modelSelection"], "runtimeMode": payload["runtimeMode"], "branch": "main", "status": "idle",
            "lineage": {"parentThreadId": None, "relationshipToParent": None, "rootThreadId": thread_id}, "activeRunId": None,
            "pendingRuntimeRequest": None, "hasActionableProposedPlan": False, "latestRunCompletedAt": None, "lastVisitedAt": None,
            "createdAt": now(), "updatedAt": now(), "archivedAt": None, "deletedAt": None, "itemCount": 0,
        }
    touch(thread_id)
    threading.Thread(target=lambda: (wait(0.3), run(thread_id, payload["initialMessage"]["text"], True)), daemon=True).start()
    return {"threadId": thread_id, "projection": projection_of(thread_id), "resumed": False}


def serve_socket(connection):
    one = Socket(connection)
    sockets.append(one)
    try:
        for frame in one.frames():
            if frame.get("_tag") == "Interrupt":
                for thread_id, stream in list(one.thread_streams.items()):
                    if stream == frame.get("requestId"):
                        del one.thread_streams[thread_id]
                continue
            if frame.get("_tag") == "Ack":
                one.ack(frame.get("requestId"))
                continue
            if frame.get("_tag") != "Request":
                continue
            tag, payload, request = frame["tag"], frame.get("payload") or {}, frame["id"]
            if tag == "orchestration.subscribeShell":
                one.shell_stream = request
                with lock:
                    one.chunk(request, [{"kind": "snapshot", "snapshot": {"schemaVersion": 2, "snapshotSequence": sequence[0], "projects": projects, "threads": list(threads.values())}},
                        {"kind": "snapshot", "snapshot": {"schemaVersion": 2, "snapshotSequence": sequence[0], "projects": projects, "threads": [], "archivedThreads": []}, "resolvedRepositoryIdentityRoots": [each["workspaceRoot"] for each in projects]}])
            elif tag == "orchestration.subscribeThread":
                with lock:
                    if payload["threadId"] not in threads:
                        one.send({"_tag": "Exit", "requestId": request, "exit": {"_tag": "Failure", "cause": "no such thread"}})
                        continue
                    one.thread_streams[payload["threadId"]] = request
                    one.chunk(request, [{"kind": "snapshot", "snapshotSequence": sequence[0], "projection": projection_of(payload["threadId"])}])
            elif tag == "orchestration.dispatchCommand":
                one.send({"_tag": "Exit", "requestId": request, "exit": {"_tag": "Success", "value": dispatch(payload)}})
            elif tag == "orchestration.launchThread":
                one.send({"_tag": "Exit", "requestId": request, "exit": {"_tag": "Success", "value": launch(payload)}})
            else:
                one.send({"_tag": "Exit", "requestId": request, "exit": {"_tag": "Failure", "cause": "unknown " + tag}})
    except (ConnectionError, OSError):
        pass
    finally:
        sockets.remove(one)
        connection.close()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *arguments):
        pass

    def answer(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.startswith("/ws"):
            key = self.headers["Sec-WebSocket-Key"]
            accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            self.close_connection = True
            serve_socket(self.connection)
            return
        with lock:
            if self.path == "/.well-known/t3/environment":
                self.answer(200, {"environmentId": os.environ.get("MOCK_ID", "mock-environment"), "label": os.environ.get("MOCK_LABEL", "mock")})
            elif self.path == "/api/auth/session":
                self.answer(200, {"authenticated": True})
            elif self.path == "/api/projects":
                self.answer(200, {"projects": projects})
            elif self.path == "/api/orchestration/shell":
                self.answer(200, {"schemaVersion": 2, "snapshotSequence": sequence[0], "threads": list(threads.values()), "projects": projects, "archivedThreads": []})
            elif self.path.startswith("/api/orchestration/threads/"):
                thread_id = unquote(self.path.rsplit("/", 1)[1])
                if thread_id in threads:
                    self.answer(200, {"snapshotSequence": sequence[0], "projection": projection_of(thread_id)})
                else:
                    self.answer(404, {"error": "not found"})
            else:
                self.answer(404, {})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(length)
        if self.path == "/oauth/token":
            self.answer(200, {"access_token": "mock-token", "expires_in": 30 * 86400})
        elif self.path == "/api/auth/websocket-ticket":
            self.answer(200, {"ticket": "ticket"})
        elif self.path == "/test/log":
            self.answer(200, log)
        else:
            self.answer(404, {})


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


Server(("127.0.0.1", PORT), Handler).serve_forever()
