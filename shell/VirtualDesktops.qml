pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Virtual desktops via KWin's D-Bus API (org.kde.KWin /VirtualDesktopManager).
// Quickshell has no generic D-Bus client, so this shells out to busctl:
// one long-running `monitor` for change signals, one `GetAll` per change.
Singleton {
    id: root

    // false until the first successful read, and whenever a read fails
    property bool available: false
    property var desktops: [] // [{ position, id, name }]
    property string current: ""

    readonly property string service: "org.kde.KWin"
    readonly property string path: "/VirtualDesktopManager"
    readonly property string iface: "org.kde.KWin.VirtualDesktopManager"

    function activate(id) {
        Quickshell.execDetached(["busctl", "--user", "set-property", service, path, iface, "current", "s", id]);
    }

    function refresh() {
        if (fetch.running)
            fetch.stale = true;
        else
            fetch.running = true;
    }

    function parse(text) {
        try {
            const props = JSON.parse(text).data[0];
            desktops = props.desktops.data.map(d => ({ position: d[0], id: d[1], name: d[2] }));
            current = props.current.data;
            available = true;
        } catch (e) {
            console.warn("VirtualDesktops: KWin D-Bus read failed:", e, text);
            desktops = [];
            current = "";
            available = false;
        }
    }

    Process {
        id: fetch

        property bool stale: false

        running: true
        command: ["busctl", "--user", "--json=short", "call", root.service, root.path, "org.freedesktop.DBus.Properties", "GetAll", "s", root.iface]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: {
            if (stale) {
                stale = false;
                running = true;
            }
        }
    }

    Process {
        id: monitor

        running: true
        command: ["busctl", "--user", "--json=short", "monitor", "--match", `type='signal',sender='${root.service}',path='${root.path}'`]
        stdout: SplitParser {
            onRead: debounce.restart()
        }
        onExited: {
            console.warn("VirtualDesktops: busctl monitor exited, retrying");
            retry.start();
        }
    }

    Timer {
        id: debounce
        interval: 20
        onTriggered: root.refresh()
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: {
            monitor.running = true;
            root.refresh();
        }
    }
}
