pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Notifications in the shell: while it runs it is the notification service,
// and Plasma is again the moment it does not. The service is
// notifications/Service.qml (KDE's own notification engine), the popups are
// notifications/Popups.qml, shown by the Frame.
Singleton {
    id: root

    // imports KDE modules, hence the Loader: a failed import must not take
    // the shell down
    Loader {
        id: service

        source: Qt.resolvedUrl("notifications/Service.qml")
    }

    readonly property var backend: service.item
    readonly property bool failed: service.status === Loader.Error
    // false: Plasma is showing the notifications (the shell is not the
    // service, for want of the helper in plasmashell or of KDE's modules)
    readonly property bool serving: backend?.serving ?? false
    // Only critical notifications pop up. The rest collect in the list the
    // bar's bell opens (modules/Bell.qml), which shows a dot while some are
    // unread.
    readonly property var popups: backend?.popups ?? null
    readonly property var history: backend?.history ?? null
    readonly property int unread: backend?.unread ?? 0
    readonly property int count: backend?.count ?? 0
    readonly property bool doNotDisturb: backend?.inhibited ?? false

    // the bell in the bar and its list, for opening the list from elsewhere
    property Item bell: null
    property Component list: null

    function toggleList() {
        if (bell && list)
            Popouts.toggle("notifications", bell, list);
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.toggleList();
        }

        function unread(): int {
            return root.unread;
        }

        function count(): int {
            return root.count;
        }
    }

    // The helper plasmashell needs for the handover is a Plasma widget. It
    // is installed for the user here if it is missing or differs from the
    // one in this repository. Plasma's system tray loads a new one by
    // itself; a changed one only when plasmashell next starts.
    Process {
        running: true
        command: ["sh", "-c", `
            src=$1
            dest="\${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/io.github.mak1a4.kde-quickshell.handover"
            [ -d "$src" ] || exit 0
            if [ ! -d "$dest" ]; then
                kpackagetool6 --type Plasma/Applet --install "$src" > /dev/null && echo installed
            elif ! diff -rq "$src" "$dest" > /dev/null; then
                kpackagetool6 --type Plasma/Applet --upgrade "$src" > /dev/null && echo upgraded
            fi
        `, "sh", Quickshell.shellDir.replace(/[^\/]+\/?$/, "plasma/handover")]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.includes("upgraded"))
                    console.warn("Notifications: the handover helper in Plasma was updated; plasmashell uses it from its next start");
            }
        }
    }
}
