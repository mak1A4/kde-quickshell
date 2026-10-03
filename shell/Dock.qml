import QtQuick
import qs.widgets

// Open windows, hidden until the pointer touches the bottom frame edge.
// Fill the frame with this item; `panel` is the visible part.
Item {
    id: root

    readonly property alias panel: panel
    property bool shown: false
    readonly property bool wanted: sensor.hovered || panelHover.hovered

    onWantedChanged: {
        if (wanted) {
            hide.stop();
            shown = true;
        } else {
            hide.restart();
        }
    }

    Timer {
        id: hide

        interval: 300
        onTriggered: root.shown = false
    }

    // the bottom border strip; always part of the frame's input region
    Item {
        x: Theme.frameBorder
        y: root.height - Theme.frameBorder
        width: root.width - Theme.frameBorder - Theme.barWidth
        height: Theme.frameBorder

        HoverHandler {
            id: sensor
        }
    }

    AttachedShape {
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
        edge: Qt.BottomEdge
    }

    Item {
        id: panel

        x: Theme.frameBorder + (root.width - Theme.frameBorder - Theme.barWidth - width) / 2
        y: root.height - Theme.frameBorder - height
        width: taskbar.implicitWidth + Theme.padding * 2
        height: root.shown ? Theme.dockHeight : 0
        clip: true

        Behavior on height {
            Anim {}
        }

        Behavior on width {
            Anim {}
        }

        HoverHandler {
            id: panelHover
        }

        // imports org.kde.taskmanager, hence Guarded
        Guarded {
            id: taskbar

            x: Theme.padding
            y: (Theme.dockHeight - implicitHeight) / 2
            name: "taskbar"
            source: Qt.resolvedUrl("modules/Taskbar.qml")
            opacity: root.shown ? 1 : 0

            Behavior on opacity {
                Anim {}
            }
        }
    }
}
