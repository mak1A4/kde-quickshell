import Quickshell
import QtQuick
import QtQuick.Layouts
import qs

// A small menu of the shell's own actions, opening above its anchor (the
// dock is at the bottom). `actions` is a list of { text, icon, run }: a theme
// icon's name or none, and what a click does. Toggle with `open`, not
// `visible`. Closes on a click outside, on Escape, after an action, and when
// another menu opens (Popouts.menu). Set the actions before opening: a popup
// must not resize while it is mapped (see MenuPopup.qml, the tray's menus).
PopupWindow {
    id: root

    required property Item anchorItem
    property var actions: []
    property bool open: false

    visible: open && Popouts.menu === root && actions.length > 0
    onOpenChanged: Popouts.menuToggled(root)
    onVisibleChanged: {
        if (!visible)
            open = false;
    }

    implicitWidth: Math.max(150, column.implicitWidth) + Theme.spacing * 2
    implicitHeight: column.implicitHeight + Theme.spacing * 2
    color: "transparent"
    grabFocus: true
    anchor.item: anchorItem
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top
    anchor.margins.top: -Theme.spacing
    anchor.adjustment: PopupAdjustment.SlideX

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius * 2
        color: Theme.bg
        border.width: 1.5
        border.color: Theme.surface
        focus: true
        Keys.onEscapePressed: root.open = false
    }

    ColumnLayout {
        id: column

        anchors {
            fill: parent
            margins: Theme.spacing
        }
        spacing: 0

        Repeater {
            model: root.actions

            Item {
                id: entry

                required property var modelData

                Layout.fillWidth: true
                implicitWidth: row.implicitWidth + Theme.padding * 2
                implicitHeight: 27

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: mouse.containsMouse ? Theme.surfaceHover : Theme.none
                }

                RowLayout {
                    id: row

                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Theme.padding
                        rightMargin: Theme.padding
                    }
                    spacing: Theme.spacing

                    Icon {
                        visible: (entry.modelData.icon ?? "") !== ""
                        source: entry.modelData.icon ?? ""
                    }

                    Label {
                        Layout.fillWidth: true
                        text: entry.modelData.text
                    }
                }

                MouseArea {
                    id: mouse

                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.open = false;
                        entry.modelData.run();
                    }
                }
            }
        }
    }
}
