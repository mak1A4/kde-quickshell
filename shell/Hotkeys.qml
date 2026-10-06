import Quickshell
import Quickshell.Io
import QtQuick

// Global shortcuts, the way a KDE application has them: the shell registers
// its actions with KDE's shortcut service (KGlobalAccel) under one component,
// "Quickshell", and the service tells it when one of their keys is pressed.
// KDE stores the keys (kglobalshortcutsrc) and lists the actions in System
// Settings > Keyboard > Shortcuts; the shell's settings window changes them
// there too. Nothing is started on a key press, and nothing depends on where
// the shell's files are.
//
// Without a D-Bus client in Quickshell this speaks KGlobalAccel's D-Bus
// interface through busctl: a few calls at startup, and one `busctl monitor`
// for the "pressed" signal. One instance, in shell.qml.
//
// The keys are the shell's only while it runs: a small keeper process
// outlives the shell and gives them back when it is gone, however it went.
// A reload leaves them alone. That also allows a key that something else in
// KDE has, KRunner's for instance: the owner keeps it and is only switched
// off while the shell runs ("overrides", see hotkeys.sh).
Scope {
    id: root

    readonly property string component: "kde-quickshell"
    readonly property string componentName: "Quickshell"

    // `id` is what KDE stores the key under, `name` what System Settings and
    // the settings window show. `key` is the key it starts out with, as a Qt
    // key number (0: none); once KDE knows the action, the stored key counts,
    // also if that is "none".
    readonly property var actions: [
        {
            id: "toggle-palette",
            name: "Toggle command palette",
            key: Qt.ControlModifier | Qt.Key_Space,
            run: () => CommandPalette.toggle(null)
        },
        {
            id: "toggle-launcher",
            name: "Toggle app launcher",
            key: 0,
            run: () => Launcher.toggle(null)
        },
        {
            id: "show-clipboard",
            name: "Show clipboard history",
            key: 0,
            run: () => CommandPalette.toggleMode("clipboard")
        },
        {
            id: "show-themes",
            name: "Show theme switcher",
            key: 0,
            run: () => CommandPalette.toggleMode("themes")
        },
        {
            id: "toggle-notifications",
            name: "Show notifications",
            key: 0,
            run: () => Notifications.toggleList()
        }
    ]

    // hotkeys.sh does the talking to KDE; see there
    readonly property string script: Quickshell.shellPath("hotkeys.sh")
    readonly property list<string> registerArgs: [component, componentName].concat(...actions.map(action => [action.id, action.name, String(action.key)]))

    // The keeper outlives the shell and gives the keys back when the shell's
    // process is gone. A reload starts it again; it then finds itself
    // running and leaves.
    // in a systemd scope of its own, so that it outlives the shell's unit
    // (see PlasmaPanels.qml)
    Component.onCompleted: Quickshell.execDetached(["sh", "-c", 'if command -v systemd-run > /dev/null; then exec systemd-run --user --scope --quiet -- "$@"; else exec "$@"; fi', "sh", "sh", script, "keep", String(Quickshell.processId)].concat(registerArgs))

    // on every load, so that a reload picks up a changed list of actions
    Process {
        running: true
        command: ["sh", root.script, "register"].concat(root.registerArgs)
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("Hotkeys: could not register the shortcuts with KDE (exit code", exitCode + ")");
        }
    }

    // One line of JSON per signal; its arguments are component, action, timestamp.
    function pressed(line) {
        let id;
        try {
            const message = JSON.parse(line);
            if (message.member !== "globalShortcutPressed")
                return;
            id = message.payload.data[1];
        } catch (problem) {
            return;
        }
        actions.find(action => action.id === id)?.run();
    }

    Process {
        id: listener

        running: true
        // KGlobalAccel's object for a component is named after it, with
        // everything that is not a letter or digit as "_"
        command: ["busctl", "--user", "monitor", "--json=short", "--match", `type='signal',sender='org.kde.kglobalaccel',path='/component/${root.component.replace(/[^A-Za-z0-9]/g, "_")}',member='globalShortcutPressed'`]
        stdout: SplitParser {
            onRead: line => root.pressed(line)
        }
        // it only ends if the session bus went away; try again in a moment
        onExited: restart.start()
    }

    Timer {
        id: restart

        interval: 3000
        onTriggered: listener.running = true
    }
}
