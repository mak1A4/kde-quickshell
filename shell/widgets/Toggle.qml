import QtQuick
import qs

Rectangle {
    id: root

    property bool checked: false

    signal toggled

    implicitWidth: 36
    implicitHeight: 18
    radius: 9
    color: checked ? Theme.accent : Theme.surfaceHover

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - width - 3 : 3
        width: 12
        height: 12
        radius: 6
        color: root.checked ? Theme.accentFg : Theme.fg

        Behavior on x {
            NumberAnimation {
                duration: 120
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled()
    }
}
