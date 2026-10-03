import Quickshell
import QtQuick
import org.kde.kwindowsystem
import org.kde.taskmanager as TaskManager
import qs
import qs.widgets

// Virtual desktops as a track of numbers with a sliding pill on the current
// one (after Caelestia's indicator). Desktops that have windows get a soft
// background, joined across neighbours.
//
// State comes from libtaskmanager's VirtualDesktopInfo
// (org_kde_plasma_virtual_desktop_management, no grant needed). It exposes no
// activate call to QML, so switching writes KWin's D-Bus `current` property.
// Clicking the current desktop toggles KWin's "show desktop": all windows are
// hidden, and come back exactly as they were on the next click. The "+" under
// the track appends a desktop (KWin D-Bus `createDesktop`) and switches to it.
Item {
    id: root

    readonly property int cell: 30
    readonly property var ids: info.desktopIds
    readonly property int currentIndex: ids.indexOf(info.currentDesktop)

    // desktop id -> true for desktops with at least one window
    property var occupied: ({})
    // consecutive occupied desktops, as { first, count }
    readonly property var runs: {
        const result = [];
        for (let i = 0; i < ids.length; i++) {
            if (!occupied[ids[i]])
                continue;
            const last = result[result.length - 1];
            if (last && last.first + last.count === i)
                last.count++;
            else
                result.push({ first: i, count: 1 });
        }
        return result;
    }

    function activate(position) {
        if (position < 0 || position >= ids.length)
            return;
        Quickshell.execDetached(["busctl", "--user", "set-property", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager", "current", "s", ids[position]]);
    }

    // set by add(); the new desktop is entered once KWin reports it
    property bool enterNewDesktop: false

    function add() {
        enterNewDesktop = true;
        // an empty name lets KWin pick its default ("Desktop N")
        Quickshell.execDetached(["busctl", "--user", "call", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager", "createDesktop", "us", String(ids.length), ""]);
    }

    onIdsChanged: {
        if (!enterNewDesktop)
            return;
        enterNewDesktop = false;
        activate(ids.length - 1);
    }

    function refreshOccupied() {
        const result = {};
        for (let i = 0; i < windows.count; i++) {
            const window = windows.objectAt(i);
            // windows on all desktops would mark every desktop; they say nothing
            if (!window || window.everywhere)
                continue;
            for (const id of window.desktops)
                result[id] = true;
        }
        occupied = result;
    }

    implicitWidth: Theme.barButton
    implicitHeight: (Math.max(ids.length, 1) + 1) * cell

    TaskManager.VirtualDesktopInfo {
        id: info
    }

    // needs KWin's window-management grant; without it nothing shows as occupied
    TaskManager.TasksModel {
        id: tasks

        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
    }

    Instantiator {
        id: windows

        model: tasks
        onObjectAdded: root.refreshOccupied()
        onObjectRemoved: root.refreshOccupied()

        QtObject {
            required property var model
            readonly property var desktops: model.VirtualDesktops ?? []
            readonly property bool everywhere: model.IsOnAllVirtualDesktops ?? false

            onDesktopsChanged: root.refreshOccupied()
            onEverywhereChanged: root.refreshOccupied()
        }
    }

    // KWin always has at least one desktop, so zero means the backend is down
    Icon {
        anchors.centerIn: parent
        visible: info.numberOfDesktops === 0
        source: "data-error"
        color: Theme.error
    }

    Repeater {
        model: root.runs

        Rectangle {
            required property var modelData

            y: modelData.first * root.cell
            width: root.width
            height: modelData.count * root.cell
            radius: Math.min(width, height) / 2
            color: Theme.surface

            Behavior on y {
                Anim {}
            }

            Behavior on height {
                Anim {}
            }
        }
    }

    // The pill. Its two ends move separately: the leading end at normal speed,
    // the trailing end slower, so it stretches while travelling.
    Rectangle {
        id: pill

        property real start: 0
        property real end: root.cell
        property bool placed: false

        function moveTo(index) {
            if (index < 0)
                return;
            const target = index * root.cell;
            if (!placed) {
                start = target;
                end = target + root.cell;
                placed = true;
                return;
            }
            const down = target > start;
            startAnim.stop();
            endAnim.stop();
            startAnim.to = target;
            endAnim.to = target + root.cell;
            startAnim.duration = Theme.moveDuration * (down ? 1.5 : 1);
            endAnim.duration = Theme.moveDuration * (down ? 1 : 1.5);
            startAnim.start();
            endAnim.start();
        }

        visible: root.currentIndex >= 0
        y: start
        width: root.width
        height: end - start
        radius: Math.min(width, height) / 2
        color: Theme.accent

        Anim {
            id: startAnim

            target: pill
            property: "start"
        }

        Anim {
            id: endAnim

            target: pill
            property: "end"
        }

        Connections {
            target: root

            function onCurrentIndexChanged() {
                pill.moveTo(root.currentIndex);
            }
        }

        Component.onCompleted: moveTo(root.currentIndex)
    }

    Repeater {
        model: root.ids

        Item {
            id: desktop

            required property var modelData
            required property int index
            readonly property bool current: index === root.currentIndex
            readonly property bool showingDesktop: current && KWindowSystem.showingDesktop
            y: index * root.cell
            width: root.width
            height: root.cell

            // hover feedback for the desktops the pill is not on
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Theme.surfaceHover
                opacity: hover.hovered && !desktop.current ? 1 : 0

                Behavior on opacity {
                    Anim {
                        kind: Anim.Fade
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: !desktop.showingDesktop
                color: desktop.current ? Theme.accentFg : (root.occupied[desktop.modelData] ? Theme.fg : Theme.fgDim)
                font.bold: desktop.current
                text: desktop.index + 1

                Behavior on color {
                    ColorAnim {}
                }
            }

            // replaces the number while the desktop is showing
            Icon {
                anchors.centerIn: parent
                visible: desktop.showingDesktop
                source: "user-desktop-symbolic"
                color: Theme.accentFg
            }

            HoverHandler {
                id: hover
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (desktop.current)
                        KWindowSystem.showingDesktop = !KWindowSystem.showingDesktop;
                    else
                        root.activate(desktop.index);
                }
            }
        }
    }

    // new desktop
    Item {
        y: Math.max(root.ids.length, 1) * root.cell
        width: root.width
        height: root.cell
        visible: info.numberOfDesktops > 0

        Behavior on y {
            Anim {}
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.surfaceHover
            opacity: addHover.hovered ? 1 : 0

            Behavior on opacity {
                Anim {
                    kind: Anim.Fade
                }
            }
        }

        Icon {
            anchors.centerIn: parent
            source: "list-add-symbolic"
            color: addHover.hovered ? Theme.fg : Theme.fgDim
        }

        HoverHandler {
            id: addHover
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.add()
        }
    }
}
