import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs

// Shell-drawn menu for a QsMenuHandle (tray item menus, i.e. DBusMenu),
// replacing the native Qt menu. Submenus open as further MenuPopups beside
// their entry. Toggle with `open`, not `visible`.
BarPopup {
    id: root

    required property var handle
    property bool submenu: false
    property bool open: false
    // the submenu currently showing, so opening another closes it
    property var openChild: null

    // an entry somewhere down the chain was activated
    signal activated

    // Entries arrive asynchronously. Mapping only once they are here keeps the
    // popup from resizing while mapped (see BarPopup).
    visible: open && opener.children.values.length > 0
    onVisibleChanged: {
        if (visible)
            return;
        open = false;
        if (openChild)
            openChild.open = false;
    }

    implicitWidth: Math.max(150, column.implicitWidth) + Theme.spacing * 2
    implicitHeight: column.implicitHeight + Theme.spacing * 2
    anchor.edges: submenu ? Edges.Top | Edges.Right : Edges.Bottom | Edges.Right
    anchor.gravity: submenu ? Edges.Bottom | Edges.Right : Edges.Bottom | Edges.Left
    anchor.margins.bottom: submenu ? 0 : -(Theme.barHeight - anchorItem.height) / 2 - Theme.spacing
    // a submenu with no room on the right opens on the left instead of covering its entry
    anchor.adjustment: submenu ? PopupAdjustment.FlipX | PopupAdjustment.SlideY : PopupAdjustment.Slide

    QsMenuOpener {
        id: opener

        menu: root.handle
    }

    ColumnLayout {
        id: column

        anchors {
            fill: parent
            margins: Theme.spacing
        }
        spacing: 0

        Repeater {
            model: opener.children

            Item {
                id: entry

                required property QsMenuEntry modelData
                readonly property bool separator: modelData.isSeparator
                readonly property bool checked: modelData.checkState !== Qt.Unchecked

                function activate() {
                    if (!modelData.hasChildren) {
                        modelData.triggered();
                        root.activated();
                        root.open = false;
                        return;
                    }
                    // created on first use; a type cannot instantiate itself directly
                    if (!child.item)
                        child.setSource(Qt.resolvedUrl("MenuPopup.qml"), {
                            handle: modelData,
                            anchorItem: entry,
                            submenu: true
                        });
                    const wasOpen = child.item.open;
                    if (root.openChild)
                        root.openChild.open = false;
                    root.openChild = wasOpen ? null : child.item;
                    child.item.open = !wasOpen;
                }

                Layout.fillWidth: true
                implicitWidth: row.implicitWidth + Theme.padding * 2
                implicitHeight: separator ? 9 : 27

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.alignWhenCentered: false
                    visible: entry.separator
                    width: parent.width
                    height: 1.5
                    color: Theme.surface
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !entry.separator
                    radius: Theme.radius
                    color: mouse.containsMouse || (child.item?.visible ?? false) ? Theme.surfaceHover : "transparent"
                }

                RowLayout {
                    id: row

                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Theme.padding
                        rightMargin: Theme.padding
                    }
                    visible: !entry.separator
                    spacing: Theme.spacing

                    // check box or radio button
                    Rectangle {
                        readonly property bool radio: entry.modelData.buttonType === QsMenuButtonType.RadioButton

                        visible: entry.modelData.buttonType !== QsMenuButtonType.None
                        implicitWidth: 15
                        implicitHeight: 15
                        radius: radio ? 7.5 : 3
                        color: "transparent"
                        border.width: 1.5
                        border.color: entry.checked ? Theme.accent : Theme.fgDim

                        Rectangle {
                            anchors.centerIn: parent
                            anchors.alignWhenCentered: false
                            visible: entry.checked
                            width: 7.5
                            height: 7.5
                            radius: parent.radio ? 3.75 : 1.5
                            color: Theme.accent
                        }
                    }

                    IconImage {
                        visible: entry.modelData.icon !== ""
                        implicitSize: Theme.iconSize
                        source: entry.modelData.icon
                    }

                    Label {
                        Layout.fillWidth: true
                        color: entry.modelData.enabled ? Theme.fg : Theme.fgDim
                        text: entry.modelData.text
                    }

                    Icon {
                        visible: entry.modelData.hasChildren
                        source: "go-next-symbolic"
                    }
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    enabled: !entry.separator && entry.modelData.enabled
                    hoverEnabled: true
                    onClicked: entry.activate()
                }

                Loader {
                    id: child
                }

                Connections {
                    target: child.item

                    function onActivated() {
                        root.activated();
                        root.open = false;
                    }
                }
            }
        }
    }
}
