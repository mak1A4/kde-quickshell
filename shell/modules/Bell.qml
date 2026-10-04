import QtQuick
import QtQuick.Layouts
import qs
import qs.notifications
import qs.widgets

// Notifications, quietly: they do not pop up (critical ones aside, see the
// Notifications singleton) but collect behind this bell. A dot on it, with a
// ring spreading out from it, says there are some not yet looked at. Left
// click opens the list, middle click switches do not disturb.
BarButton {
    id: root

    readonly property int unread: Notifications.unread
    readonly property bool quiet: Notifications.doNotDisturb

    active: Popouts.current === "notifications"
    hintTitle: "Notifications"
    hintLines: {
        const lines = [];
        if (!Notifications.serving)
            return ["Shown by Plasma"];
        if (unread > 0)
            lines.push(unread === 1 ? "1 new" : `${unread} new`);
        else
            lines.push(Notifications.count > 0 ? `${Notifications.count} in the list` : "None");
        if (quiet)
            lines.push("Do not disturb is on");
        return lines;
    }
    onClicked: button => {
        if (button === Qt.LeftButton)
            Notifications.toggleList();
        else if (button === Qt.MiddleButton)
            Notifications.backend?.setDoNotDisturb(!quiet);
    }

    // the list can then be opened from elsewhere (a shortcut, IPC)
    Component.onCompleted: {
        Notifications.bell = root;
        Notifications.list = list;
    }

    Component {
        id: list

        NotificationList {}
    }

    Item {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: Theme.iconSize
        implicitHeight: Theme.iconSize

        Icon {
            anchors.fill: parent
            color: root.unread > 0 ? Theme.fg : Theme.fgDim
            source: root.quiet ? "notifications-disabled-symbolic" : "notifications-symbolic"
        }

        // the dot: there, and still, in do not disturb; otherwise it calls
        Rectangle {
            id: dot

            readonly property bool calling: root.unread > 0 && !root.quiet

            anchors {
                right: parent.right
                top: parent.top
                rightMargin: -3
                topMargin: -3
            }
            width: 9
            height: 9
            radius: width / 2
            color: Theme.accent
            border.width: 1.5
            border.color: Theme.bg
            visible: root.unread > 0

            // a ring that spreads out from the dot and fades, every two seconds
            Rectangle {
                id: ring

                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: "transparent"
                border.width: 1.5
                border.color: Theme.accent
                opacity: 0

                SequentialAnimation {
                    running: dot.calling
                    loops: Animation.Infinite
                    onRunningChanged: {
                        if (!running) {
                            ring.opacity = 0;
                            ring.scale = 1;
                        }
                    }

                    ParallelAnimation {
                        NumberAnimation {
                            target: ring
                            property: "scale"
                            from: 1
                            to: 3
                            duration: 1100
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            target: ring
                            property: "opacity"
                            from: 0.8
                            to: 0
                            duration: 1100
                            easing.type: Easing.OutCubic
                        }
                    }

                    PauseAnimation {
                        duration: 900
                    }
                }
            }
        }
    }
}
