import QtQuick
import qs

// A panel that slides out from behind the bar's inner edge, at full size, and
// back in. While it is out, changing `contentWidth`, `contentHeight` or
// `anchorY` morphs it in place: it grows or shrinks around its anchor and
// glides to a new one. This item is only the clip (so nothing draws over the
// bar while sliding); `blob` is the rectangle the frame shader draws as its
// background.
Item {
    id: root

    // x of the bar's inner edge and the vertical range available, in parent coordinates
    required property real edgeX
    required property real minY
    required property real maxY

    property bool open: false
    // vertical centre the panel aims for
    property real anchorY: 0
    property real contentWidth: 0
    property real contentHeight: 0
    default property alias content: slider.data

    // 1 = fully behind the bar, 0 = out; overshoots below 0 on the way out
    property real offset: open ? 0 : 1
    readonly property bool hidden: offset >= 1
    // Animated size and anchor. They follow the content only while open, so a
    // closing panel keeps its shape instead of collapsing as it slides away.
    property real w: 0
    property real h: 0
    property real centre: 0
    // room on the free side for the overshoot
    readonly property real slack: 36

    // background rectangle: from the content's leading edge to well inside the bar
    readonly property vector4d blob: {
        if (hidden || w <= 0 || h <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        const left = x + slider.x;
        const right = edgeX + Theme.panelRounding;
        return Qt.vector4d((left + right) / 2, y + h / 2, (right - left) / 2, h / 2);
    }

    x: edgeX - w - slack
    // y is derived, not animated itself: it then stays centred on the anchor
    // through every frame of a size change
    y: Math.max(minY, Math.min(maxY - h, centre - h / 2))
    width: w + slack
    height: h
    visible: !hidden

    Binding {
        root.w: root.contentWidth
        root.h: root.contentHeight
        root.centre: root.anchorY
        when: root.open
        restoreMode: Binding.RestoreNone
    }

    Behavior on offset {
        Anim {}
    }

    // morph while showing, but appear in place when opening
    Behavior on centre {
        enabled: !root.hidden

        Anim {}
    }

    Behavior on w {
        enabled: !root.hidden

        Anim {}
    }

    Behavior on h {
        enabled: !root.hidden

        Anim {}
    }

    // Exactly the background's size, and clipping: while the panel grows,
    // content laid out for the final size is revealed, never drawn outside it.
    Item {
        id: slider

        x: root.slack + (root.w + Theme.panelSmoothing) * root.offset
        width: root.w
        height: root.h
        clip: true
    }
}
