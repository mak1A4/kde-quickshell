import QtQuick
import org.kde.kirigami as Kirigami

// One thing that can be done from the lock screen: an icon and its name, in
// the manner of the shell's buttons.
Rectangle {
    id: button

    required property QtObject look
    property string icon
    property alias text: label.text

    signal clicked

    width: row.implicitWidth + 24
    height: 36
    radius: height / 2
    color: mouse.containsMouse ? look.surfaceHover : look.surface

    Behavior on color {
        ColorAnimation {
            duration: button.look.fadeDuration
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: button.look.spacing

        Kirigami.Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: button.look.iconSize
            height: button.look.iconSize
            source: button.icon
            isMask: true
            color: button.look.fg
        }

        Text {
            id: label

            anchors.verticalCenter: parent.verticalCenter
            color: button.look.fg
            font.pixelSize: button.look.fontSize
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        onClicked: button.clicked()
    }
}
