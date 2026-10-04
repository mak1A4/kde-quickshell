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
    // a popout or the launcher: something that a click elsewhere dismisses
    readonly property bool modal: popoutOpen || dock.launcherOpen

    // Hovered item with a hint. A hint waits Theme.hintDelay before it first
    // appears; once one is showing, moving to another item switches at once.
    // Hints yield to an open popout.
    readonly property Item wantedHint: !modal && (Popouts.hintItem?.hintTitle ?? "") !== "" ? Popouts.hintItem : null
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
        // no delay if a hint is showing, or the side panel is still out from a
        // popout that just closed: it then shrinks straight back to the hint
        if (shownHint || !sidePanel.hidden)
            shownHint = wantedHint;
        else
            hintShow.restart();
    }

    Timer {
        id: hintShow

        interval: Theme.hintDelay
        onTriggered: root.shownHint = root.wantedHint
    }

    // Short grace before a hint goes away, so crossing the gap between two
    // buttons doesn't close it. It then settles on whatever is hovered by then.
    Timer {
        id: hintHide

        interval: 150
        onTriggered: root.shownHint = root.wantedHint
    }

    // A popout closed by its own button turns back into that button's hint,
    // decided here and not by hover state: in the middle of a click the hover
    // state can read "not hovered" for a moment, and the panel would slide
    // away and come back. The grace timer then checks what is really hovered.
    Connections {
        target: Popouts

        function onClosing(anchorItem, byOwner) {
            if (!byOwner || !root.within(anchorItem, bar) || (anchorItem.hintTitle ?? "") === "")
                return;
            hintShow.stop();
            root.shownHint = anchorItem;
            hintHide.restart();
        }
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
    // the launcher is typed into, so it takes the keyboard outright; a
    // popout only gets it once clicked
    WlrLayershell.keyboardFocus: dock.launcherOpen ? WlrKeyboardFocus.Exclusive : (popoutOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)

    mask: Region {
        // The click-through hole. It closes while a popout or the launcher
        // is open, so a click anywhere outside reaches us and dismisses it.
        x: Theme.frameBorder
        y: Theme.frameBorder
        width: root.modal ? 0 : root.innerRight - Theme.frameBorder
        height: root.modal ? 0 : root.height - Theme.frameBorder * 2
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
        enabled: root.modal
        acceptedButtons: Qt.AllButtons
        onPressed: {
            Popouts.close();
            Launcher.hide();
        }
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
            readonly property vector4d panel1: sidePanel.blob
            readonly property vector4d panel2: Qt.vector4d(0, 0, 0, 0)
            readonly property vector4d bubble: dockHint.blob
            readonly property real bubbleRadius: 12
            readonly property color bubbleColor: Theme.tooltipBg
            readonly property real bubbleOpacity: dockHint.opacity
        }
    }

    Dock {
        id: dock

        anchors.fill: parent
        screen: root.screen
    }

    // The one panel beside the bar. It shows the hint of the hovered button,
    // or the popout a button opened, and morphs between the two in place:
    // clicking a button grows its hint into the popout rather than swapping
    // one panel for another. Only the popout takes input.
    SidePanel {
        id: sidePanel

        readonly property bool hinting: !root.popoutOpen && root.barHint !== null
        // the button it currently belongs to
        readonly property Item anchorItem: root.popoutOpen ? Popouts.anchorItem : root.barHint

        onAnchorItemChanged: {
            if (anchorItem)
                anchorY = anchorItem.mapToItem(null, 0, anchorItem.height / 2).y;
        }

        edgeX: root.innerRight
        // keeps the fillets clear of the frame's corners
        minY: Theme.frameBorder + Theme.frameRounding + Theme.panelSmoothing
        maxY: root.height - Theme.frameBorder - Theme.frameRounding - Theme.panelSmoothing
        open: root.popoutOpen || root.barHint !== null
        contentWidth: root.popoutOpen ? (content.item?.implicitWidth ?? Theme.popupWidth) : barHintText.implicitWidth + Theme.padding * 2 + Theme.spacing
        contentHeight: root.popoutOpen ? (content.item?.implicitHeight ?? 0) : barHintText.implicitHeight + Theme.padding * 2
        focus: root.popoutOpen
        Keys.onEscapePressed: Popouts.close()

        // clicks inside a popout must not reach the dismiss area underneath
        MouseArea {
            anchors.fill: parent
            enabled: root.popoutOpen
            acceptedButtons: Qt.AllButtons
        }

        Hint {
            id: barHintText

            x: Theme.padding + Theme.spacing
            y: Theme.padding
            source: root.barHint
            opacity: sidePanel.hinting ? 1 : 0

            Behavior on opacity {
                Anim {
                    kind: Anim.Fade
                }
            }
        }

        // Held against the bar side: as the panel grows from hint to popout,
        // the popout's content stays put and is uncovered.
        Loader {
            id: content

            anchors.right: parent.right
            // stays loaded until it has faded out
            active: root.popoutOpen || opacity > 0
            sourceComponent: Popouts.content
            opacity: root.popoutOpen ? 1 : 0

            Behavior on opacity {
                Anim {
                    kind: Anim.Fade
                }
            }
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
