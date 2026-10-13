pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import QtQml

// A native client for T3 Code (the `t3` server), shown as the panel that
// drops from the top frame edge on Meta+Space (Frame.qml, ai/AiPanel.qml).
// Open it with the shortcut (Hotkeys.qml), a click on the notch that says
// how many threads are at work (ai/Notch.qml), or
//   qs ipc -p <config> call ai toggle
//
// Why native: T3's own UI is a web app, and a web view cannot live in this
// process (QtWebEngine/QtWebView crash Quickshell at startup, Chromium's
// "Argument list is empty"), so the panel speaks T3's protocol itself, which
// turns out to be plain HTTP + WebSocket JSON:
//
// - Auth: a one-time pairing token (minted by `t3 pair`, see ai.sh) is
//   exchanged at POST /oauth/token with client_label "kde quickshell" for a
//   bearer token (30 days). The exchange is what creates the authorized
//   client of that name in T3's settings; the token is kept in
//   ~/.config/kde-quickshell/ai.json (chmod 600) and reused until it expires,
//   so there is exactly one such client, not one per panel opening.
// - Reads: GET /api/projects, GET /api/orchestration/shell (every thread, in
//   short) and GET /api/orchestration/threads/<id> (one thread in full:
//   { snapshotSequence, projection: { thread, runs, turnItems, ... } }), all
//   with the bearer token and the header x-t3-orchestration-protocol: 2.
// - Writes and live updates: Effect RPC over ws://<origin>/ws — a short-lived
//   ticket from POST /api/auth/websocket-ticket goes in the query string, and
//   each request is {"_tag":"Request","id":...,"tag":...,"payload":...,
//   "headers":[]}; answers come back as "Chunk" (stream values, each to be
//   acknowledged with {"_tag":"Ack","requestId":...} before the next comes)
//   and "Exit".
//   Commands used: orchestration.launchThread, orchestration.dispatchCommand
//   (message.dispatch, run.interrupt, runtime-request.respond, thread.visit)
//   and two streams:
//   - orchestration.subscribeShell: { kind: "snapshot", snapshot: { projects,
//     threads } }, then { kind: "thread.updated", thread } and { kind:
//     "thread.removed", threadId } (and the same for projects). It is what
//     keeps the list of threads, the notch and the notifications right
//     while no thread is open.
//   - orchestration.subscribeThread: { kind: "snapshot", projection }, then
//     { kind: "event", event: { type, payload } }. A "turn-item.updated"
//     carries the item whole and is put in place as it comes, which is what
//     makes an answer appear as it is written. Every other event only asks
//     for the thread over HTTP again: the projection is the truth, and
//     refetching keeps this client small against an alpha protocol.
//
// The server is the user's own (desktop app or `t3 serve`); its origin comes
// from <t3 data>/userdata/server-runtime.json, rewritten on loopback. If
// nothing answers, the panel offers to start `t3 serve` (see startServer()).
//
// Once paired, the shell keeps the connection while the server is there,
// also with the panel closed: a run that ends or waits for an answer is
// worth knowing about then. A shell that was never paired asks nothing.
//
// There can be more servers than this machine's: T3 Code's own window shows
// the threads of other machines beside the local ones ("environments"), each
// a server of its own that it is paired with. Its pairings are not ours to
// use (they are kept encrypted), so the shell is paired with such a server
// itself, once: `t3 pair` there, then
//   qs ipc -p <config> call ai pair http://<host>:3773 <token>
// Each server is an AiLink; the threads and projects here are all of them
// together, each marked with the server it is of.
Singleton {
    id: root

    property bool open: false
    // the screen whose frame shows it; null means every screen's
    property var screen: null
    // what the panel shows: "home" (composer and threads) or "thread"
    property string page: "home"

    function show(onScreen) {
        screen = onScreen ?? Quickshell.screens[0] ?? null;
        Popouts.close();
        Launcher.hide();
        CommandPalette.hide();
        Notifications.listOpen = false;
        open = true;
        ensureReady();
    }

    function hide() {
        open = false;
    }

    function toggle(onScreen) {
        if (open)
            hide();
        else
            show(onScreen);
    }

    // Opens the panel on one thread: a notification's click.
    function view(id) {
        if (!threads.some(thread => thread.id === id))
            return;
        openThread(id);
        if (!open)
            show(null);
    }

    IpcHandler {
        target: "ai"

        function isOpen(): bool {
            return root.open;
        }

        function toggle(): void {
            root.toggle(null);
        }

        // not "show"/"hide": see the Launcher's handler
        function open(): void {
            root.show(null);
        }

        function close(): void {
            root.hide();
        }

        function status(): string {
            return root.status + (root.statusText ? ": " + root.statusText : "");
        }

        // the projects T3 knows, one per line
        function projects(): string {
            return root.projects.map(project => project.title).join("\n");
        }

        // every thread as the panel lists them, one per line: state, id, title
        function threads(): string {
            return root.allThreads.map(thread => [root.kindOf(thread), thread.id, thread.title].join("\t")).join("\n");
        }

        // how many threads are waiting for the user, at work, and finished
        // without having been looked at (the notch has the second, and the
        // first and third together)
        function counts(): string {
            return [root.waitingCount, root.runningCount, root.doneCount].join(" ");
        }

        function thread(): string {
            return root.page === "thread" ? root.threadId : "";
        }

        // which of the streams are up ("shell", "thread"), for each server
        function streams(): string {
            return root.links.map(link => link.key + ": " + [link.shellStream ? "shell" : "", link.threadStream ? "thread" : ""].filter(name => name).join(" ")).join("\n");
        }

        // the servers: key, name, address and state of each, one per line
        function environments(): string {
            return root.links.map(link => [link.key, link.label, link.origin, link.status + (link.statusText ? ": " + link.statusText : "")].join("\t")).join("\n");
        }

        // Pairs the shell with another machine's server: its address, and a
        // token from `t3 pair` run there. How that went: pairing().
        function pair(origin: string, token: string): void {
            root.pairWith(origin, token);
        }

        function pairing(): string {
            return root.pairing;
        }

        // forgets a server paired that way, by its key
        function forget(key: string): void {
            root.forget(key);
        }

        // the panel on this thread, as a click on it in the list
        function view(id: string): void {
            root.view(id);
        }

        // back to the composer and the list
        function home(): void {
            root.page = "home";
        }

        // the open thread's last rows as text, for scripts and tests (capped:
        // a long thread's whole history is more than IPC should carry)
        function messages(): string {
            return root.rowList.slice(-50).map(row => row.kind + ": " + (row.text || row.last).slice(0, 500)).join("\n");
        }

        // The project a new thread is started in, by its title, and how
        // much such a thread may do unasked (one of Ai.runtimeModes' ids),
        // as the composer's selectors; each answers with what is in use.
        function project(title: string): string {
            const found = root.projects.find(candidate => candidate.title === title);
            if (found)
                root.projectId = found.id;
            return root.project?.title ?? "";
        }

        function access(mode: string): string {
            if (root.runtimeModes.some(candidate => candidate.id === mode))
                root.runtimeMode = mode;
            return root.runtimeMode;
        }

        // as the composer: a follow-up in the open thread, else a new thread
        function send(text: string): string {
            root.send(text);
            return root.threadId;
        }
    }

    // ---- where T3 lives ---------------------------------------------------

    readonly property string home: Quickshell.env("HOME")
    readonly property string t3Home: Quickshell.env("T3CODE_HOME") || ((Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/t3")
    readonly property string userdata: t3Home + "/userdata"

    // written by the running server; host may be 0.0.0.0, the panel only ever
    // talks to loopback
    property int serverPort: 3773
    readonly property string origin: "http://127.0.0.1:" + serverPort

    FileView {
        path: root.userdata + "/server-runtime.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const port = JSON.parse(text())?.port;
                if (port)
                    root.serverPort = port;
            } catch (error) {}
            // a server has just started: it writes this before it listens
            localLink.retry();
        }
    }

    // the user's favourite provider/models in T3, what the composer's model
    // picker offers; the first is the default for a new thread
    property var favorites: []
    readonly property var favorite: favorites[0] ?? null

    FileView {
        path: root.userdata + "/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.favorites = JSON.parse(text())?.favorites ?? [];
            } catch (error) {}
        }
    }

    // what T3 calls its models ("claude-fable-5-1": "Claude Fable 5.1"), from
    // the list it keeps of them
    property var modelNames: ({})

    FileView {
        path: root.userdata + "/model-manifest.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const names = {};
                const providers = JSON.parse(text())?.manifest?.providers ?? {};
                for (const provider in providers)
                    for (const model of providers[provider].models ?? [])
                        if (model.slug && model.name)
                            names[model.slug] = model.name;
                root.modelNames = names;
            } catch (error) {}
        }
    }

    // A model's name to show: T3's own, else made from the id.
    function modelName(model) {
        const id = String(model ?? "");
        if (id in modelNames)
            return modelNames[id];
        return id.replace(/(\d)-(?=\d)/g, "$1.").split("-").map(word => word === "gpt" ? "GPT" : word.charAt(0).toUpperCase() + word.slice(1)).join(" ");
    }

    // ---- what a new thread starts with (the composer's selectors) -----------

    // Index into `favorites`; the effort and access mode beside it. All three
    // are remembered in ai.json. Effort is a provider option whose name
    // depends on the provider (codex: reasoningEffort, claude: effort), and
    // is left out for providers that do not take one. They are for a new
    // thread only: a follow-up goes out with what its thread has.
    property int modelIndex: 0
    property string effort: "medium"
    property string runtimeMode: "full-access"
    readonly property var effortChoices: [
        {
            id: "low",
            label: "Low"
        },
        {
            id: "medium",
            label: "Medium"
        },
        {
            id: "high",
            label: "High"
        },
        {
            id: "xhigh",
            label: "Extra high"
        }
    ]
    readonly property var runtimeModes: [
        {
            id: "approval-required",
            label: "Ask first",
            note: "Every command and edit waits for an answer"
        },
        {
            id: "auto-accept-edits",
            label: "Auto edits",
            note: "Edits go through, commands wait"
        },
        {
            id: "auto",
            label: "Auto",
            note: "Only what looks risky waits"
        },
        {
            id: "full-access",
            label: "Full access",
            note: "Nothing waits"
        }
    ]
    readonly property string effortLabel: (effortChoices.find(choice => choice.id === effort) ?? effortChoices[1]).label

    function runtimeLabel(mode) {
        return (runtimeModes.find(candidate => candidate.id === mode) ?? runtimeModes[3]).label;
    }

    readonly property var modelSelection: {
        const picked = favorites[modelIndex] ?? favorite;
        let selection = picked ? {
            instanceId: picked.provider,
            model: picked.model
        } : defaultModel();
        const effortId = selection.instanceId.includes("codex") || selection.instanceId.includes("grok") ? "reasoningEffort" : (selection.instanceId.includes("claude") ? "effort" : "");
        if (effortId)
            selection = Object.assign({}, selection, {
                options: [{
                    id: effortId,
                    value: effort
                }]
            });
        return selection;
    }

    // ---- the stored pairing ----------------------------------------------

    // { accessToken, expiresAt (epoch ms), projectId, modelIndex, effort,
    // runtimeMode, environments } in ~/.config/kde-quickshell/ai.json, made
    // private (600) after every write: a token drives agents with the user's
    // rights. `environments` are the other machines' servers: [{ key (the
    // server's environment id), label, origin, accessToken, expiresAt }].
    property string accessToken: ""
    property real tokenExpiresAt: 0
    property var remotes: []
    property string savedProjectId: ""
    // nothing is written before the file has been read
    property bool storeRead: false

    FileView {
        id: storeFile

        path: (Quickshell.env("XDG_CONFIG_HOME") || root.home + "/.config") + "/kde-quickshell/ai.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const stored = JSON.parse(text());
                root.accessToken = stored.accessToken ?? "";
                root.tokenExpiresAt = stored.expiresAt ?? 0;
                root.savedProjectId = stored.projectId ?? "";
                root.modelIndex = stored.modelIndex ?? 0;
                root.effort = stored.effort ?? "medium";
                root.runtimeMode = stored.runtimeMode ?? "full-access";
                root.remotes = Array.isArray(stored.environments) ? stored.environments : [];
            } catch (error) {}
            root.storeRead = true;
            // an older store may still be world-readable
            chmodStore.restart();
        }
        onLoadFailed: root.storeRead = true
    }

    function saveStore() {
        if (!storeRead)
            return;
        storeFile.setText(JSON.stringify({
            accessToken: accessToken,
            expiresAt: tokenExpiresAt,
            projectId: projectId,
            modelIndex: modelIndex,
            effort: effort,
            runtimeMode: runtimeMode,
            environments: remotes
        }, null, 2) + "\n");
        // FileView writes in its own time; tighten the permissions after
        chmodStore.restart();
    }

    Timer {
        id: chmodStore

        interval: 600
        onTriggered: Quickshell.execDetached(["chmod", "600", storeFile.path])
    }

    // ---- state ------------------------------------------------------------

    // What the panel says of the connection is this machine's server's:
    // idle (not asked yet), offline (no server), pairing, connecting, ready.
    // Or "error", with what went wrong with something the user did, until
    // that is dismissed or the next thing goes right.
    property string complaint: ""
    readonly property string status: complaint !== "" ? "error" : localLink.status
    readonly property string statusText: complaint !== "" ? complaint : localLink.statusText
    readonly property bool ready: localLink.ready
    // every server's, each marked with its server (`environment`)
    readonly property var projects: links.reduce((all, link) => all.concat(link.projects), [])
    readonly property var threads: links.reduce((all, link) => all.concat(link.threads), [])
    property string projectId: ""
    property string threadId: ""
    property var projection: null

    onProjectsChanged: chooseProject()
    onThreadsChanged: note(threads)

    // ---- the servers ------------------------------------------------------------

    AiLink {
        id: localLink

        key: "local"
        label: "This machine"
        origin: root.origin
        accessToken: root.accessToken
        tokenExpiresAt: root.tokenExpiresAt
        // the user is asking, and for this one a token can be had
        onUnpaired: root.pair()
        onRefused: {
            root.accessToken = "";
            if (root.open)
                checkSession(false);
        }
        onThreadValues: (id, values) => root.threadValues(id, values)
    }

    readonly property var remoteKeys: remotes.map(remote => remote.key)
    property var remoteLinks: []

    Instantiator {
        model: root.remoteKeys
        delegate: AiLink {
            required property string modelData
            readonly property var entry: root.remotes.find(remote => remote.key === modelData) ?? null

            key: modelData
            label: entry?.label ?? ""
            origin: entry?.origin ?? ""
            accessToken: entry?.accessToken ?? ""
            tokenExpiresAt: entry?.expiresAt ?? 0
            onThreadValues: (id, values) => root.threadValues(id, values)
        }
        onObjectAdded: (index, object) => root.remoteLinks = root.remoteLinks.concat([object])
        onObjectRemoved: (index, object) => root.remoteLinks = root.remoteLinks.filter(one => one !== object)
    }

    readonly property var links: [localLink].concat(remoteLinks)

    // the server of that key; this machine's for none
    function linkOf(environment) {
        return links.find(link => link.key === environment) ?? localLink;
    }

    // what to call a thread's or a project's server beside it: nothing for
    // this machine's
    function environmentLabel(environment) {
        return environment && environment !== "local" ? (linkOf(environment).label || "elsewhere") : "";
    }

    // How the last pairing with another machine's server went, for the one
    // who asked (`ai pairing`).
    property string pairing: ""

    function pairWith(address, pairingToken) {
        const at = String(address).trim().replace(/\/+$/, "");
        pairing = "asking " + at;
        // the server says who it is without being asked for a token
        const request = new XMLHttpRequest();
        request.open("GET", at + "/.well-known/t3/environment");
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            let who = null;
            try {
                who = JSON.parse(request.responseText);
            } catch (error) {}
            if (request.status !== 200 || !who?.environmentId) {
                pairing = "failed: no T3 Code server answers at " + at;
                return;
            }
            exchangeAt(at, pairingToken, (token, expiresAt) => {
                if (!token) {
                    pairing = "failed: " + (who.label ?? at) + " refused the token";
                    return;
                }
                remotes = remotes.filter(remote => remote.key !== who.environmentId).concat([{
                        key: who.environmentId,
                        label: who.label ?? at,
                        origin: at,
                        accessToken: token,
                        expiresAt: expiresAt
                    }]);
                saveStore();
                pairing = "paired with " + (who.label ?? at);
            });
        };
        request.send();
    }

    function forget(key) {
        remotes = remotes.filter(remote => remote.key !== key);
        saveStore();
    }

    readonly property var project: projects.find(candidate => candidate.id === projectId) ?? null
    readonly property var thread: threads.find(candidate => candidate.id === threadId) ?? null

    function projectTitle(id) {
        return projects.find(candidate => candidate.id === id)?.title ?? "";
    }

    onProjectIdChanged: {
        if (ready && projectId && projectId !== savedProjectId) {
            savedProjectId = projectId;
            saveStore();
        }
    }
    onModelIndexChanged: {
        if (ready)
            saveStore();
    }
    onEffortChanged: {
        if (ready)
            saveStore();
    }
    onRuntimeModeChanged: {
        if (ready)
            saveStore();
    }

    // ---- what a thread is up to ---------------------------------------------

    readonly property var settled: ["idle", "completed", "failed", "cancelled", "interrupted", "rolled_back"]

    // A thread's last run has ended since the thread was last looked at, in
    // T3's own window or here. As T3 has it, with one difference: a thread
    // never looked at counts as unseen there only once it is visited, and
    // here a thread is visited the moment it is started (see newThread()).
    function unseen(thread) {
        const ended = Date.parse(thread.latestRunCompletedAt ?? "");
        if (isNaN(ended) || !thread.lastVisitedAt)
            return false;
        const visited = Date.parse(thread.lastVisitedAt);
        return isNaN(visited) || ended > visited;
    }

    // waiting (for an approval, an answer, a plan to be accepted), running,
    // background (its run has ended, but a subagent, a command or a monitor
    // it started is still going: T3's own window says "waiting" then), done
    // or failed (ended, and not looked at since), or idle
    function kindOf(thread) {
        if (!thread)
            return "idle";
        if (thread.pendingRuntimeRequest || thread.hasActionableProposedPlan)
            return "waiting";
        if (thread.activeRunId || !settled.includes(thread.status ?? "idle"))
            return "running";
        if ((thread.pendingBackgroundTasks ?? []).length > 0)
            return "background";
        if (!unseen(thread))
            return "idle";
        return thread.status === "failed" ? "failed" : "done";
    }

    function when(thread) {
        return String(thread.latestRunRequestedAt ?? thread.latestUserMessageAt ?? thread.createdAt ?? "");
    }

    // Every thread of the user's own: the ones that wait for an answer
    // first, then the running ones, then what has ended unseen, then the
    // rest; each by last use. Not the threads agents start for their
    // subagents, which T3 lists too (seventeen of twenty, the day this was
    // written): those are their parent's business.
    readonly property var allThreads: {
        const rank = thread => ["waiting", "running", "background", "failed", "done"].indexOf(kindOf(thread)) + 1 || 6;
        return threads.filter(thread => !thread.archivedAt && !thread.deletedAt && !thread.lineage?.parentThreadId).sort((a, b) => rank(a) - rank(b) || when(b).localeCompare(when(a)));
    }
    readonly property int waitingCount: allThreads.filter(thread => kindOf(thread) === "waiting").length
    readonly property int runningCount: allThreads.filter(thread => ["running", "background"].includes(kindOf(thread))).length
    readonly property int doneCount: allThreads.filter(thread => ["done", "failed"].includes(kindOf(thread))).length
    // The two numbers in the frame's notch (ai/Notch.qml): how many threads
    // are at work, and how many it is the user's turn in: one that waits
    // for an answer, one that has ended and has not been looked at.
    readonly property int workingCount: runningCount
    readonly property int turnCount: waitingCount + doneCount

    // as the panel and the functions below say it: an error, or none
    function setStatus(next, text) {
        complaint = next === "error" ? (text ?? "") : "";
    }

    // ---- telling the user -----------------------------------------------------

    // What each thread was last seen doing, by id: a change is news. A
    // thread seen for the first time is not (the first list of a server's
    // threads, at the start or when it is back).
    property var known: ({})

    // The threads are replaced or one of them is: says what has changed for
    // the worse or the better, unless the user is looking at that thread.
    function note(next) {
        const kinds = {};
        for (const thread of next) {
            const kind = kindOf(thread);
            kinds[thread.id] = kind;
            const before = known[thread.id];
            if (before === undefined || before === kind || thread.lineage?.parentThreadId || (open && page === "thread" && threadId === thread.id))
                continue;
            if (kind === "waiting")
                notify(thread, thread.pendingRuntimeRequest ? "Waiting for your answer" : "A plan is ready", true);
            else if (before === "running" || before === "waiting") {
                if (thread.status === "completed")
                    notify(thread, "Finished", false);
                else if (thread.status === "failed")
                    notify(thread, "Failed", false);
            }
        }
        known = kinds;
    }

    // A notification whose click opens the panel on the thread (ai.sh).
    function notify(thread, title, urgent) {
        const where = [environmentLabel(thread.environment), projectTitle(thread.projectId)].filter(part => part).join(" · ");
        Quickshell.execDetached(["sh", Quickshell.shellPath("ai.sh"), "notify", String(Quickshell.processId), thread.id, urgent ? "critical" : "normal", title, (thread.title || "Untitled") + (where ? "\n" + where : "")]);
    }

    // ---- small helpers ------------------------------------------------------

    function uuid(): string {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, character => {
            const random = Math.floor(Math.random() * 16);
            return (character === "x" ? random : (random & 0x3 | 0x8)).toString(16);
        });
    }

    // ---- session: pair once, then reuse -------------------------------------

    // Asks every server, as far as that gets; safe to call on every opening.
    // This machine's is paired if it is not; another's only if it was.
    function ensureReady() {
        for (const link of links) {
            if (link.ready)
                link.connectSocket();
            else
                link.checkSession(link !== localLink);
        }
    }

    function checkSession(quiet) {
        complaint = "";
        localLink.checkSession(quiet);
    }

    // Starts the server headless on loopback, in its own systemd scope so it
    // outlives the shell, then keeps checking until it answers.
    function startServer() {
        complaint = "";
        localLink.setStatus("connecting", "Starting the T3 Code server…");
        const cli = t3Home + "/bin/t3";
        Quickshell.execDetached(["sh", "-c", 'if command -v systemd-run > /dev/null; then exec systemd-run --user --scope --quiet -- "$@"; else exec "$@"; fi', "sh", cli, "serve", "--host", "127.0.0.1", "--port", String(serverPort), home]);
        serverWait.restart();
    }

    Timer {
        id: serverWait

        interval: 1500
        repeat: true
        onTriggered: {
            localLink.http("GET", "/api/auth/session", null, (code, body) => {
                if (code !== 0) {
                    serverWait.stop();
                    localLink.setStatus("idle", "");
                    root.checkSession(false);
                }
            });
        }
    }

    // Mint a one-time token with T3's CLI (ai.sh) and exchange it, labelled
    // "kde quickshell". The stored bearer token is what later openings reuse.
    function pair() {
        localLink.setStatus("pairing", "Pairing with T3 Code…");
        pairProcess.running = true;
    }

    Process {
        id: pairProcess

        command: ["sh", Quickshell.shellPath("ai.sh"), "pair-token"]
        stdout: StdioCollector {
            onStreamFinished: {
                const token = text.trim();
                if (!token) {
                    localLink.setStatus("idle", "");
                    root.setStatus("error", "Could not mint a pairing token (is T3 Code installed?).");
                    return;
                }
                root.exchangeAt(root.origin, token, (access, expiresAt) => {
                    localLink.setStatus("idle", "");
                    if (!access) {
                        root.setStatus("error", "Pairing was refused by the T3 Code server.");
                        return;
                    }
                    root.accessToken = access;
                    root.tokenExpiresAt = expiresAt;
                    root.saveStore();
                    localLink.checkSession(true);
                });
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && localLink.status === "pairing") {
                localLink.setStatus("idle", "");
                root.setStatus("error", "Pairing failed: the t3 CLI did not run.");
            }
        }
    }

    // A one-time pairing token for a bearer token, at the server of that
    // address. `done` gets the token and when it runs out, or nothing.
    function exchangeAt(address, pairingToken, done) {
        const fields = {
            grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
            subject_token: pairingToken,
            subject_token_type: "urn:t3:params:oauth:token-type:environment-bootstrap",
            requested_token_type: "urn:ietf:params:oauth:token-type:access_token",
            client_label: "kde quickshell",
            client_device_type: "desktop",
            client_os: "Linux"
        };
        const request = new XMLHttpRequest();
        request.open("POST", address + "/oauth/token");
        request.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            let body = null;
            try {
                body = JSON.parse(request.responseText);
            } catch (error) {}
            if (request.status === 200 && body?.access_token)
                done(body.access_token, Date.now() + (body.expires_in ?? 0) * 1000);
            else
                done("", 0);
        };
        request.send(Object.entries(fields).map(([key, value]) => encodeURIComponent(key) + "=" + encodeURIComponent(value)).join("&"));
    }

    // ---- data ---------------------------------------------------------------

    // keep the stored choice while it still exists, else the project of the
    // most recently used thread
    function chooseProject() {
        if (projects.some(candidate => candidate.id === projectId))
            return;
        const recent = threads.slice().sort((a, b) => when(b).localeCompare(when(a)))[0];
        projectId = projects.some(candidate => candidate.id === savedProjectId) ? savedProjectId : (recent?.projectId ?? projects[0]?.id ?? "");
    }

    // The model a new thread starts with: the project's own default, else the
    // favourite from T3's settings, else the model of the project's newest
    // thread.
    function defaultModel() {
        if (project?.defaultModelSelection)
            return project.defaultModelSelection;
        if (favorite)
            return {
                instanceId: favorite.provider,
                model: favorite.model
            };
        const recent = allThreads.find(thread => thread.projectId === projectId);
        if (recent?.modelSelection)
            return recent.modelSelection;
        return {
            instanceId: "claudeAgent",
            model: ""
        };
    }

    // ---- the open thread --------------------------------------------------------

    // Its turn items by id, as the last projection had them and the stream
    // has changed them since, and the rows the panel shows for them: once as
    // a list for scripts, once as the model the panel's list draws. A row is
    //   key, kind (user, assistant, work, approval, question, error, notice),
    //   text, streaming, and for
    //   - work (what the agent did between two messages, in one row):
    //     summary in `text`, `last` (the step it is at), `steps` (all of
    //     them, as JSON: [{ kind, text }]), `live` (not finished)
    //   - approval and question: requestId, `pending` (not answered yet); a
    //     question has what is asked in `steps`, as JSON: [{ id, header,
    //     question, options: [{ label, description }], multi, answer }]
    // The model is changed row by row, never replaced: a list that is rebuilt
    // for every word of an answer loses its place and what is selected in it.
    property var items: ({})
    property var rowList: []
    readonly property ListModel rows: ListModel {}
    // a message has gone out and nothing has come back yet
    property bool sending: false
    // what a thread that is being started was asked, its title until it has one
    property string starting: ""
    // the server a thread that is being started is started on
    property string startingIn: "local"
    // the open thread's server
    readonly property var threadLink: linkOf(thread?.environment ?? startingIn)
    // whether the composers can send: a new thread to the chosen project's
    // server, a follow-up to the open thread's
    readonly property bool canStart: linkOf(project?.environment).ready
    readonly property bool canSend: threadLink.ready
    readonly property var liveRun: (projection?.runs ?? []).find(run => !settled.includes(run.status)) ?? null
    readonly property bool busy: sending || liveRun !== null || ["running", "waiting"].includes(kindOf(thread))

    // the end of the open thread is what to show: it has just been opened,
    // or the user has written in it
    signal showEnd

    function openThread(id) {
        page = "thread";
        if (id !== threadId || !projection) {
            clear(id);
            startingIn = threads.find(candidate => candidate.id === id)?.environment ?? "local";
            // the stream starts with the thread whole; asked for over HTTP
            // only if that does not come
            watch(id);
            refetchSoon.interval = 2500;
            refetchSoon.restart();
        }
        showEnd();
        visit(id, false);
    }

    function clear(id) {
        threadId = id;
        projection = null;
        items = {};
        sending = false;
        setRows([]);
    }

    // The open thread's stream, from its server; no other server has one.
    function watch(id) {
        for (const link of links)
            if (link !== threadLink && link.watched)
                link.subscribeThread("");
        threadLink.subscribeThread(id);
    }

    // what that stream sends (AiLink.threadValues)
    function threadValues(id, values) {
        if (id !== threadId)
            return;
        for (const value of values) {
            if (value?.kind === "snapshot" && value.projection)
                applyProjection(value.projection);
            else if (value?.kind === "event")
                applyEvent(value.event);
            else if (value?.kind === "unknown-event")
                refetchSoon.restart();
        }
        streamedAt = Date.now();
    }

    function refetchThread() {
        if (!threadId)
            return;
        const wanted = threadId;
        threadLink.fetchThread(wanted, next => {
            if (next && wanted === threadId)
                applyProjection(next);
        });
    }

    function applyProjection(next) {
        refetchSoon.stop();
        projection = next;
        const byId = {};
        for (const item of next.turnItems ?? [])
            byId[item.id] = item;
        items = byId;
        sending = false;
        rebuild();
    }

    // one item, as the stream sends it while the agent works
    function applyItem(item) {
        if (!item?.id || item.threadId !== threadId)
            return;
        items[item.id] = item;
        streamedAt = Date.now();
        rebuildSoon.start();
        // the run it belongs to is not known yet
        if (liveRun === null)
            refetchSoon.start();
    }

    // What the stream says has happened in the open thread. An item is put
    // in place, and so is a run (which is what says the agent is at work);
    // a message's text is in its item too. Anything else is not known here,
    // and the thread is asked for again once the stream has been quiet for
    // a moment: a long thread is megabytes, not something to fetch per event.
    function applyEvent(event) {
        const payload = event?.payload;
        switch (event?.type) {
        case "turn-item.updated":
            if (payload?.id)
                applyItem(payload);
            return;
        case "message.updated":
            return;
        case "run.updated":
        case "run.created":
            if (projection && payload?.id && payload.status) {
                const runs = (projection.runs ?? []).filter(run => run.id !== payload.id).concat([payload]);
                projection = Object.assign({}, projection, {
                    runs: runs
                });
                sending = false;
                return;
            }
        }
        refetchSoon.restart();
    }

    // a burst of items (an answer arriving word by word) is drawn once
    Timer {
        id: rebuildSoon

        interval: 50
        onTriggered: root.rebuild()
    }

    function rebuild() {
        rebuildSoon.stop();
        setRows(rowsOf(Object.values(items).sort((a, b) => (a.ordinal ?? 0) - (b.ordinal ?? 0))));
    }

    function setRows(next) {
        rowList = next;
        let same = 0;
        while (same < next.length && same < rows.count && rows.get(same).key === next[same].key) {
            const have = rows.get(same);
            for (const key in next[same])
                if (have[key] !== next[same][key])
                    rows.setProperty(same, key, next[same][key]);
            same++;
        }
        if (rows.count > same)
            rows.remove(same, rows.count - same);
        for (let at = same; at < next.length; at++)
            rows.append(next[at]);
    }

    function row(item, kind, text) {
        return {
            key: item.id,
            kind: kind,
            text: text,
            streaming: !!item.streaming,
            requestId: item.requestId ?? "",
            pending: false,
            last: "",
            steps: "",
            live: false
        };
    }

    // The items in order as rows: messages one each, and what lies between
    // two messages (thinking, commands, edits, searches) gathered into one.
    function rowsOf(list) {
        const out = [];
        let work = null;
        const close = () => {
            if (work)
                out.push(workRow(work));
            work = null;
        };
        for (const item of list) {
            const step = stepOf(item);
            if (step !== null) {
                if (step.text === "")
                    continue;
                if (work === null)
                    work = {
                        first: item,
                        steps: []
                    };
                work.steps.push(Object.assign(step, {
                    item: item
                }));
                continue;
            }
            let made = null;
            switch (item.type) {
            case "user_message":
                made = row(item, "user", item.text ?? "");
                break;
            case "assistant_message":
                made = row(item, "assistant", item.text ?? "");
                break;
            case "proposed_plan":
                made = row(item, "assistant", item.markdown ?? "");
                break;
            case "approval_request":
                made = row(item, "approval", item.prompt ?? "The agent asks for approval.");
                made.pending = !settled.includes(item.status) || thread?.pendingRuntimeRequest?.id === item.requestId;
                break;
            case "user_input_request":
                {
                    const given = item.questionAnswer?.answers ?? {};
                    const questions = (item.questions ?? []).map(question => ({
                                id: question.id ?? question.question ?? "",
                                header: question.header ?? "",
                                question: question.question ?? "",
                                options: (question.options ?? []).map(option => ({
                                            label: option.label ?? "",
                                            description: option.description ?? ""
                                        })),
                                multi: !!question.multiSelect,
                                answer: String(given[question.id ?? question.question] ?? "")
                            }));
                    made = row(item, "question", questions.map(question => question.question).join("\n") || "The agent asks a question.");
                    made.steps = JSON.stringify(questions);
                    made.pending = !settled.includes(item.status) || thread?.pendingRuntimeRequest?.id === item.requestId;
                }
                break;
            case "error":
                made = row(item, "error", [item.title ?? "Something went wrong", item.failure?.message ?? item.text ?? ""].filter(part => part).join(": "));
                break;
            case "system_notice":
                made = row(item, "notice", item.message ?? item.title ?? "");
                break;
            }
            if (made === null || (made.text === "" && !made.streaming))
                continue;
            close();
            out.push(made);
        }
        close();
        return out;
    }

    // One item as a step of the agent's work, { kind, text }; null for what
    // is a row of its own, and an empty text for what is not shown at all.
    function stepOf(item) {
        const first = text => String(text ?? "").trim().split("\n")[0];
        switch (item.type) {
        case "user_message":
        case "assistant_message":
        case "proposed_plan":
        case "approval_request":
        case "user_input_request":
        case "error":
        case "system_notice":
            return null;
        case "notification":
        case "checkpoint":
        case "run_interrupt_request":
            return {
                kind: "",
                text: ""
            };
        case "reasoning":
            return {
                kind: "thought",
                text: String(item.text ?? "").trim().replace(/\s*\n\s*/g, " ")
            };
        case "command_execution":
            // T3's own steps (preparing the workspace) come as commands too,
            // without an item of the provider's behind them
            if (!item.nativeItemRef)
                return {
                    kind: "note",
                    text: item.title || first(item.input)
                };
            return {
                kind: "command",
                text: first(item.input) + (item.exitCode ? ` (exit ${item.exitCode})` : "")
            };
        case "file_change":
            return {
                kind: "edit",
                text: within(item.fileName ?? item.title ?? "a file")
            };
        case "file_search":
            return {
                kind: "search",
                text: item.pattern ?? item.query ?? item.title ?? "files"
            };
        case "web_search":
            return {
                kind: "search",
                text: (item.patterns ?? [])[0] ?? item.query ?? item.title ?? "the web"
            };
        case "dynamic_tool":
            return {
                kind: "tool",
                text: within(item.title ?? item.toolName ?? "")
            };
        case "subagent":
            return {
                kind: "agent",
                text: [item.title ?? "", item.progress ?? ""].filter(part => part).join(" · ")
            };
        case "todo_list":
            return {
                kind: "todo",
                text: (item.steps ?? []).map(step => (step.status === "completed" ? "✓ " : "· ") + (step.title ?? step.text ?? "")).join("\n")
            };
        default:
            return {
                kind: "note",
                text: item.title ?? ""
            };
        }
    }

    // a path, as short as it can be said: in the thread's project, in the home
    function within(text) {
        const base = projects.find(candidate => candidate.id === (thread?.projectId ?? projectId))?.workspaceRoot ?? "";
        let short = String(text);
        if (base)
            short = short.split(base + "/").join("");
        return short.split(home + "/").join("~/");
    }

    function workRow(work) {
        const steps = work.steps;
        const count = kind => steps.filter(step => step.kind === kind).length;
        const some = (number, one, many) => number === 0 ? "" : number === 1 ? "1 " + one : number + " " + many;
        const last = steps[steps.length - 1];
        const from = Date.parse(work.first.startedAt ?? "");
        const to = Date.parse(last.item.completedAt ?? last.item.updatedAt ?? "");
        const seconds = isNaN(from) || isNaN(to) ? 0 : Math.round((to - from) / 1000);
        const took = seconds < 1 ? "" : seconds < 60 ? seconds + "s" : Math.floor(seconds / 60) + "m " + (seconds % 60) + "s";
        const made = row(work.first, "work", [some(count("command"), "command", "commands"), some(count("edit"), "edit", "edits"), some(count("search"), "search", "searches"), some(count("tool"), "tool call", "tool calls"), some(count("agent"), "subagent", "subagents")].filter(part => part).join(", ") || (count("thought") === steps.length ? "Thought" : some(steps.length, "step", "steps")));
        made.key = "work:" + work.first.id;
        if (took)
            made.text += " · " + took;
        made.last = (last.kind === "command" ? "$ " : "") + last.text.split("\n").pop();
        made.steps = JSON.stringify(steps.map(step => ({
                    kind: step.kind,
                    text: step.text
                })));
        made.live = !settled.includes(last.item.status) || !!last.item.streaming;
        made.streaming = false;
        return made;
    }

    // While a run is going and the stream below says nothing, the thread is
    // asked for again: an event may have been missed, or the stream be gone.
    property real streamedAt: 0

    Timer {
        interval: 3000
        repeat: true
        running: root.open && root.page === "thread" && root.busy && !!root.threadId
        onTriggered: {
            if (Date.now() - root.streamedAt > 2500)
                root.refetchThread();
        }
    }

    Timer {
        id: refetchSoon

        interval: 600
        onTriggered: {
            interval = 600;
            root.refetchThread();
        }
    }

    // ---- writing ------------------------------------------------------------

    // Sends `text`: as a new thread when none is open, else as the next
    // message of the open thread, with the model that thread has.
    function send(text) {
        const trimmed = text.trim();
        if (!trimmed)
            return;
        if (page !== "thread" || !threadId) {
            newThread(trimmed);
            return;
        }
        if (!canSend)
            return;
        complaint = "";
        sending = true;
        showEnd();
        threadLink.command({
            type: "message.dispatch",
            createdBy: "user",
            creationSource: "web",
            threadId: threadId,
            messageId: uuid(),
            text: trimmed,
            attachments: [],
            dispatchMode: liveRun !== null ? {
                type: "queue_after_active"
            } : {
                type: "start_immediately"
            }
        }, exit => {
            if (exit?._tag === "Success")
                refetchSoon.restart();
            else {
                sending = false;
                console.warn("Ai: message.dispatch rejected:", JSON.stringify(exit).slice(0, 400));
                setStatus("error", "The message was not accepted.");
            }
        });
    }

    function newThread(text) {
        if (!project) {
            setStatus("error", "Pick a project first.");
            return;
        }
        // on the project's server
        const link = linkOf(project.environment);
        if (!link.ready)
            return;
        // the thread is shown at once, empty; its id is ours to choose
        const id = uuid();
        page = "thread";
        clear(id);
        startingIn = link.key;
        sending = true;
        starting = text;
        showEnd();
        link.rpc("orchestration.launchThread", {
            commandId: uuid(),
            threadId: id,
            projectId: projectId,
            title: text.slice(0, 80),
            modelSelection: modelSelection,
            runtimeMode: runtimeMode,
            interactionMode: "default",
            workspaceStrategy: {
                type: "root"
            },
            initialMessage: {
                text: text,
                attachments: []
            }
        }, exit => {
            if (threadId !== id)
                return;
            if (exit?._tag !== "Success") {
                console.warn("Ai: launchThread rejected:", JSON.stringify(exit).slice(0, 400));
                clear("");
                page = "home";
                setStatus("error", "The thread could not be started.");
                return;
            }
            complaint = "";
            const made = exit.value?.threadId ?? id;
            threadId = made;
            // the list has it a moment later; until then, what is known
            if (exit.value?.projection?.thread && !threads.some(thread => thread.id === made))
                link.threads = link.threads.concat(link.mark([exit.value.projection.thread]));
            if (exit.value?.projection)
                applyProjection(exit.value.projection);
            else
                refetchThread();
            watch(made);
            // from now on, what the run does is news once it ends
            visit(made, true);
        });
    }

    function interrupt() {
        const run = thread?.activeRunId ?? liveRun?.id ?? "";
        if (!threadId || !run)
            return;
        threadLink.command({
            type: "run.interrupt",
            threadId: threadId,
            runId: run
        }, () => refetchSoon.restart());
    }

    // accept, acceptForSession, decline
    function respond(requestId, decision) {
        if (!threadId || !requestId)
            return;
        threadLink.command({
            type: "runtime-request.respond",
            threadId: threadId,
            requestId: requestId,
            decision: decision
        }, () => refetchSoon.restart());
    }

    // An answer to each of the agent's questions, by the question's id: one
    // of its options' labels, or words of the user's own.
    function answer(requestId, answers) {
        if (!threadId || !requestId)
            return;
        threadLink.command({
            type: "runtime-request.respond",
            threadId: threadId,
            requestId: requestId,
            answers: answers
        }, exit => {
            if (exit?._tag !== "Success") {
                console.warn("Ai: the answer was rejected:", JSON.stringify(exit).slice(0, 400));
                setStatus("error", "The answer was not accepted.");
            }
            refetchSoon.restart();
        });
    }

    // The thread has been looked at: T3 keeps that, and its own window shows
    // the thread as read too.
    // Without `always`, only if there is something unseen in it.
    property var visited: ({
            id: "",
            at: 0
        })

    function visit(id, always) {
        const seen = threads.find(candidate => candidate.id === id);
        if (!id || (!always && seen && seen.lastVisitedAt && !unseen(seen)))
            return;
        // said a moment ago
        if (visited.id === id && Date.now() - visited.at < 1000)
            return;
        visited = {
            id: id,
            at: Date.now()
        };
        linkOf(seen?.environment ?? startingIn).command({
            type: "thread.visit",
            threadId: id,
            visitedAt: new Date().toISOString()
        }, null);
    }

    // a run of the thread on show has ended while it was looked at (a
    // thread that is only being started is not known to the server yet)
    onBusyChanged: {
        if (!busy && open && page === "thread" && thread)
            visit(threadId, true);
    }
}
