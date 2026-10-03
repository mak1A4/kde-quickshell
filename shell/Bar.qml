import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.modules
import qs.widgets

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.bg

    RowLayout {
        anchors {
            left: parent.left
            leftMargin: Theme.spacing
            verticalCenter: parent.verticalCenter
        }
        spacing: Theme.spacing * 2

        // Workspaces and Taskbar import org.kde.taskmanager, hence Guarded
        Guarded {
            name: "desktops"
            source: Qt.resolvedUrl("modules/Workspaces.qml")
        }

        Guarded {
            name: "taskbar"
            source: Qt.resolvedUrl("modules/Taskbar.qml")
        }
    }

    Clock {
        anchors.centerIn: parent
    }

    RowLayout {
        anchors {
            right: parent.right
            rightMargin: Theme.spacing
            verticalCenter: parent.verticalCenter
        }
        spacing: Theme.spacing

        Media {}
        Tray {}
        Network {}
        Audio {}
        Battery {}
    }
}
