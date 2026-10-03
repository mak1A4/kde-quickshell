import Quickshell
import QtQuick
import QtQuick.Layouts
import org.kde.taskmanager as TaskManager
import qs
import qs.widgets

// Virtual desktops. State comes from libtaskmanager's VirtualDesktopInfo
// (org_kde_plasma_virtual_desktop_management, no grant needed). It exposes no
// activate call to QML, so switching writes KWin's D-Bus `current` property.
RowLayout {
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
    Label {
        visible: info.numberOfDesktops === 0
        color: Theme.error
        text: "desktops unavailable"
    }

    Repeater {
        model: info.desktopIds

        Pill {
            id: desktop

            required property var modelData
            required property int index
            readonly property bool current: modelData === info.currentDesktop

            highlighted: current
            onClicked: root.activate(index)
            // wheel up = previous desktop
            onScrolled: steps => root.activate(info.desktopIds.indexOf(info.currentDesktop) - steps)

            Label {
                color: desktop.current ? Theme.accentFg : Theme.fg
                text: desktop.index + 1
            }
        }
    }
}
