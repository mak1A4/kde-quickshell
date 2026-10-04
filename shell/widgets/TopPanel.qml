import QtQuick
import qs

// A panel that slides down from behind the frame's top edge, at full size,
// and back up. While it is out, changing `contentWidth` or `contentHeight`
// resizes it in place, hanging from the edge. Fill the frame with this item;
// `blob` is the rectangle the frame shader draws as its background.
Item {
    id: root

    // y of the top border's inner edge and the panel's horizontal centre
    required property real edgeY
    required property real centreX

    property bool open: false
    property real contentWidth: 0
    property real contentHeight: 0
    default property alias content: panel.data

    // 1 = fully behind the border, 0 = out; overshoots below 0 on the way out
    property real offset: open ? 0 : 1
    readonly property bool hidden: offset >= 1
    // Animated size. It follows the content only while open, so a closing
    // panel keeps its shape instead of collapsing as it slides away.
    property real w: 0
    property real h: 0
    // room on the free sides for the overshoot
    readonly property real slack: 36
    // left edge, on a whole device pixel (see "Sizes" in docs/decisions.md)
    readonly property real leftX: Math.round((centreX - w / 2) / 3) * 3

    // the part that is out, for the frame's input region
    readonly property rect area: hidden ? Qt.rect(0, 0, 0, 0) : Qt.rect(leftX, edgeY, w, Math.max(0, panel.y + h))

    // background rectangle: from well inside the border to the panel's lower edge
    readonly property vector4d blob: {
        if (hidden || w <= 0 || h <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        const top = edgeY - Theme.panelRounding;
        const bottom = edgeY + panel.y + h;
        if (bottom <= edgeY)
            return Qt.vector4d(0, 0, 0, 0);
        return Qt.vector4d(leftX + w / 2, (top + bottom) / 2, w / 2, (bottom - top) / 2);
    }

    Binding {
        root.w: root.contentWidth
        root.h: root.contentHeight
        when: root.open
        restoreMode: Binding.RestoreNone
    }

    Behavior on offset {
        Anim {}
    }

    // resize while showing, but appear at full size when opening
    Behavior on w {
        enabled: !root.hidden

        Anim {}
    }

    Behavior on h {
        enabled: !root.hidden

        Anim {}
    }

    // keeps the sliding panel from drawing over the border
    Item {
        x: root.leftX - root.slack
        y: root.edgeY
        width: root.w + root.slack * 2
        height: root.h + root.slack
        clip: true
        visible: !root.hidden

        // Exactly the background's size, and clipping: while the panel
        // resizes, content laid out for the final size is uncovered, never
        // drawn outside it.
        Item {
            id: panel

            x: root.slack
            y: -(root.h + Theme.panelSmoothing) * root.offset
            width: root.w
            height: root.h
            clip: true
        }
    }
}
