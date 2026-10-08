import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root

    property alias text: label.text
    property string icon: ""
    // set `raised` for buttons sitting on a surface-coloured card
    property bool raised: false

    signal clicked

    implicitWidth: row.implicitWidth + Theme.padding * 2
    implicitHeight: Theme.pillHeight
    radius: Theme.radius
    color: {
        if (raised)
            return mouse.containsMouse ? Theme.surfaceActive : Theme.surfaceHover;
        return mouse.containsMouse ? Theme.surfaceHover : Theme.surface;
    }

    Behavior on color {
        ColorAnim {}
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Theme.spacing

        Icon {
            visible: root.icon !== ""
            source: root.icon
        }

        Label {
            id: label
        }
    }

    MouseArea {
        id: mouse

        cursorShape: Qt.PointingHandCursor
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
