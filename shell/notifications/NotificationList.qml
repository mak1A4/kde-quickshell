import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// The list the bar's bell opens: every notification not yet closed, newest
// first, as the same cards the popups use (they do not expire here). They are
// still open towards their applications, so their actions work. Above
// it: do not disturb, clear, and the way to System Settings.
Item {
    id: root

    readonly property var notifications: Notifications.history
    readonly property int cardWidth: 345
    readonly property int maxListHeight: 540
    // for the cards' ages
    property real now: Date.now()

    implicitWidth: cardWidth + Theme.padding * 2
    implicitHeight: column.implicitHeight + Theme.padding * 2

    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // while it is open, what is in it and what arrives counts as seen
    Component.onCompleted: {
        if (Notifications.backend)
            Notifications.backend.listOpen = true;
    }
    Component.onDestruction: {
        if (Notifications.backend)
            Notifications.backend.listOpen = false;
    }

    ColumnLayout {
        id: column

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: Theme.padding
        }
        spacing: Theme.padding

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 3
            spacing: Theme.spacing

            Label {
                Layout.fillWidth: true
                font.pixelSize: 15
                font.bold: true
                text: "Notifications"
            }

            Label {
                color: Theme.fgDim
                font.pixelSize: 12
                text: "Do not disturb"
            }

            Toggle {
                Layout.rightMargin: Theme.spacing
                checked: Notifications.doNotDisturb
                onToggled: Notifications.backend?.setDoNotDisturb(!checked)
            }

            IconButton {
                visible: list.count > 0
                source: "edit-clear-history-symbolic"
                onClicked: Notifications.backend?.clear()
            }

            IconButton {
                source: "configure-symbolic"
                onClicked: {
                    Quickshell.execDetached(["kcmshell6", "kcm_notifications"]);
                    Popouts.close();
                }
            }
        }

        ListView {
            id: list

            Layout.fillWidth: true
            implicitHeight: Math.min(contentHeight, root.maxListHeight)
            visible: count > 0
            clip: true
            spacing: 9
            boundsBehavior: Flickable.StopAtBounds
            model: root.notifications

            delegate: Card {
                width: list.width
                notifications: root.notifications
                // it stays until it is closed or the list is cleared
                defaultTimeout: 0
                paused: true
                now: root.now
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: Theme.padding
            Layout.bottomMargin: Theme.padding
            visible: list.count === 0
            horizontalAlignment: Text.AlignHCenter
            color: Theme.fgDim
            text: Notifications.serving ? "No notifications" : "Plasma is showing the notifications"
        }
    }
}
