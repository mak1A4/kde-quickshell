import QtQuick
import qs

Rectangle {
    id: root

    property alias source: icon.source
    property alias iconColor: icon.color
    property bool checked: false

    signal clicked

    implicitWidth: 24
    implicitHeight: 24
    radius: Theme.radius
    color: checked ? Theme.surface : (mouse.containsMouse ? Theme.surfaceHover : Theme.none)

    Behavior on color {
        ColorAnim {}
    }

    Icon {
        id: icon

        anchors.centerIn: parent
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
