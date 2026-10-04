pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The command palette: KRunner's search in the shell's own panel, sliding
// down from the top frame edge. State and logic are here; the panel is
// palette/PalettePanel.qml, shown by the Frame. (Not called Palette: QtQuick
// has a type of that name.) Open it with
//   qs ipc -p <config> call palette toggle
// (bind that to a key in System Settings > Shortcuts), or with a query
// already typed: `call palette search "> "`.
//
// Typing searches with every runner plugin enabled in System Settings >
// Search > KRunner: apps, windows, settings, files, calculator, units, web
// shortcuts and so on. ">" lists the shell's own actions.
//
// It has a second mode, the clipboard history: Klipper's entries, text and
// images, filtered by what is typed; Enter puts one back on the clipboard.
// `call palette clipboard`, or its own shortcut (see Hotkeys.qml).
Singleton {
    id: root

    property bool open: false
    // the screen whose frame shows it; null means every screen's
    property var screen: null
    property string query: ""
    // "" searches; "clipboard" lists the clipboard history
    property string mode: ""
    readonly property bool clipboardMode: mode === "clipboard"

    function show(onScreen, text, inMode) {
        screen = onScreen ?? Quickshell.screens[0] ?? null;
        Popouts.close();
        Launcher.hide();
        runner.active = true;
        clips = [];
        mode = inMode ?? "";
        query = text ?? "";
        open = true;
        if (clipboardMode)
            loadClips();
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

    // opens in that mode, or closes if it is showing it
    function toggleMode(inMode) {
        if (open && mode === inMode)
            hide();
        else
            show(null, "", inMode);
    }

    onOpenChanged: pendingRun = false
    onQueryChanged: {
        pendingRun = false;
        if (open && clipboardMode)
            loadClips();
    }

    IpcHandler {
        target: "palette"

        // state for scripts and tests: `qs ipc call palette isOpen`. (Functions, not
        // properties: those make Quickshell warn about their change signals
        // on every load.)
        function isOpen(): bool {
            return root.open;
        }

        function query(): string {
            return root.query;
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

        function search(text: string): void {
            root.show(null, text);
        }

        function clipboard(): void {
            root.toggleMode("clipboard");
        }
    }

    // ---- KRunner ---------------------------------------------------------

    // Created on first use and kept, so the runner plugins load once.
    Loader {
        id: runner

        active: false
        source: Qt.resolvedUrl("palette/Runner.qml")
    }

    readonly property var backend: runner.item
    // org.kde.milou is missing or no longer loads here
    readonly property bool backendFailed: runner.status === Loader.Error
    readonly property bool shellMode: mode === "" && query.trim().startsWith(">")
    readonly property bool runnerMode: mode === "" && !shellMode
    // results for the typed query are still on their way
    readonly property bool waiting: runnerMode && backend !== null && !backend.fresh
    readonly property bool querying: runnerMode && backend !== null && (backend.querying || !backend.fresh)

    Binding {
        target: root.backend
        property: "query"
        value: root.runnerMode ? root.query : ""
        when: root.backend !== null
    }

    Connections {
        target: root.backend

        function onQueryRequested(text) {
            root.query = text;
        }

        // Enter was pressed before the results arrived: run the first one now
        function onFreshChanged() {
            if (!root.backend.fresh || !root.pendingRun)
                return;
            root.pendingRun = false;
            if (root.open && root.results.length > 0)
                root.activate(root.results[0], 0, -1);
        }
    }

    // ---- clipboard history -----------------------------------------------

    // Klipper's entries matching the query, most recently used first, as
    // clipboard.sh lists them. Read again for every change of the query: the
    // search runs over the whole text of every entry, in Klipper's store.
    property var clips: []
    // only the answer to the latest request counts
    property int clipRequest: 0

    Component {
        id: clipLister

        Process {
            id: lister

            required property int request

            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    if (lister.request === root.clipRequest) {
                        try {
                            root.clips = text.trim() === "" ? [] : JSON.parse(text);
                        } catch (error) {
                            console.warn("CommandPalette: unreadable clipboard list:", error);
                            root.clips = [];
                        }
                    }
                    lister.destroy();
                }
            }
        }
    }

    function loadClips() {
        clipLister.createObject(root, {
            request: ++clipRequest,
            command: ["sh", Quickshell.shellPath("clipboard.sh"), "list"].concat(query.trim().split(/\s+/).filter(word => word))
        });
    }

    // "5 min ago" for a time in seconds since the epoch
    function ago(time) {
        const seconds = Date.now() / 1000 - time;
        if (seconds < 60)
            return "just now";
        if (seconds < 3600)
            return Math.floor(seconds / 60) + " min ago";
        if (seconds < 86400)
            return Math.floor(seconds / 3600) + " h ago";
        const days = Math.floor(seconds / 86400);
        return days === 1 ? "yesterday" : days + " days ago";
    }

    // ---- results ---------------------------------------------------------

    // What the panel lists. Each result has key (its identity, to find it
    // again in the next list),
    // kind, title, subtitle, icon, symbolic (recolour the icon), category
    // and actions (extra things it can do: text and icon each); a clipboard
    // entry that is an image also the file to show as `image`.
    readonly property var results: {
        const text = query.trim();

        if (clipboardMode)
            return clips.map(clip => {
                const image = clip.image ?? "";
                // the first line with something on it stands for the entry
                const line = (clip.text ?? "").split("\n").map(line => line.trim()).find(line => line !== "") ?? "";
                let detail = ago(clip.time);
                if (clip.lines > 1)
                    detail += ` · ${clip.lines} lines`;
                else if (clip.length > 80)
                    detail += ` · ${clip.length} characters`;
                return {
                    key: clip.uuid,
                    kind: "clip",
                    uuid: clip.uuid,
                    title: image !== "" ? "Image" : line,
                    subtitle: detail,
                    icon: image !== "" ? "image-x-generic-symbolic" : "edit-paste-symbolic",
                    symbolic: true,
                    category: "",
                    actions: [],
                    image: image
                };
            });

        // the shell's own actions, shared with the launcher
        if (shellMode) {
            const words = text.slice(1).toLowerCase().split(/\s+/).filter(word => word);
            return Launcher.actions.filter(action => words.every(word => action.title.toLowerCase().includes(word))).map(action => ({
                        key: "action\n" + action.title,
                        kind: "action",
                        title: action.title,
                        subtitle: action.subtitle,
                        icon: action.icon,
                        symbolic: true,
                        category: "Shell",
                        actions: [],
                        action: action
                    }));
        }

        return backend?.matches ?? [];
    }

    // Enter was pressed while results were still on their way
    property bool pendingRun: false

    // Enter or a click on row `index`; `action` >= 0 picks one of its actions.
    function submit(index, action) {
        if (waiting) {
            pendingRun = true;
            return;
        }
        activate(results[index], index, action);
    }

    function activate(result, index, action) {
        if (!result)
            return;
        if (result.kind === "clip") {
            Quickshell.execDetached(["sh", Quickshell.shellPath("clipboard.sh"), "copy", result.uuid]);
            hide();
        } else if (result.kind === "action") {
            hide();
            Launcher.runAction(result.action);
        } else if (result.kind === "match") {
            // The calculator and the unit converter only copy their answer.
            // They would do it through this process's clipboard; wl-copy is
            // the way that is known to work from here (see the Launcher).
            // As in KRunner, the converter's action copies the unit too.
            if (result.answer) {
                const number = /^[-+\d.,'\s]*\d/.exec(result.title);
                const bare = result.id === "unitconverter" && action < 0 && number;
                Quickshell.execDetached(["wl-copy", "--", bare ? number[0].trim() : result.title]);
                hide();
            } else if (backend.run(index, result.id, action)) {
                hide();
            }
        }
    }
}
