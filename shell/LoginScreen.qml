pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Keeps the login screen in step with the session: the theme's background
// there, and the user's display scaling, keyboard layout, fonts and colours.
// The login screen is another user's and its files are root's, so this
// needs the password; login.sh says whether anything is to be done at all,
// and only then is it asked for (pkexec, in Plasma's own dialog).
//
// Looked at when the shell starts. A question for the password that was
// turned down is not asked again until something changes; "Update the login
// screen" among the ">" actions, or `qs ipc call login apply`, asks anyway.
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("login.sh")
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    // what login.sh said last: "ok", "declined", "needed", "asking", "failed"
    property string verdict: ""
    // the state being asked for
    property string wanted: ""

    function check(force: bool): void {
        if (checker.running || asker.running)
            return;
        checker.command = [script, "check", configDir].concat(force ? ["force"] : []);
        checker.running = true;
    }

    Process {
        id: checker

        stdout: StdioCollector {
            onStreamFinished: {
                const words = text.trim().split(" ");
                root.verdict = words[0] ?? "";
                if (words[0] !== "needed" || !words[1])
                    return;
                root.wanted = words[1];
                root.verdict = "asking";
                asker.command = ["pkexec", root.script, "apply", root.configDir, root.wanted];
                asker.running = true;
            }
        }
    }

    Process {
        id: asker

        stderr: StdioCollector {
            id: complaint
        }
        onExited: code => {
            if (code === 0) {
                root.verdict = "ok";
                // the directory for the background is there now: fill it;
                // and so is the helper that colours the browsers
                Themes.showBackgroundAgain();
                ThemeExport.write();
            } else if (code === 126) {
                // the dialog was closed: not again for this state
                root.verdict = "declined";
                Quickshell.execDetached([root.script, "declined", root.wanted]);
            } else {
                root.verdict = "failed";
                console.warn("LoginScreen: login.sh apply ended with", code, complaint.text.trim());
            }
        }
    }

    // not in the first moments of a session: the dialog is Plasma's, and
    // has to be there to ask
    Timer {
        interval: 5000
        running: true
        onTriggered: root.check(false)
    }

    IpcHandler {
        target: "login"

        function apply(): void {
            root.check(true);
        }

        function state(): string {
            return root.verdict;
        }
    }
}
