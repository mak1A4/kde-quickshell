pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Everything the shell needs outside itself, looked at each time it starts:
// its desktop entry, its start at login, the lock screen, what Plasma loads
// of it, the login screen, the keepers, and whether the programs that take
// its theme are connected to it. What is the shell's own to put in place is
// put there (setup.sh, which says for each thing what it does); the rest is
// said.
//
// Nothing is shown when all is well. A notification says what was put right,
// and what is wrong and cannot be: that once, not at every start. "Check the
// shell's setup" among the ">" actions looks again and says how everything
// stands, and what is not as it should be is listed there too;
// `qs ipc call setup report` gives it all as text.
Singleton {
    id: root

    // { state, id, title, detail }; state is "ok", "fixed", "note" or "problem"
    property var items: []
    // false until it has been looked at once
    property bool ready: false
    // what there is to know about: everything that is not simply in place
    readonly property var open: items.filter(item => item.state !== "ok")
    readonly property string summary: {
        if (!ready)
            return "Not looked at yet";
        const count = state => items.filter(item => item.state === state).length;
        const parts = [];
        for (const [state, one, many] of [["problem", "problem", "problems"], ["fixed", "put right", "put right"], ["note", "note", "notes"]]) {
            if (count(state) > 0)
                parts.push(`${count(state)} ${count(state) === 1 ? one : many}`);
        }
        return parts.length > 0 ? parts.join(", ") : `Everything is in place (${items.length} things looked at)`;
    }

    // `all`: say how everything stands, not only what is new
    function check(all: bool): void {
        if (checker.running) {
            // what is asked for meanwhile is looked at afterwards
            again = true;
            sayAll = sayAll || all;
            return;
        }
        checker.command = ["sh", Quickshell.shellPath("setup.sh"), Quickshell.shellDir, all ? "all" : "news"];
        checker.running = true;
    }

    property bool again: false
    property bool sayAll: false

    Process {
        id: checker

        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                for (const line of text.split("\n")) {
                    // (not taken apart as `const [state, ...] =`: for a
                    // line with fewer parts, QML's JavaScript leaves the
                    // names with what they had for the line before)
                    const parts = line.split("\t");
                    if (parts.length < 4)
                        continue;
                    found.push({
                        state: parts[0],
                        id: parts[1],
                        title: parts[2],
                        detail: parts[3]
                    });
                }
                if (found.length === 0) {
                    console.warn("Setup: setup.sh said nothing");
                    return;
                }
                for (const item of found) {
                    if (item.state === "problem")
                        console.warn(`Setup: ${item.title}: ${item.detail}`);
                    else if (item.state === "fixed")
                        console.info(`Setup: ${item.title}: ${item.detail}`);
                }
                root.items = found;
                root.ready = true;
            }
        }
        onExited: {
            if (!root.again)
                return;
            const all = root.sayAll;
            root.again = false;
            root.sayAll = false;
            root.check(all);
        }
    }

    // Not in the first moments: the keepers are started and the theme is
    // given to KDE as the shell starts, and both are looked at.
    Timer {
        interval: 8000
        running: true
        onTriggered: root.check(false)
    }

    // the login screen has just been updated, or the question turned down
    Connections {
        target: LoginScreen

        function onVerdictChanged() {
            if (root.ready && ["ok", "declined", "failed"].includes(LoginScreen.verdict))
                root.check(false);
        }
    }

    IpcHandler {
        target: "setup"

        // looks again; a notification says how everything stands
        function check(): void {
            root.check(true);
        }

        function summary(): string {
            return root.summary;
        }

        // what was found last, a line for each thing
        function report(): string {
            return root.items.map(item => `${item.state.padEnd(8)}${item.title}: ${item.detail}`).join("\n");
        }
    }
}
