import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs

// Shell-drawn menu for a QsMenuHandle (tray item menus, i.e. DBusMenu),
// replacing the native Qt menu. It opens to the left of its anchor, as the bar
// is on the right; submenus are further MenuPopups beside their entry.
// Toggle with `open`, not `visible`. Closes on click outside or Escape, and
// when another menu opens (Popouts.menu).
PopupWindow {
    id: root

    required property Item anchorItem
    required property var handle
    property bool submenu: false
    property bool open: false
    // the submenu currently showing, so opening another closes it
    property var openChild: null

    // an entry somewhere down the chain was activated
    signal activated

    // Entries arrive asynchronously. Mapping only once they are here keeps the
    // popup from resizing while mapped, which at fractional scale leaves a
    // stale, stretched frame (Quickshell 0.3.1 / Qt 6.11).
    visible: open && (submenu || Popouts.menu === root) && opener.children.values.length > 0
    onOpenChanged: {
        if (!submenu)
            Popouts.menuToggled(root);
    }
    onVisibleChanged: {
        if (visible)
            return;
        open = false;
        if (openChild)
            openChild.open = false;
    }

    implicitWidth: Math.max(150, column.implicitWidth) + Theme.spacing * 2
    implicitHeight: column.implicitHeight + Theme.spacing * 2
    color: "transparent"
    grabFocus: true
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Left
    // the root menu clears the bar plus a small gap; submenus touch their parent
    anchor.margins.left: submenu ? 0 : -(Theme.barWidth - anchorItem.width) / 2 - Theme.spacing
    // with no room on the left, open on the right instead of covering the anchor
    anchor.adjustment: PopupAdjustment.FlipX | PopupAdjustment.SlideY

    QsMenuOpener {
        id: opener

        menu: root.handle
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius * 2
        color: Theme.bg
        border.width: 1.5
        border.color: Theme.surface
        focus: true
        Keys.onEscapePressed: root.open = false
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
                    color: mouse.containsMouse || (child.item?.visible ?? false) ? Theme.surfaceHover : Theme.none
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

                    cursorShape: Qt.PointingHandCursor
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
