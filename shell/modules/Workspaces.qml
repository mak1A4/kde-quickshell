import Quickshell
import QtQuick
import org.kde.kwindowsystem
import org.kde.taskmanager as TaskManager
import qs
import qs.widgets

// Virtual desktops as a column of dots, one colour per desktop. The current
// desktop is a taller capsule that slides between positions (after Caelestia's
// indicator); desktops with windows are solid dots, empty ones small and faint.
// While "show desktop" is active the capsule is hollow.
//
// State comes from libtaskmanager's VirtualDesktopInfo
// (org_kde_plasma_virtual_desktop_management, no grant needed). It exposes no
// activate call to QML, so switching writes KWin's D-Bus `current` property.
// Clicking the current desktop toggles KWin's "show desktop": all windows are
// hidden, and come back exactly as they were on the next click. The ring at
// the end appends a desktop (KWin D-Bus `createDesktop`) and switches to it.
// Right click removes a desktop; KWin moves its windows to a neighbour.
Item {
    id: root

    readonly property int cell: 21

    function colorAt(index) {
        return Theme.desktopColors[index % Theme.desktopColors.length];
    }
    readonly property var ids: info.desktopIds
    readonly property int currentIndex: ids.indexOf(info.currentDesktop)

    // desktop id -> true for desktops with at least one window
    property var occupied: ({})
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

    // Removes a desktop. KWin rehomes its windows by its own rule: they stay
    // at the same position in the list, i.e. on the desktop that followed, or on
    // the new last desktop when the last one is removed.
    function remove(position) {
        if (ids.length <= 1 || position < 0 || position >= ids.length)
            return;
        Quickshell.execDetached(["busctl", "--user", "call", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager", "removeDesktop", "s", ids[position]]);
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

    // The capsule. Its two ends move separately: the leading end at normal
    // speed, the trailing end slower, so it stretches while travelling.
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

        readonly property color tint: root.colorAt(Math.max(0, root.currentIndex))

        visible: root.currentIndex >= 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: start + 1.5
        width: 12
        height: end - start - 3
        radius: width / 2
        // hollow while all windows are hidden
        color: KWindowSystem.showingDesktop ? Qt.alpha(tint, 0) : tint
        border.width: 3
        border.color: tint

        Behavior on color {
            ColorAnim {}
        }

        Behavior on border.color {
            ColorAnim {}
        }

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
            y: index * root.cell
            width: root.width
            height: root.cell

            // the dot; the capsule covers it on the current desktop
            Rectangle {
                readonly property bool occupied: root.occupied[desktop.modelData] ?? false
                property real size: (occupied ? 9 : 6) * (hover.hovered ? 1.5 : 1)

                anchors.centerIn: parent
                anchors.alignWhenCentered: false
                visible: !desktop.current
                width: size
                height: size
                radius: size / 2
                color: root.colorAt(desktop.index)
                opacity: occupied || hover.hovered ? 1 : 0.4

                Behavior on size {
                    Anim {
                        kind: Anim.Fade
                    }
                }

                Behavior on opacity {
                    Anim {
                        kind: Anim.Fade
                    }
                }
            }

            HoverHandler {
                id: hover
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: event => {
                    if (event.button === Qt.RightButton)
                        root.remove(desktop.index);
                    else if (desktop.current)
                        KWindowSystem.showingDesktop = !KWindowSystem.showingDesktop;
                    else
                        root.activate(desktop.index);
                }
            }
        }
    }

    // New desktop: always the last dot, a ring in the colour the next desktop
    // will get. It fills in on hover.
    Item {
        y: Math.max(root.ids.length, 1) * root.cell
        width: root.width
        height: root.cell
        visible: info.numberOfDesktops > 0

        Behavior on y {
            Anim {}
        }

        Rectangle {
            readonly property color tint: root.colorAt(root.ids.length)
            property real size: addHover.hovered ? 13.5 : 9

            anchors.centerIn: parent
            anchors.alignWhenCentered: false
            width: size
            height: size
            radius: size / 2
            color: addHover.hovered ? tint : Qt.alpha(tint, 0)
            border.width: 1.5
            border.color: tint
            opacity: addHover.hovered ? 1 : 0.6

            Behavior on size {
                Anim {
                    kind: Anim.Fade
                }
            }

            Behavior on color {
                ColorAnim {}
            }

            Behavior on opacity {
                Anim {
                    kind: Anim.Fade
                }
            }
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
