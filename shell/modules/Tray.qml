import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// StatusNotifierItem tray. Hidden when no app has registered an item.
// Left click activates, middle click is the secondary action, right click
// opens the item's menu, drawn by the shell (widgets/MenuPopup.qml).
Pill {
    id: root

    visible: SystemTray.items.values.length > 0
    interactive: false

    Repeater {
        model: SystemTray.items

        MouseArea {
            id: item

            required property SystemTrayItem modelData

            implicitWidth: Theme.iconSize
            implicitHeight: Theme.iconSize
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: event => {
                if (event.button === Qt.MiddleButton)
                    modelData.secondaryActivate();
                else if (event.button === Qt.LeftButton && !modelData.onlyMenu)
                    modelData.activate();
                else if (modelData.hasMenu)
                    menu.open = !menu.open;
            }
            onWheel: event => modelData.scroll(event.angleDelta.y, false)

            IconImage {
                anchors.fill: parent
                source: item.modelData.icon
            }

            MenuPopup {
                id: menu

                anchorItem: item
                handle: item.modelData.menu
            }
        }
    }
}
