import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// The list that grows out of the frame's bottom left corner (see the Frame):
// every notification not yet closed, newest
// first, as the same cards the popups use (they do not expire here). While
// one is still open towards its application its actions work. Under them,
// "earlier": what a past run of the shell left in the history on disk (see
// Notifications.qml), as records without actions. Above
// it all: do not disturb, clear, and the way to System Settings.
Item {
    id: root

    readonly property var notifications: Notifications.history
    readonly property var earlier: Notifications.earlier
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
                visible: list.count > 0 || root.earlier.length > 0
                source: "edit-clear-history-symbolic"
                onClicked: {
                    Notifications.backend?.clear();
                    Notifications.clearEarlier();
                }
            }

            IconButton {
                source: "configure-symbolic"
                onClicked: {
                    Quickshell.execDetached(["kcmshell6", "kcm_notifications"]);
                    Notifications.listOpen = false;
                }
            }
        }

        ListView {
            id: list

            Layout.fillWidth: true
            implicitHeight: Math.min(contentHeight, root.maxListHeight)
            visible: count > 0 || root.earlier.length > 0
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

            // The earlier ones scroll with the list. A card takes a row of
            // KDE's model and the model to act on it; here it gets an entry
            // dressed as such a row, and for a model something that can only
            // close it.
            footer: Column {
                width: list.width
                spacing: list.spacing
                topPadding: list.count > 0 && root.earlier.length > 0 ? list.spacing : 0

                Label {
                    leftPadding: 3
                    visible: root.earlier.length > 0
                    color: Theme.fgDim
                    font.pixelSize: 12
                    text: "Earlier"
                }

                Repeater {
                    model: root.earlier

                    Card {
                        id: record

                        required property var modelData

                        width: list.width
                        model: ({
                                type: 1,
                                urgency: record.modelData.urgency,
                                timeout: 0,
                                expired: true,
                                created: new Date(record.modelData.created),
                                applicationName: record.modelData.applicationName,
                                applicationIconName: record.modelData.applicationIconName,
                                iconName: record.modelData.iconName,
                                summary: record.modelData.summary,
                                body: record.modelData.body,
                                hasDefaultAction: false
                            })
                        notifications: QtObject {
                            function index(row, column) {
                                return record.modelData.key;
                            }

                            function close(key) {
                                Notifications.forget(key);
                            }

                            function expire(key) {
                            }
                        }
                        defaultTimeout: 0
                        paused: true
                        now: root.now
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: Theme.padding
            Layout.bottomMargin: Theme.padding
            visible: list.count === 0 && root.earlier.length === 0
            horizontalAlignment: Text.AlignHCenter
            color: Theme.fgDim
            text: Notifications.serving ? "No notifications" : "Plasma is showing the notifications"
        }
    }
}
