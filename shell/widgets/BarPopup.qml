import Quickshell
import QtQuick
import qs

// Popup hanging below a bar item, right-aligned with it. Closes on click
// outside or Escape. Give it a constant implicitHeight: resizing a mapped
// popup at fractional scale leaves a stale, stretched frame.
PopupWindow {
    id: root

    required property Item anchorItem
    default property alias content: background.data

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    // clear the bar's bottom edge plus a small gap
    anchor.margins.bottom: -(Theme.barHeight - anchorItem.height) / 2 - Theme.spacing
    grabFocus: true
    implicitWidth: Theme.popupWidth
    color: "transparent"

    Rectangle {
        id: background

        anchors.fill: parent
        radius: Theme.radius * 2
        color: Theme.bg
        border.width: 1.5
        border.color: Theme.surface
        focus: true
        Keys.onEscapePressed: root.visible = false
    }
}
