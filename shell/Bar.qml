import QtQuick
import QtQuick.Layouts
import qs.modules
import qs.widgets

// Contents of the vertical bar on the frame's right side.
Item {
    id: root

    ColumnLayout {
        anchors {
            top: parent.top
            topMargin: Theme.frameBorder + Theme.spacing
            horizontalCenter: parent.horizontalCenter
        }
        spacing: Theme.spacing

        // imports org.kde.taskmanager, hence Guarded
        Guarded {
            Layout.alignment: Qt.AlignHCenter
            name: "desktops"
            compact: true
            source: Qt.resolvedUrl("modules/Workspaces.qml")
        }
    }

    ColumnLayout {
        anchors {
            bottom: parent.bottom
            bottomMargin: Theme.frameBorder + Theme.spacing
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 3

        Media {}
        Tray {
            Layout.alignment: Qt.AlignHCenter
        }

        // imports KDE Connect's QML module, hence Guarded
        Guarded {
            Layout.alignment: Qt.AlignHCenter
            name: "kde connect"
            compact: true
            source: Qt.resolvedUrl("modules/Connect.qml")
        }

        Network {}
        Audio {}

        // imports PowerDevil's QML modules, hence Guarded
        Guarded {
            Layout.alignment: Qt.AlignHCenter
            name: "power"
            compact: true
            source: Qt.resolvedUrl("modules/Power.qml")
        }

        Session {}

    }

    Clock {
        anchors.centerIn: parent
    }
}
