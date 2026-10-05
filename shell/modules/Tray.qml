import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets
import "tray/symbols.js" as Symbols

// StatusNotifierItem tray. Takes no space when no app has registered an item.
// Left click activates, middle click is the secondary action, right click
// opens the item's menu, drawn by the shell (widgets/MenuPopup.qml).
//
// An item the user has chosen an icon for (BarItems.qml), or one listed in
// tray/symbols.js, is drawn as a one-colour icon like the rest of the bar,
// with a dot when its tooltip carries a count; any other keeps the icon it
// brings.
//
// Every item is a cell like any other in the bar (BarButton, and the bar's
// spacing between them), and its icon fills the same square whatever it is: a
// pixmap of any size, a theme icon or a glyph.
//
// An item the user has hidden (BarItems.qml) is not in the bar until the
// bar's arrow is clicked.
ColumnLayout {
    spacing: Theme.barSpacing
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        BarButton {
            id: item

            required property SystemTrayItem modelData
            readonly property string symbol: BarItems.icon(modelData)
            // its own icon is one of the icon theme's one-colour icons
            readonly property bool plain: BarItems.isPlain(Symbols.named(modelData.icon))
            readonly property string named: Symbols.named(modelData.icon)

            tucked: !BarItems.expanded && BarItems.hidden(modelData)
            hintTitle: modelData.tooltipTitle || modelData.title || modelData.id
            hintLines: modelData.tooltipDescription ? [modelData.tooltipDescription] : []
            active: menu.visible
            onClicked: button => {
                if (button === Qt.MiddleButton)
                    modelData.secondaryActivate();
                else if (button === Qt.LeftButton && !modelData.onlyMenu)
                    modelData.activate();
                else if (modelData.hasMenu)
                    menu.open = !menu.open;
            }
            onScrolled: steps => modelData.scroll(steps * 120, false)

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Theme.iconSize
                implicitHeight: Theme.iconSize

                // the item's own icon, as it comes
                IconImage {
                    anchors.fill: parent
                    visible: item.symbol === "" && !item.plain
                    source: visible ? item.modelData.icon : ""
                }

                // The item's own icon in the bar's colour, where it names
                // one of the icon theme's one-colour icons (BarItems).
                Icon {
                    anchors.fill: parent
                    visible: item.symbol === "" && item.plain
                    source: item.named
                }

                Icon {
                    // a glyph is drawn larger than the square, see symbols.js
                    readonly property int glyphSize: Symbols.size(item.symbol, Theme.iconSize)

                    anchors.centerIn: parent
                    width: glyphSize || Theme.iconSize
                    height: width
                    roundToIconSize: glyphSize === 0
                    visible: item.symbol !== ""
                    source: BarItems.source(item.symbol)
                }

                Rectangle {
                    anchors {
                        horizontalCenter: parent.right
                        verticalCenter: parent.top
                        horizontalCenterOffset: -1.5
                        verticalCenterOffset: 1.5
                    }
                    width: 9
                    height: 9
                    radius: 4.5
                    visible: item.symbol !== "" && Symbols.count(item.modelData.tooltipTitle) > 0
                    color: Theme.error
                }
            }

            MenuPopup {
                id: menu

                anchorItem: item
                handle: item.modelData.menu
            }
        }
    }
}
