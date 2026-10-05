pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// What the dock keeps about its icons, in a file:
//
// `pinned`: the applications pinned to the dock, as launcher addresses the
// way KDE's task list writes them ("applications:org.kde.dolphin.desktop").
// The task list (modules/Taskbar.qml) shows them where their application has
// no window, and changes the list when one is pinned or unpinned.
//
// `order`: the applications in the order of their icons, pinned or not,
// running or not, by the same kind of address. The taskbar puts its icons in
// this order, adds an application it has not seen at the end, and rewrites it
// when an icon is dragged. So an icon is where it was put: also after its
// application was closed and started again, and after a restart of the shell.
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kde-quickshell/dock.json"
    property list<string> pinned: []
    property list<string> order: []

    // The taskbar that must not be put away just now: an icon is being
    // dragged or its menu is open, and the pointer may be anywhere. null if
    // none. The dock that holds it stays out.
    property Item holder: null

    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    function store(list: list<string>): void {
        if (same(list, pinned))
            return;
        pinned = list;
        save();
    }

    function storeOrder(list: list<string>): void {
        if (same(list, order))
            return;
        order = list;
        save();
    }

    // Nothing is written before the file has been read: what is in it would
    // be replaced by the empty lists this starts with. (It was: the first
    // icons put in order wrote the file, the pins not yet read, and they
    // were gone.)
    property bool ready: false

    function save() {
        if (!ready)
            return;
        file.setText(JSON.stringify({
            pinned: pinned,
            order: order
        }, null, 2) + "\n");
    }

    function read() {
        let stored = {};
        try {
            stored = JSON.parse(file.text()) ?? {};
        } catch (error) {
            // no file yet, or one being written: nothing is known, nothing changes
            return;
        }
        // not assigned if the same: nothing then has to follow
        if (!same(stored.pinned ?? [], pinned))
            pinned = stored.pinned ?? [];
        if (!same(stored.order ?? [], order))
            order = stored.order ?? [];
    }

    FileView {
        id: file

        path: root.path
        blockLoading: true
        // edited by hand, or by another dock's task list: read again
        watchChanges: true
        onFileChanged: reload()
        // no file until something is pinned or dragged
        printErrors: false
        onLoaded: root.read()
    }

    Component.onCompleted: {
        read();
        ready = true;
    }
}
