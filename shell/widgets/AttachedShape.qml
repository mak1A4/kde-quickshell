import QtQuick
import QtQuick.Shapes
import qs

// Background of a panel that grows out of the frame: convex corners on its
// free side, concave fillets where it meets the frame. The fillets are drawn
// outside the item's own rectangle. `edge` is the frame edge it hangs on.
Shape {
    id: root

    property int edge: Qt.RightEdge
    property real rounding: Theme.panelRounding

    // shrinks while the panel is nearly closed, so the arcs never overlap
    readonly property real r: Math.min(rounding, (edge === Qt.BottomEdge ? height : width) / 2)
    readonly property real w: width
    readonly property real h: height

    visible: width > 0 && height > 0
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: Theme.bg
        strokeWidth: -1

        PathSvg {
            path: {
                const r = root.r, w = root.w, h = root.h;
                if (root.edge === Qt.BottomEdge)
                    return `M${-r},${h} A${r},${r} 0 0 0 0,${h - r} L0,${r} A${r},${r} 0 0 1 ${r},0 L${w - r},0 A${r},${r} 0 0 1 ${w},${r} L${w},${h - r} A${r},${r} 0 0 0 ${w + r},${h} Z`;
                return `M${w},${-r} A${r},${r} 0 0 1 ${w - r},0 L${r},0 A${r},${r} 0 0 0 0,${r} L0,${h - r} A${r},${r} 0 0 0 ${r},${h} L${w - r},${h} A${r},${r} 0 0 1 ${w},${h + r} Z`;
            }
        }
    }
}
