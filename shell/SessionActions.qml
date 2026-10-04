pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// What can be done to the session, for the session menu in the bar and the
// launcher's ">" actions. Everything goes through KDE or logind:
//   - lock and the sleep states via logind
//   - log out, restart, shut down via KDE's session manager (org.kde.Shutdown),
//     which closes applications properly first
// `confirm` marks actions that end the session. The bar menu asks for a second
// click; the launcher uses KDE's own confirmation screen (`prompt`) instead.
Singleton {
    id: root

    // suspend-to-disk needs swap set up for it; ask logind rather than assume
    property bool canHibernate: false

    Process {
        running: true
        command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanHibernate"]
        stdout: StdioCollector {
            onStreamFinished: root.canHibernate = text.includes('"yes"')
        }
    }

    readonly property var all: [
        {
            id: "lock",
            title: "Lock screen",
            icon: "system-lock-screen-symbolic",
            confirm: false,
            command: ["loginctl", "lock-session"]
        },
        {
            id: "sleep",
            title: "Sleep",
            icon: "system-suspend-symbolic",
            confirm: false,
            command: ["systemctl", "suspend"]
        },
        {
            id: "hibernate",
            title: "Hibernate",
            icon: "system-suspend-hibernate-symbolic",
            confirm: false,
            command: ["systemctl", "hibernate"]
        },
        {
            id: "logout",
            title: "Log out",
            icon: "system-log-out-symbolic",
            confirm: true,
            command: ["busctl", "--user", "call", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown", "logout"],
            prompt: ["busctl", "--user", "call", "org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptLogout"]
        },
        {
            id: "restart",
            title: "Restart",
            icon: "system-reboot-symbolic",
            confirm: true,
            command: ["busctl", "--user", "call", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown", "logoutAndReboot"],
            prompt: ["busctl", "--user", "call", "org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptReboot"]
        },
        {
            id: "shutdown",
            title: "Shut down",
            icon: "system-shutdown-symbolic",
            confirm: true,
            command: ["busctl", "--user", "call", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown", "logoutAndShutdown"],
            prompt: ["busctl", "--user", "call", "org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptShutDown"]
        }
    ]

    readonly property var available: all.filter(action => action.id !== "hibernate" || canHibernate)

    // Runs it now. The caller is responsible for having confirmed.
    function run(action) {
        Quickshell.execDetached(action.command);
    }

    // Hands a session-ending action to KDE's confirmation screen; others just run.
    function runWithPrompt(action) {
        Quickshell.execDetached(action.prompt ?? action.command);
    }
}
