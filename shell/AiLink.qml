import Quickshell
import QtQuick
import QtWebSockets

// One T3 Code server, as the Ai singleton sees it: this machine's, or
// another's that the user has paired the shell with (Ai.pairWith()). The
// protocol is in Ai.qml's first lines; this is the part of it that is the
// same for every server: the session, the reads over HTTP, the socket with
// its requests and its two streams. What comes of it are `projects` and
// `threads`, each marked with the server it is of (`environment`: `key`).
Scope {
    id: link

    // what the server is filed under: "local", or its environment id
    required property string key
    property string label: ""
    // http://host:port
    property string origin: ""
    // the bearer token and when it runs out (epoch ms); the Ai singleton
    // stores both
    property string accessToken: ""
    property real tokenExpiresAt: 0
    readonly property bool local: key === "local"
    readonly property bool paired: accessToken !== "" && tokenExpiresAt > Date.now() + 60000

    // idle (not asked yet, or not paired), offline (no server), pairing,
    // connecting, ready
    property string status: "idle"
    property string statusText: ""
    // the list of threads is loaded
    property bool ready: false
    property var projects: []
    property var threads: []

    // the server no longer knows the token
    signal refused
    // the server answers but the shell is not paired with it, and the user
    // is asking: for the local server a token can be had (ai.sh)
    signal unpaired
    // what the stream of the thread that is on show has sent
    signal threadValues(string threadId, var values)

    function setStatus(next, text) {
        status = next;
        statusText = text ?? "";
    }

    function mark(list) {
        return list.map(one => Object.assign({}, one, {
                environment: key
            }));
    }

    function uuid(): string {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, character => {
            const random = Math.floor(Math.random() * 16);
            return (character === "x" ? random : (random & 0x3 | 0x8)).toString(16);
        });
    }

    // An HTTP call against the server. `done` gets (status, parsed-or-text).
    function http(method, path, body, done) {
        const request = new XMLHttpRequest();
        request.open(method, origin + path);
        request.setRequestHeader("x-t3-orchestration-protocol", "2");
        if (accessToken)
            request.setRequestHeader("Authorization", "Bearer " + accessToken);
        let payload = null;
        if (body !== null && body !== undefined) {
            request.setRequestHeader("Content-Type", "application/json");
            payload = JSON.stringify(body);
        }
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            let parsed = request.responseText;
            try {
                parsed = JSON.parse(parsed);
            } catch (error) {}
            done(request.status, parsed);
        };
        request.send(payload);
    }

    // ---- session ---------------------------------------------------------------

    readonly property string gone: local ? "No T3 Code server is running." : `${label || origin} does not answer.`

    // `quiet`: asked by the shell itself, not by the user opening the panel.
    // Then nothing is paired; it only looks whether the server is there and
    // still knows the stored token.
    function checkSession(quiet) {
        if (origin === "" || status === "pairing" || status === "connecting")
            return;
        http("GET", "/api/auth/session", null, (code, body) => {
            if (code === 0)
                lost(gone);
            else if (paired && code === 200 && body?.authenticated)
                becomeReady();
            else {
                setStatus("idle", "");
                if (!quiet)
                    unpaired();
            }
        });
    }

    // The server does not answer: nothing known about any of its threads is
    // true any more. Asked again when the Ai singleton says so (the local
    // server's runtime file has changed, the panel opens) or a minute has
    // passed.
    function lost(text) {
        ready = false;
        socket.active = false;
        setStatus("offline", text);
        threads = [];
    }

    Timer {
        interval: 60000
        repeat: true
        running: link.paired && link.status === "offline"
        onTriggered: link.checkSession(true)
    }

    // Paired before: the threads are worth watching from the shell's start,
    // and from the moment the shell is paired.
    function retry() {
        retrySoon.restart();
    }

    Timer {
        id: retrySoon

        interval: 1500
        running: true
        onTriggered: {
            if (link.paired && !link.ready)
                link.checkSession(true);
        }
    }

    onAccessTokenChanged: {
        if (accessToken !== "")
            retrySoon.restart();
    }

    function becomeReady() {
        if (status !== "ready")
            setStatus("connecting", "Loading projects and threads…");
        loadShell(() => {
            ready = true;
            setStatus("ready", "");
            connectSocket();
        });
    }

    // ---- data ---------------------------------------------------------------

    // The projects and every thread, over HTTP: once at the start, and again
    // only if the socket's own list of them should not come (see
    // subscribeShell()).
    function loadShell(done) {
        http("GET", "/api/projects", null, (code, body) => {
            if (code === 200 && Array.isArray(body?.projects))
                projects = mark(body.projects.filter(candidate => !candidate.deletedAt));
            http("GET", "/api/orchestration/shell", null, (code2, body2) => {
                if (code2 === 0) {
                    lost(gone);
                    return;
                }
                if (code2 === 200 && Array.isArray(body2?.threads))
                    threads = mark(body2.threads);
                done?.();
            });
        });
    }

    // one thread whole; `done` gets its projection, or nothing
    function fetchThread(id, done) {
        // a subagent's thread has an id with colons and per cent signs in it
        http("GET", "/api/orchestration/threads/" + encodeURIComponent(id), null, (code, body) => {
            const next = body?.projection;
            done(code === 200 && next?.thread?.id === id ? next : null);
        });
    }

    // ---- the socket: commands and streams -----------------------------------

    property int rpcSeq: 0
    property var rpcPending: ({})

    WebSocket {
        id: socket

        onTextMessageReceived: message => {
            let frame;
            try {
                frame = JSON.parse(message);
            } catch (error) {
                return;
            }
            const entry = link.rpcPending[String(frame.requestId)];
            if (frame._tag === "Chunk") {
                // A stream sends its next chunk only once this one has been
                // acknowledged. Without the Ack a stream is its first chunk
                // and then silence, which is what this panel first had:
                // every thread as it was when it was opened.
                socket.sendTextMessage(JSON.stringify({
                    _tag: "Ack",
                    requestId: frame.requestId
                }));
                entry?.chunk?.(frame.values ?? []);
            } else if (frame._tag === "Exit") {
                delete link.rpcPending[String(frame.requestId)];
                entry?.exit?.(frame.exit);
            } else if (frame._tag === "Ping") {
                socket.sendTextMessage(JSON.stringify({
                    _tag: "Pong"
                }));
            }
        }
        onStatusChanged: {
            if (socket.status === WebSocket.Open) {
                link.subscribeShell();
                if (link.watched)
                    link.subscribeThread(link.watched);
            } else if (socket.status === WebSocket.Error || socket.status === WebSocket.Closed) {
                socket.active = false;
                link.rpcPending = {};
                link.threadStream = "";
                link.shellStream = "";
                if (link.ready)
                    reconnect.restart();
            }
        }
    }

    Timer {
        id: reconnect

        interval: 3000
        onTriggered: link.connectSocket()
    }

    function connectSocket() {
        if (socket.active || !accessToken)
            return;
        http("POST", "/api/auth/websocket-ticket", {}, (code, body) => {
            if (code === 0) {
                lost(local ? "The T3 Code server has gone." : gone);
                return;
            }
            if (code !== 200 || !body?.ticket) {
                if (code === 401 || code === 403) {
                    ready = false;
                    setStatus("idle", "");
                    threads = [];
                    refused();
                } else if (ready)
                    reconnect.restart();
                return;
            }
            if (socket.active)
                return;
            socket.url = origin.replace(/^http/, "ws") + "/ws?orchestrationProtocol=2&wsTicket=" + encodeURIComponent(body.ticket);
            socket.active = true;
        });
    }

    // One RPC request. `onChunk` (optional) makes it a stream that stays
    // registered until it ends or is interrupted; the return value is the
    // request id.
    function rpc(tag, payload, onExit, onChunk) {
        if (socket.status !== WebSocket.Open) {
            connectSocket();
            onExit?.({
                _tag: "Failure"
            });
            return "";
        }
        const id = String(++rpcSeq);
        rpcPending[id] = {
            exit: onExit,
            chunk: onChunk
        };
        socket.sendTextMessage(JSON.stringify({
            _tag: "Request",
            id: id,
            tag: tag,
            payload: payload,
            headers: []
        }));
        return id;
    }

    function command(payload, done) {
        return rpc("orchestration.dispatchCommand", Object.assign({
            commandId: uuid()
        }, payload), done);
    }

    property string shellStream: ""
    property string threadStream: ""
    // the thread whose stream is wanted, also across a new socket
    property string watched: ""

    // Every thread in short, and each change to one as it happens.
    function subscribeShell() {
        if (shellStream || socket.status !== WebSocket.Open)
            return;
        shellStream = rpc("orchestration.subscribeShell", {}, exit => {
            // the stream ended: the threads are asked for now and then instead
            shellStream = "";
        }, values => {
            let next = null;
            for (const value of values) {
                // what is in T3's archive is not listed here
                const archive = value?.location === "archive";
                if (value?.kind === "snapshot" && value.snapshot) {
                    // The first snapshot is followed by a second that only
                    // says which projects' repositories are known by now,
                    // and has no threads in it: not a list of the threads.
                    if (value.resolvedRepositoryIdentityRoots !== undefined)
                        continue;
                    if (Array.isArray(value.snapshot.projects))
                        projects = mark(value.snapshot.projects.filter(candidate => !candidate.deletedAt));
                    next = mark(value.snapshot.threads ?? []);
                } else if (value?.kind === "thread.updated" && value.thread) {
                    next = (next ?? threads).filter(thread => thread.id !== value.thread.id).concat(archive ? [] : mark([value.thread]));
                } else if (value?.kind === "thread.removed" && !archive) {
                    next = (next ?? threads).filter(thread => thread.id !== value.threadId);
                } else if (value?.kind === "project.updated" && value.project) {
                    projects = projects.filter(candidate => candidate.id !== value.project.id).concat(value.project.deletedAt ? [] : mark([value.project]));
                } else if (value?.kind === "project.removed") {
                    projects = projects.filter(candidate => candidate.id !== value.projectId);
                }
            }
            if (next !== null)
                threads = next;
        });
    }

    // One thread whole, then what happens in it, as threadValues(); "" for
    // none.
    function subscribeThread(id) {
        if (threadStream) {
            socket.sendTextMessage(JSON.stringify({
                _tag: "Interrupt",
                requestId: threadStream
            }));
            delete rpcPending[threadStream];
            threadStream = "";
        }
        watched = id;
        if (!id)
            return;
        if (socket.status !== WebSocket.Open) {
            connectSocket();
            return;
        }
        threadStream = rpc("orchestration.subscribeThread", {
            threadId: id
        }, exit => {
            // the stream ended (the thread is gone)
            if (watched === id)
                threadStream = "";
        }, values => {
            if (watched !== id)
                return;
            threadValues(id, values);
            // without the shell's stream, a thread's title and state in the
            // list are only as new as the last time they were asked for
            if (!shellStream)
                shellRefresh.restart();
        });
    }

    Timer {
        id: shellRefresh

        interval: 1200
        onTriggered: link.loadShell(null)
    }
}
