pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The panel that slides down from the top frame edge, and its two uses: the
// clipboard history (Klipper's entries, text and images, filtered by what is
// typed; Enter puts one back on the clipboard) and the theme switcher
// (picker/ThemePicker.qml). State and logic are here; the clipboard's panel
// is palette/PalettePanel.qml, shown by the Frame. Open them with
//   qs ipc -p <config> call palette clipboard
//   qs ipc -p <config> call palette themes
// or with their shortcuts (see Hotkeys.qml).
//
// The name is from what it was until 2026-10-12, a command palette: KRunner's
// search in this panel. That is the launcher's now (Launcher.qml), where
// typing searches. (Not called Palette: QtQuick has a type of that name.)
Singleton {
    id: root

    property bool open: false
    // the screen whose frame shows it; null means every screen's
    property var screen: null
    property string query: ""
    // "clipboard" lists the clipboard history; "themes" is the theme
    // switcher (picker/ThemePicker.qml), which has the panel to itself
    property string mode: "clipboard"
    readonly property bool clipboardMode: mode === "clipboard"
    readonly property bool themesMode: mode === "themes"

    function show(onScreen, text, inMode) {
        screen = onScreen ?? Quickshell.screens[0] ?? null;
        Popouts.close();
        Launcher.hide();
        Ai.hide();
        Notifications.listOpen = false;
        clips = [];
        mode = inMode ?? "clipboard";
        query = text ?? "";
        open = true;
        if (clipboardMode)
            loadClips();
    }

    function hide() {
        open = false;
    }

    // opens in that mode, or closes if it is showing it
    function toggleMode(inMode) {
        if (open && mode === inMode)
            hide();
        else
            show(null, "", inMode);
    }

    onQueryChanged: {
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

        // not "hide": see the Launcher's handler
        function close(): void {
            root.hide();
        }

        function clipboard(): void {
            root.toggleMode("clipboard");
        }

        function themes(): void {
            root.toggleMode("themes");
        }

        function mode(): string {
            return root.mode;
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

    // What the panel lists: the clipboard's entries. Each has key (its
    // identity, to find it again in the next list), title, subtitle, icon
    // and, if it is an image, the file to show as `image`.
    readonly property var results: clips.map(clip => {
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
            uuid: clip.uuid,
            title: image !== "" ? "Image" : line,
            subtitle: detail,
            icon: image !== "" ? "image-x-generic-symbolic" : "edit-paste-symbolic",
            image: image
        };
    })

    // Enter or a click on row `index`
    function submit(index) {
        const result = results[index];
        if (!result)
            return;
        Quickshell.execDetached(["sh", Quickshell.shellPath("clipboard.sh"), "copy", result.uuid]);
        hide();
    }
}
