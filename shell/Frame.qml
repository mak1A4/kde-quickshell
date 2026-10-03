import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.widgets

// One transparent surface over the whole screen. It draws the border, the bar
// on the right, and every panel that slides out of them. Only the border, bar
// and open panels take input; the rest passes through to the windows below.
PanelWindow {
    id: root

    readonly property real innerRight: width - Theme.barWidth
    readonly property bool popoutOpen: Popouts.current !== "" && within(Popouts.anchorItem, bar)

    // Hovered item with a hint. A hint waits Theme.hintDelay before it first
    // appears; once one is showing, moving to another item switches at once.
    // Hints yield to an open popout.
    readonly property Item wantedHint: !popoutOpen && (Popouts.hintItem?.hintTitle ?? "") !== "" ? Popouts.hintItem : null
    property Item shownHint: null
    readonly property Item barHint: within(shownHint, bar) ? shownHint : null
    readonly property Item dockHintItem: within(shownHint, dock) ? shownHint : null

    function within(item, ancestor) {
        for (let p = item; p; p = p.parent)
            if (p === ancestor)
                return true;
        return false;
    }

    onWantedHintChanged: {
        if (!wantedHint) {
            hintShow.stop();
            hintHide.restart();
            return;
        }
        hintHide.stop();
        if (shownHint)
            shownHint = wantedHint;
        else
            hintShow.restart();
    }

    Timer {
        id: hintShow

        interval: Theme.hintDelay
        onTriggered: root.shownHint = root.wantedHint
    }

    // short grace, so crossing the gap between two buttons doesn't close it
    Timer {
        id: hintHide

        interval: 120
        onTriggered: root.shownHint = null
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
    // KWin maps the layer-shell namespace to a window type. "dock" makes this
    // a panel: it stays when all windows are hidden (show desktop), and window
    // effects leave it alone. Any other name is a normal window to KWin.
    WlrLayershell.namespace: "dock"
    WlrLayershell.keyboardFocus: popoutOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        // The click-through hole. It closes while a popout is open, so a
        // click anywhere outside the popout reaches us and dismisses it.
        x: Theme.frameBorder
        y: Theme.frameBorder
        width: root.popoutOpen ? 0 : root.innerRight - Theme.frameBorder
        height: root.popoutOpen ? 0 : root.height - Theme.frameBorder * 2
        intersection: Intersection.Xor

        Region {
            x: dock.area.x
            y: dock.area.y
            width: dock.area.width
            height: dock.area.height
            intersection: Intersection.Subtract
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.popoutOpen
        acceptedButtons: Qt.AllButtons
        onPressed: Popouts.close()
    }

    // Border and panel backgrounds, as one merged shape (see the shader),
    // with a soft shadow onto the windows below.
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
        }

        ShaderEffect {
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("file://" + Quickshell.shellPath("shaders/frame.frag.qsb"))

            readonly property vector2d resolution: Qt.vector2d(width, height)
            readonly property vector4d inner: {
                const left = Theme.frameBorder, top = Theme.frameBorder;
                const right = root.innerRight, bottom = root.height - Theme.frameBorder;
                return Qt.vector4d((left + right) / 2, (top + bottom) / 2, (right - left) / 2, (bottom - top) / 2);
            }
            readonly property real innerRadius: Theme.frameRounding
            readonly property real panelRadius: Theme.panelRounding
            readonly property real smoothing: Theme.panelSmoothing
            readonly property color color: Theme.bg
            readonly property vector4d panel0: dock.blob
            readonly property vector4d panel1: popout.blob
            readonly property vector4d panel2: barHintPanel.blob
            readonly property vector4d bubble: dockHint.blob
            readonly property real bubbleRadius: 12
            readonly property color bubbleColor: Theme.tooltipBg
            readonly property real bubbleOpacity: dockHint.opacity
        }
    }

    Dock {
        id: dock

        anchors.fill: parent
    }

    // popout of the bar module that asked for one, beside its button
    SidePanel {
        id: popout

        function track() {
            if (root.popoutOpen)
                anchorY = Popouts.anchorItem.mapToItem(null, 0, Popouts.anchorItem.height / 2).y;
        }

        edgeX: root.innerRight
        // keeps the fillets clear of the frame's corners
        minY: Theme.frameBorder + Theme.frameRounding + Theme.panelSmoothing
        maxY: root.height - Theme.frameBorder - Theme.frameRounding - Theme.panelSmoothing
        open: root.popoutOpen
        contentWidth: Theme.popupWidth
        contentHeight: content.item?.implicitHeight ?? 0
        focus: root.popoutOpen
        Keys.onEscapePressed: Popouts.close()

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

            // stays loaded until it has slid back in
            active: root.popoutOpen || !popout.hidden
            sourceComponent: Popouts.content
            width: Theme.popupWidth
        }
    }

    // hint for a hovered bar button. Not in the input region; it is only looked at.
    SidePanel {
        id: barHintPanel

        edgeX: root.innerRight
        minY: popout.minY
        maxY: popout.maxY
        open: root.barHint !== null
        contentWidth: barHintText.implicitWidth + Theme.padding * 2 + Theme.spacing
        contentHeight: barHintText.implicitHeight + Theme.padding * 2

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

    // Hint for a hovered dock icon: a bubble in its own colour, floating just
    // above the dock. The bubble is drawn by the frame shader (`blob`), so it
    // shares the shadow; this item places the text and carries the fade.
    Item {
        id: dockHint

        readonly property bool showing: root.dockHintItem !== null && dock.shown
        // horizontal centre of the hovered icon, in window coordinates
        property real anchorX: 0
        property real w: dockHintText.implicitWidth + Theme.padding * 2
        readonly property real h: dockHintText.implicitHeight + Theme.spacing * 2
        readonly property real gap: 9
        // it lifts this far into place while fading in
        property real lift: showing ? 0 : 6

        readonly property vector4d blob: opacity > 0 ? Qt.vector4d(x + w / 2, y + h / 2, w / 2, h / 2) : Qt.vector4d(0, 0, 0, 0)

        x: Math.max(Theme.frameBorder + Theme.spacing, Math.min(root.innerRight - Theme.spacing - w, anchorX - w / 2))
        y: dock.area.y - gap - h + lift
        width: w
        height: h
        opacity: showing ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                kind: Anim.Fade
            }
        }

        Behavior on lift {
            Anim {}
        }

        // glide along with the pointer once showing
        Behavior on anchorX {
            enabled: dockHint.visible

            Anim {}
        }

        Behavior on w {
            enabled: dockHint.visible

            Anim {}
        }

        Connections {
            target: root

            function onDockHintItemChanged() {
                if (root.dockHintItem)
                    dockHint.anchorX = root.dockHintItem.mapToItem(null, root.dockHintItem.width / 2, 0).x;
            }
        }

        Hint {
            id: dockHintText

            x: Theme.padding
            y: Theme.spacing
            source: root.dockHintItem
            titleColor: Theme.tooltipFg
            lineColor: Qt.alpha(Theme.tooltipFg, 0.75)
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
