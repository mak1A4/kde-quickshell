import Quickshell
import QtQuick

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }
    // 30 logical px = exactly 40 device px at scale 1.333 (multiples of 3 land on whole pixels)
    implicitHeight: 30
    color: "#1e1e2e"

    Row {
        anchors {
            left: parent.left
            leftMargin: 9
            verticalCenter: parent.verticalCenter
        }
        spacing: 6

        Text {
            visible: !VirtualDesktops.available
            color: "#f38ba8"
            font.pixelSize: 13
            text: "desktops: KWin D-Bus unavailable"
        }

        Repeater {
            model: VirtualDesktops.desktops

            Rectangle {
                id: desktop

                required property var modelData

                width: name.implicitWidth + 16
                height: 22
                radius: 6
                color: desktop.modelData.id === VirtualDesktops.current ? "#89b4fa" : "#313244"

                Text {
                    id: name

                    anchors.centerIn: parent
                    color: desktop.modelData.id === VirtualDesktops.current ? "#1e1e2e" : "#cdd6f4"
                    font.pixelSize: 13
                    text: desktop.modelData.name
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: VirtualDesktops.activate(desktop.modelData.id)
                }
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Text {
        anchors.centerIn: parent
        color: "#cdd6f4"
        font.pixelSize: 13
        text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm:ss")
    }

    // Loaded indirectly so a missing org.kde.taskmanager module degrades to a
    // visible error instead of taking the whole bar down.
    Loader {
        id: taskList

        anchors {
            right: parent.right
            rightMargin: 9
            verticalCenter: parent.verticalCenter
        }
        source: "TaskList.qml"
    }

    Text {
        visible: taskList.status === Loader.Error
        anchors {
            right: parent.right
            rightMargin: 9
            verticalCenter: parent.verticalCenter
        }
        color: "#f38ba8"
        font.pixelSize: 13
        text: "taskbar: org.kde.taskmanager not loadable"
    }
}
