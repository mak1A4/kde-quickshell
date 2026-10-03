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

    // hovered item with a hint, split by where it lives; hints yield to popouts
    readonly property Item hintItem: !popoutOpen && (Popouts.hintItem?.hintTitle ?? "") !== "" ? Popouts.hintItem : null
    readonly property Item barHint: within(hintItem, bar) ? hintItem : null
    readonly property Item dockHint: within(hintItem, dock) ? hintItem : null

    function within(item, ancestor) {
        for (let p = item; p; p = p.parent)
            if (p === ancestor)
                return true;
        return false;
    }

    function owns(item) {
        return within(item, bar);
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

    // hint for a hovered bar button: a small panel growing out of the bar.
    // Not in the input region; it is only looked at.
    AttachedShape {
        x: barHintPanel.x
        y: barHintPanel.y
        width: barHintPanel.width
        height: barHintPanel.height
        edge: Qt.RightEdge
    }

    Item {
        id: barHintPanel

        property real anchorY: 0
        readonly property real minY: Theme.frameBorder + Theme.frameRounding + Theme.panelRounding
        readonly property real maxY: root.height - Theme.frameBorder - Theme.frameRounding - Theme.panelRounding - height

        x: root.width - Theme.barWidth - width
        y: Math.max(minY, Math.min(maxY, anchorY - height / 2))
        width: root.barHint ? barHintText.implicitWidth + Theme.padding * 2 + Theme.spacing : 0
        height: barHintText.implicitHeight + Theme.padding * 2
        clip: true

        Behavior on width {
            Anim {}
        }

        Behavior on y {
            enabled: barHintPanel.width > 0

            Anim {}
        }

        Connections {
            target: root

            function onBarHintChanged() {
                if (root.barHint)
                    barHintPanel.anchorY = root.barHint.mapToItem(null, 0, root.barHint.height / 2).y;
            }
        }

        Hint {
            id: barHintText

            x: Theme.padding + Theme.spacing
            y: Theme.padding
            source: root.barHint
        }
    }

    // hint for a hovered dock icon: a bubble above it
    Rectangle {
        id: dockHintBubble

        property real anchorX: 0

        x: Math.max(Theme.frameBorder + Theme.spacing, Math.min(root.width - Theme.barWidth - Theme.spacing - width, anchorX - width / 2))
        y: dock.panel.y - height - Theme.spacing
        width: dockHintText.implicitWidth + Theme.padding * 2
        height: dockHintText.implicitHeight + Theme.spacing * 2
        radius: Theme.radius * 2
        color: Theme.bg
        opacity: root.dockHint && dock.shown ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        Connections {
            target: root

            function onDockHintChanged() {
                if (root.dockHint)
                    dockHintBubble.anchorX = root.dockHint.mapToItem(null, root.dockHint.width / 2, 0).x;
            }
        }

        Hint {
            id: dockHintText

            x: Theme.padding
            y: Theme.spacing
            source: root.dockHint
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
