import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// StatusNotifierItem tray. Takes no space when no app has registered an item.
// Left click activates, middle click is the secondary action, right click
// opens the item's menu, drawn by the shell (widgets/MenuPopup.qml).
ColumnLayout {
    spacing: 0
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        Rectangle {
            id: item

            required property SystemTrayItem modelData

            implicitWidth: Theme.barButton
            implicitHeight: 30
            radius: 9
            color: mouse.containsMouse || menu.visible ? Theme.surfaceHover : "transparent"

            IconImage {
                anchors.centerIn: parent
                implicitSize: Theme.iconSize
                source: item.modelData.icon
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: event => {
                    if (event.button === Qt.MiddleButton)
                        item.modelData.secondaryActivate();
                    else if (event.button === Qt.LeftButton && !item.modelData.onlyMenu)
                        item.modelData.activate();
                    else if (item.modelData.hasMenu)
                        menu.open = !menu.open;
                }
                onWheel: event => item.modelData.scroll(event.angleDelta.y, false)
            }

            MenuPopup {
                id: menu

                anchorItem: item
                handle: item.modelData.menu
            }
        }
    }
}
