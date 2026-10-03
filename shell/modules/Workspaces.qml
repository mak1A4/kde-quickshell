import Quickshell
import QtQuick
import QtQuick.Layouts
import org.kde.kwindowsystem
import org.kde.taskmanager as TaskManager
import qs
import qs.widgets

// Virtual desktops. State comes from libtaskmanager's VirtualDesktopInfo
// (org_kde_plasma_virtual_desktop_management, no grant needed). It exposes no
// activate call to QML, so switching writes KWin's D-Bus `current` property.
// Clicking the current desktop toggles KWin's "show desktop": all windows are
// hidden, and come back exactly as they were on the next click.
ColumnLayout {
    id: root

    spacing: 3

    function activate(position) {
        const ids = info.desktopIds;
        if (position < 0 || position >= ids.length)
            return;
        Quickshell.execDetached(["busctl", "--user", "set-property", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager", "current", "s", ids[position]]);
    }

    TaskManager.VirtualDesktopInfo {
        id: info
    }

    // KWin always has at least one desktop, so zero means the backend is down
    Icon {
        Layout.alignment: Qt.AlignHCenter
        visible: info.numberOfDesktops === 0
        source: "data-error"
        color: Theme.error
    }

    Repeater {
        model: info.desktopIds

        BarButton {
            id: desktop

            required property var modelData
            required property int index
            readonly property bool current: modelData === info.currentDesktop

            implicitHeight: 27
            highlighted: current
            hintTitle: info.desktopNames[index] ?? ""
            hintLines: {
                if (!current)
                    return [];
                return KWindowSystem.showingDesktop ? ["Showing desktop", "Click to bring the windows back"] : ["Current desktop", "Click to show the desktop"];
            }
            onClicked: {
                if (current)
                    KWindowSystem.showingDesktop = !KWindowSystem.showingDesktop;
                else
                    root.activate(index);
            }
            // wheel up = previous desktop
            onScrolled: steps => root.activate(info.desktopIds.indexOf(info.currentDesktop) - steps)

            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: !(desktop.current && KWindowSystem.showingDesktop)
                color: desktop.current ? Theme.accentFg : Theme.fg
                text: desktop.index + 1
            }

            // replaces the number while the desktop is showing
            Icon {
                Layout.alignment: Qt.AlignHCenter
                visible: desktop.current && KWindowSystem.showingDesktop
                source: "user-desktop-symbolic"
                color: Theme.accentFg
            }
        }
    }
}
