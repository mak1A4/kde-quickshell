import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.widgets

// One transparent surface over the whole screen. It draws the border, the bar
// on the right, and every panel that grows out of them. Only the border, bar
// and open panels take input; the rest passes through to the windows below.
PanelWindow {
    id: root

    readonly property bool popoutOpen: Popouts.current !== "" && owns(Popouts.anchorItem)

    function owns(item) {
        for (let p = item; p; p = p.parent)
            if (p === bar)
                return true;
        return false;
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // space is reserved by Exclusions.qml
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "kde-quickshell-frame"
    WlrLayershell.keyboardFocus: popoutOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        // The click-through hole. It closes while a popout is open, so a
        // click anywhere outside the popout reaches us and dismisses it.
        x: Theme.frameBorder
        y: Theme.frameBorder
        width: root.popoutOpen ? 0 : root.width - Theme.frameBorder - Theme.barWidth
        height: root.popoutOpen ? 0 : root.height - Theme.frameBorder * 2
        intersection: Intersection.Xor

        Region {
            x: dock.panel.x
            y: dock.panel.y
            width: dock.panel.width
            height: dock.panel.height
            intersection: Intersection.Subtract
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.popoutOpen
        acceptedButtons: Qt.AllButtons
        onPressed: Popouts.close()
    }

    // border, inner corners rounded by Theme.frameRounding; the right side is the bar
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Theme.bg
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill

            PathSvg {
                path: {
                    const w = root.width, h = root.height, k = Theme.frameRounding;
                    const l = Theme.frameBorder, t = Theme.frameBorder;
                    const r = w - Theme.barWidth, b = h - Theme.frameBorder;
                    return `M0,0 H${w} V${h} H0 Z M${l + k},${t} H${r - k} A${k},${k} 0 0 1 ${r},${t + k} V${b - k} A${k},${k} 0 0 1 ${r - k},${b} H${l + k} A${k},${k} 0 0 1 ${l},${b - k} V${t + k} A${k},${k} 0 0 1 ${l + k},${t} Z`;
                }
            }
        }
    }

    Dock {
        id: dock

        anchors.fill: parent
    }

    AttachedShape {
        x: popout.x
        y: popout.y
        width: popout.width
        height: popout.height
        edge: Qt.RightEdge
    }

    // popout of the bar module that asked for one, beside its button
    Item {
        id: popout

        // vertical centre of the button that opened it, in window coordinates
        property real anchorY: 0
        // keeps its fillets inside the bar's edge and clear of the frame's corners
        readonly property real minY: Theme.frameBorder + Theme.frameRounding + Theme.panelRounding
        readonly property real maxY: root.height - Theme.frameBorder - Theme.frameRounding - Theme.panelRounding - height

        function track() {
            if (root.popoutOpen)
                anchorY = Popouts.anchorItem.mapToItem(null, 0, Popouts.anchorItem.height / 2).y;
        }

        x: root.width - Theme.barWidth - width
        y: Math.max(minY, Math.min(maxY, anchorY - height / 2))
        width: root.popoutOpen ? Theme.popupWidth : 0
        height: content.item?.implicitHeight ?? 0
        clip: true
        focus: root.popoutOpen
        Keys.onEscapePressed: Popouts.close()

        Behavior on width {
            Anim {}
        }

        // glide between buttons, but appear in place when opening
        Behavior on y {
            enabled: popout.width > 0

            Anim {}
        }

        Connections {
            target: Popouts

            function onCurrentChanged() {
                popout.track();
            }
        }

        // clicks inside must not reach the dismiss area underneath
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Loader {
            id: content

            // stays loaded until the closing animation has finished
            active: root.popoutOpen || popout.width > 0
            sourceComponent: Popouts.content
            width: Theme.popupWidth
            opacity: root.popoutOpen ? 1 : 0

            Behavior on opacity {
                Anim {}
            }
        }
    }

    Bar {
        id: bar

        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
        }
        width: Theme.barWidth
    }
}
