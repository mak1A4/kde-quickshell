import QtQuick
import QtQuick.Layouts
import qs

// A key and what it does, for the last line of a panel that is worked with
// the keyboard. Without a text it is not there.
RowLayout {
    id: hint

    property string key
    property string text

    spacing: Theme.spacing
    visible: text !== ""

    Rectangle {
        implicitWidth: Math.max(18, keyLabel.implicitWidth + 9)
        implicitHeight: 18
        radius: 4.5
        color: Theme.surface

        Label {
            id: keyLabel

            anchors.centerIn: parent
            color: Theme.fgDim
            font.pixelSize: Theme.fontSizeSmall
            text: hint.key
        }
    }

    Label {
        Layout.maximumWidth: 210
        color: Theme.fgDim
        font.pixelSize: 11
        text: hint.text
    }
}
