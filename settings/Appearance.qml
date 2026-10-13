import Quickshell
import Quickshell.Io
import QtQuick

// How the shell looks, as far as it is chosen here: whether the frame and its
// panels are glass, transparent with what is behind them blurred, and how
// transparent. They are `glass` and `transparency` in the file
// shell/Themes.qml keeps the choice of theme in, and reads again whenever it
// changes; the rest of that file is left as it is.
Scope {
    id: root

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kde-quickshell/theme.json"
    property bool glass: true
    // how much of what is behind the glass shows, 0.1 to 0.9
    property real transparency: 0.5
    // The file as it was last read or written here. Not read anew for each
    // change: the slider writes faster than the file is read back.
    property var all: ({})

    function set(key: string, value: var): void {
        const next = Object.assign({}, all);
        next[key] = value;
        all = next;
        file.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function setGlass(on: bool): void {
        glass = on;
        set("glass", on);
    }

    function setTransparency(value: real): void {
        transparency = Math.round(Math.max(0.1, Math.min(0.9, value)) * 100) / 100;
        set("transparency", transparency);
    }

    function read(): void {
        let stored = {};
        try {
            stored = JSON.parse(file.text()) ?? {};
        } catch (error) {
            // no file yet: nothing is chosen
        }
        all = stored;
        glass = stored.glass !== false;
        const given = stored.transparency;
        transparency = typeof given === "number" && isFinite(given) ? Math.max(0.1, Math.min(0.9, given)) : 0.5;
    }

    FileView {
        id: file

        path: root.path
        blockLoading: true
        // changed by the shell too, among its ">" actions
        watchChanges: true
        onFileChanged: reload()
        // no file until something is chosen
        printErrors: false
        onLoaded: root.read()
    }
}
