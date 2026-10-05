import QtQuick
import qs

// A panel in the frame's bottom left corner, joined to the left and the
// bottom border. It has whatever size its content asks for and resizes in
// place, growing out of the corner: a small tab can become a whole list.
// Size 0 is no panel. Fill the frame with this item; `blob` is the rectangle
// the frame shader draws as its background.
Item {
    id: root

    // the inner edges of the left and the bottom border
    required property real edgeX
    required property real edgeY

    property real contentWidth: 0
    property real contentHeight: 0
    default property alias content: panel.data

    // animated size
    property real w: contentWidth
    property real h: contentHeight

    // the part that shows, for the frame's input region
    readonly property rect area: Qt.rect(edgeX, edgeY - Math.max(0, h), Math.max(0, w), Math.max(0, h))
    // background rectangle: from well inside both borders to the panel's free edges
    readonly property vector4d blob: {
        if (w < 1 || h < 1)
            return Qt.vector4d(0, 0, 0, 0);
        const left = edgeX - Theme.panelRounding, right = edgeX + w;
        const top = edgeY - h, bottom = edgeY + Theme.panelRounding;
        return Qt.vector4d((left + right) / 2, (top + bottom) / 2, (right - left) / 2, (bottom - top) / 2);
    }

    Behavior on w {
        Anim {}
    }

    Behavior on h {
        Anim {}
    }

    // Exactly the background's size, and clipping: content laid out for the
    // final size is uncovered as the panel grows, never drawn outside it.
    Item {
        id: panel

        x: root.edgeX
        y: root.edgeY - height
        width: Math.max(0, root.w)
        height: Math.max(0, root.h)
        clip: true
    }
}
