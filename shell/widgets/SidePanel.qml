import QtQuick
import qs

// A panel that slides out from behind the bar's inner edge, at full size, and
// back in. This item is only the clip (so nothing draws over the bar while
// sliding); `blob` is the rectangle the frame shader draws as its background.
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
    // animated size, so switching content resizes smoothly
    property real w: contentWidth
    property real h: contentHeight
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
    y: Math.max(minY, Math.min(maxY - h, anchorY - h / 2))
    width: w + slack
    height: h
    clip: true
    visible: !hidden

    Behavior on offset {
        Anim {}
    }

    // glide while showing, but appear in place when opening
    Behavior on y {
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

    Item {
        id: slider

        x: root.slack + (root.w + Theme.panelSmoothing) * root.offset
        width: root.w
        height: root.h
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            Anim {
                kind: Anim.Fade
            }
        }
    }
}
