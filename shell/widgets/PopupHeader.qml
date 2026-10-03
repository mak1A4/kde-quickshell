import Quickshell
import QtQuick
import QtQuick.Layouts
import qs

// Popup title with a gear button that opens the matching System Settings module.
RowLayout {
    id: root

    required property string title
    required property string settingsModule

    Label {
        Layout.fillWidth: true
        font.pixelSize: 15
        font.bold: true
        text: root.title
    }

    IconButton {
        source: "configure-symbolic"
        onClicked: Quickshell.execDetached(["kcmshell6", root.settingsModule])
    }
}
