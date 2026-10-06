import QtQuick

// A key and what it does, as in the last line of the shell's command palette.
Row {
    id: hint

    required property QtObject look
    property string key
    property string text

    spacing: look.spacing
    visible: text !== ""

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(18, keyLabel.implicitWidth + 9)
        height: 18
        radius: 4.5
        color: hint.look.surface

        Text {
            id: keyLabel

            anchors.centerIn: parent
            color: hint.look.fgDim
            font.pixelSize: hint.look.fontSizeSmall
            text: hint.key
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        color: hint.look.fgDim
        font.pixelSize: 11
        text: hint.text
    }
}
