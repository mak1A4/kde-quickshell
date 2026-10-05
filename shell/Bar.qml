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
        spacing: Theme.barSpacing

        // Only there while something below is hidden (BarItems): a click
        // brings the hidden items into the bar, each in its place, a second
        // one puts them away. The group grows upward, being anchored at its
        // lower end.
        BarButton {
            visible: BarItems.hiddenCount > 0
            hintTitle: BarItems.expanded ? "Hide again" : BarItems.hiddenCount === 1 ? "1 hidden icon" : `${BarItems.hiddenCount} hidden icons`
            onClicked: BarItems.expanded = !BarItems.expanded

            Icon {
                Layout.alignment: Qt.AlignHCenter
                source: "go-up-symbolic"
                rotation: BarItems.expanded ? 180 : 0

                Behavior on rotation {
                    Anim {}
                }
            }
        }

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
