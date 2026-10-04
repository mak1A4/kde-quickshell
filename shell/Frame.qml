import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.notifications
import qs.palette
import qs.widgets

// One transparent surface over the whole screen. It draws the border, the bar
// on the right, and every panel that slides out of them. Only the border, bar
// and open panels take input; the rest passes through to the windows below.
PanelWindow {
    id: root

    readonly property real innerRight: width - Theme.barWidth
    readonly property bool popoutOpen: Popouts.current !== "" && within(Popouts.anchorItem, bar)
    // a popout, the launcher or the palette: something that a click elsewhere dismisses
    readonly property bool modal: popoutOpen || dock.launcherOpen || commandPalette.showing

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
    // the launcher and the palette are typed into, so they take the keyboard
    // outright; a popout only gets it once clicked
    WlrLayershell.keyboardFocus: dock.launcherOpen || commandPalette.showing ? WlrKeyboardFocus.Exclusive : (popoutOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)

    mask: Region {
        // The click-through hole. It closes while a popout, the launcher or
        // the palette is open, so a click anywhere outside reaches us and
        // dismisses it.
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

        // notification popups take the pointer too
        Region {
            x: notificationPanel.area.x
            y: notificationPanel.area.y
            width: notificationPanel.area.width
            height: notificationPanel.area.height
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
            CommandPalette.hide();
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
            readonly property vector4d panel2: commandPalette.blob
            readonly property vector4d panel3: notificationPanel.blob
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

    // The command palette, hanging from the top edge. Its content exists
    // only while open (and until it has faded out).
    TopPanel {
        id: commandPalette

        readonly property bool showing: CommandPalette.open && (CommandPalette.screen === null || CommandPalette.screen === root.screen)

        anchors.fill: parent
        edgeY: Theme.frameBorder
        centreX: (Theme.frameBorder + root.innerRight) / 2
        open: showing
        // fallbacks for the instant before the loader has the content
        contentWidth: paletteLoader.item?.implicitWidth ?? 660
        contentHeight: paletteLoader.item?.implicitHeight ?? 69

        // clicks on the palette must not reach the dismiss area underneath
        MouseArea {
            anchors.fill: parent
            enabled: commandPalette.showing
            acceptedButtons: Qt.AllButtons
        }

        Loader {
            id: paletteLoader

            active: commandPalette.showing || opacity > 0
            opacity: commandPalette.showing ? 1 : 0
            sourceComponent: PalettePanel {}

            Behavior on opacity {
                Anim {
                    kind: Anim.Fade
                }
            }
        }
    }

    // Notification popups, hanging from the top edge against the bar, on the
    // first screen. They step aside while the palette is open: the two would
    // touch, and what is being typed comes first.
    TopPanel {
        id: notificationPanel

        readonly property bool here: root.screen === Quickshell.screens[0]
        readonly property bool showing: (popups.item?.count ?? 0) > 0 && !commandPalette.showing

        anchors.fill: parent
        edgeY: Theme.frameBorder
        // its background runs on under the bar, so the two join
        centreX: root.innerRight + Theme.panelRounding - contentWidth / 2
        open: showing
        contentWidth: (popups.item?.implicitWidth ?? 0) + Theme.panelRounding
        contentHeight: popups.item?.implicitHeight ?? 0

        // clicks between the cards go nowhere
        MouseArea {
            anchors.fill: parent
            enabled: notificationPanel.showing
            acceptedButtons: Qt.AllButtons
        }

        Loader {
            id: popups

            active: notificationPanel.here && Notifications.popups !== null
            sourceComponent: Popups {
                notifications: Notifications.popups
                timeout: Notifications.backend.popupTimeout
                paused: !notificationPanel.showing
            }
        }
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
                SwapFade {
                    incoming: sidePanel.hinting
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
                SwapFade {
                    incoming: root.popoutOpen
                }
            }
        }
    }

    // Hint for a hovered dock icon: a bubble in its own colour, floating just
    // above the dock. The bubble is drawn by the frame shader (`blob`), so it
    // shares the shadow; this item places the text and carries the fade.
    Item {
        id: dockHint

        readonly property bool showing: root.dockHintItem !== null && dock.shown && !dock.launcherOpen
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

        // When the launcher opens the tooltip goes at once: fading and
        // sinking next to a dock that is growing into something else looks
        // like two animations fighting.
        Behavior on opacity {
            enabled: !dock.launcherOpen

            Anim {
                kind: Anim.Fade
            }
        }

        Behavior on lift {
            enabled: !dock.launcherOpen

            Anim {}
        }

        Connections {
            target: dock

            // and it must not come back by itself when the launcher closes
            function onLauncherOpenChanged() {
                if (dock.launcherOpen) {
                    hintShow.stop();
                    root.shownHint = null;
                }
            }
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
