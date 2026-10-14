import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.notifications
import qs.palette
import qs.picker
import qs.widgets

// One transparent surface over the whole screen. It draws the border, the bar
// on the right, and every panel that slides out of them. Only the border, bar
// and open panels take input; the rest passes through to the windows below.
PanelWindow {
    id: root

    readonly property real innerRight: width - Theme.barWidth
    readonly property bool popoutOpen: Popouts.current !== "" && within(Popouts.anchorItem, bar)
    // a popout, the launcher or the palette: something that a click elsewhere dismisses
    readonly property bool modal: popoutOpen || dock.launcherOpen || commandPalette.showing || notificationCorner.listOpen

    // Hovered item with a hint. A hint waits Theme.hintDelay before it first
    // appears; once one is showing, moving to another item switches at once.
    // Hints yield to an open popout, and to an open menu.
    readonly property Item wantedHint: !modal && !Popouts.menuOpen && (Popouts.hintItem?.hintTitle ?? "") !== "" ? Popouts.hintItem : null
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
    // outright; a popout only gets it once clicked. The notification list
    // takes it outright as well, for Escape: getting it on a click, the shell
    // stayed the active window after the list had closed, and the window
    // being worked in had to be clicked to type again. KWin gives the
    // keyboard back when an exclusive surface lets go.
    WlrLayershell.keyboardFocus: dock.launcherOpen || commandPalette.showing || notificationCorner.listOpen ? WlrKeyboardFocus.Exclusive : (popoutOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)

    // KWin leaves this surface the active window when it stops asking for the
    // keyboard, so the window that had it before is activated again
    // (LastWindow.qml). Not if another window has become active meanwhile:
    // one picked in the palette, or one opened by what was run, which is
    // given `windowWait` to appear.
    Item {
        id: keyboard

        readonly property bool wanted: root.WlrLayershell.keyboardFocus !== WlrKeyboardFocus.None
        readonly property bool held: Window.active
        readonly property int windowWait: 2000

        // Its task model needs to have loaded by the time it is asked. And
        // a reload while the frame had the keyboard leaves it with it.
        Component.onCompleted: {
            LastWindow.last;
            giveBack.interval = 300;
            giveBack.start();
        }
        onWantedChanged: {
            if (wanted) {
                giveBack.stop();
                LastWindow.remember(held);
                return;
            }
            // the surface's new state has to reach KWin first
            giveBack.interval = LastWindow.expecting ? windowWait : 60;
            LastWindow.expecting = false;
            giveBack.restart();
        }

        Timer {
            id: giveBack

            onTriggered: {
                if (!keyboard.wanted && keyboard.held)
                    LastWindow.giveBack();
            }
        }
    }

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

        // the notification light in the corner
        Region {
            x: Theme.frameBorder
            y: root.height - Theme.frameBorder - notificationCorner.button
            width: notificationCorner.button
            height: notificationCorner.button
            intersection: Intersection.Subtract
        }

        // notification popups take the pointer too (the open list has
        // all of it anyway)
        Region {
            x: notificationCorner.area.x
            y: notificationCorner.area.y
            width: notificationCorner.area.width
            height: notificationCorner.area.height
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
            Notifications.listOpen = false;
        }
    }

    // Border and panel backgrounds, as one merged shape (see the shader),
    // with a soft shadow onto the windows below. The Loader that makes one
    // says its colour (`tint`) and how far it is glass (`glassy`, 0 for the
    // solid shape).
    Component {
        id: shape

        ShaderEffect {
            fragmentShader: Qt.resolvedUrl("file://" + Quickshell.shellPath("shaders/frame.frag.qsb"))

            readonly property vector2d resolution: Qt.vector2d(width, height)
            readonly property vector4d inner: {
                const hole = root.hole;
                return Qt.vector4d((hole.x + hole.z) / 2, (hole.y + hole.w) / 2, (hole.z - hole.x) / 2, (hole.w - hole.y) / 2);
            }
            readonly property real innerRadius: Theme.frameRounding
            readonly property real cornerRadius: notificationCorner.corner
            readonly property real panelRadius: Theme.panelRounding
            readonly property real smoothing: Theme.panelSmoothing
            readonly property color color: parent.tint
            readonly property vector4d panel0: dock.blob
            readonly property vector4d panel1: sidePanel.blob
            readonly property vector4d panel2: commandPalette.blob
            // free since the notification popups moved into the corner (panel4)
            readonly property vector4d panel3: Qt.vector4d(0, 0, 0, 0)
            readonly property vector4d panel4: notificationCorner.blob
            // free since the AI panel was removed
            readonly property vector4d panel5: Qt.vector4d(0, 0, 0, 0)
            readonly property vector4d bubble: dockHint.blob
            readonly property real bubbleRadius: 12
            readonly property color bubbleColor: Theme.tooltipBg
            readonly property real bubbleOpacity: dockHint.opacity
            readonly property real glass: parent.glassy
            readonly property real rim: Theme.glassRim
        }
    }

    // what the border leaves free: left, top, right, bottom
    readonly property vector4d hole: Qt.vector4d(Theme.frameBorder, Theme.frameBorder, innerRight, height - Theme.frameBorder)

    // the solid frame, casting its shadow
    Item {
        anchors.fill: parent
        visible: !Theme.glass
        layer.enabled: !Theme.glass
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
        }

        Loader {
            property color tint: Theme.bg
            property real glassy: 0

            anchors.fill: parent
            active: !Theme.glass
            sourceComponent: shape
        }
    }

    // ---- glass ---------------------------------------------------------------
    //
    // With `Theme.frameOpacity` below 1 the shape lets that much of what is
    // behind it through (the shader's `glass`), and the compositor is asked
    // to blur what is behind it (ext-background-effect-v1, through
    // Quickshell's BackgroundEffect: the protocol is Wayland's own, not
    // KDE's). Two things follow.
    //
    // The shadow cannot be cast the same way: it lies under the whole shape
    // as well as around it, and through glass it would be seen, a grey film
    // on everything. So the shadow is made from the shape drawn solid, which
    // is not shown itself, and the shape is cut out of it again.
    //
    // And the compositor has to be told where to blur, as rectangles and
    // ellipses, which the shape is not quite: see `blur` below.
    //
    // All of it is made when the glass is switched on, and gone when it is
    // switched off (Themes.glass): left in place and only shown again, the
    // effect no longer cut the shape out, and drew it, black, under the
    // glass.
    Loader {
        anchors.fill: parent
        active: Theme.glass
        sourceComponent: Item {
            Item {
                id: solid

                anchors.fill: parent
                visible: false
                layer.enabled: true

                Loader {
                    property color tint: "black"
                    property real glassy: 0

                    anchors.fill: parent
                    sourceComponent: shape
                }
            }

            MultiEffect {
                anchors.fill: parent
                source: solid
                // as large as the frame, so that the cut lies on it exactly
                autoPaddingEnabled: false
                shadowEnabled: true
                blurMax: 15
                shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
                maskEnabled: true
                maskSource: solid
                maskInverted: true
                // The cut is as soft as the shape's own edge: where the shape half
                // covers a pixel, half the shadow stays. Cut hard (the default: gone
                // wherever there is any of the shape), the shadow ended in steps a
                // pixel outside every curve, with a light seam between it and the
                // glass: "anything rounded looks jagged".
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            Loader {
                property color tint: Theme.bg
                property real glassy: 1 - Theme.frameOpacity

                anchors.fill: parent
                sourceComponent: shape
            }
        }
    }

    // Where the compositor blurs: the whole surface, less the hole, and
    // each panel put back. (The dock's hint is not glass and is left out.)
    BackgroundEffect.blurRegion: Theme.glass ? blur : null

    Region {
        id: blur

        width: root.width
        height: root.height

        Region {
            intersection: Intersection.Subtract
            x: root.hole.x
            y: root.hole.y
            width: root.hole.z - root.hole.x
            height: root.hole.w - root.hole.y
            // Regions are whole pixels, so on a curve the blur ends in
            // steps. They are kept under the glass's solid rim, where they
            // do not show, by blurring a little less than the shape at every
            // curve: here a hole with tighter corners, for a panel wider
            // ones and fillets a pixel narrower (BlurBlob.qml).
            radius: Math.max(0, Math.floor(Theme.frameRounding) - 1)
            bottomLeftRadius: Math.max(0, Math.floor(notificationCorner.corner) - 1)
        }

        BlurBlob {
            blob: dock.blob
            hole: root.hole
        }

        BlurBlob {
            blob: sidePanel.blob
            hole: root.hole
        }

        BlurBlob {
            blob: commandPalette.blob
            hole: root.hole
        }

        BlurBlob {
            blob: notificationCorner.blob
            hole: root.hole
        }
    }

    Dock {
        id: dock

        anchors.fill: parent
        screen: root.screen
        cornerRoom: notificationCorner.here ? notificationCorner.reach : 0
    }

    // The panel hanging from the top edge: the clipboard history or the
    // theme switcher (CommandPalette). Its content exists only while open
    // (and until it has faded out).
    TopPanel {
        id: commandPalette

        readonly property bool showing: CommandPalette.open && (CommandPalette.screen === null || CommandPalette.screen === root.screen)

        anchors.fill: parent
        edgeY: Theme.frameBorder
        centreX: (Theme.frameBorder + root.innerRight) / 2
        open: showing
        // fallbacks for the instant before the loader has the content
        contentWidth: paletteLoader.item?.implicitWidth ?? (CommandPalette.themesMode ? 1284 : 660)
        contentHeight: paletteLoader.item?.implicitHeight ?? (CommandPalette.themesMode ? 273 : 69)

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
            sourceComponent: CommandPalette.themesMode ? themePicker : palettePanel

            Component {
                id: palettePanel

                PalettePanel {}
            }

            Component {
                id: themePicker

                ThemePicker {}
            }

            Behavior on opacity {
                Anim {
                    kind: Anim.Fade
                }
            }
        }
    }

    // Notifications, quietly: the frame's bottom left corner. While there are
    // some, there is a light in it, as far into the corner as it goes, and
    // the corner is rounded a little further than the others, as much as
    // gives the light room. It ripples for as long as some notifications
    // have not been looked at. A click there (or on the corner of the border,
    // when there are none) and the list grows out of the corner; so do, by
    // themselves, the notifications that are to be seen at once (they hung
    // from the top edge against the bar first). Middle click
    // switches do not disturb. First screen only.
    CornerPanel {
        id: notificationCorner

        readonly property bool here: root.screen === Quickshell.screens[0] && Notifications.serving
        readonly property bool listOpen: here && Notifications.listOpen
        readonly property bool calling: Notifications.unread > 0 && !Notifications.doNotDisturb
        readonly property bool lit: here && Notifications.count > 0 && !listOpen
        // Notifications that are to be seen at once come out of the same
        // corner, as cards, for as long as KDE's model keeps them up; not
        // while the list is open, which has them too.
        readonly property bool popping: (popups.item?.count ?? 0) > 0 && !listOpen
        // The corner's radius: the frame's own without notifications, and
        // with some just enough for the light. The light's middle is 7.5 px
        // from the screen's two edges, in the corner of the border itself,
        // and it is 5.7 px at its widest (the dot on the in-breath, and its
        // soft edge): out to the left and down it has 1.8 px, and at this
        // radius 3.9 px to the curve. At the frame's own 7.5 it would reach
        // over the curve. (The corner was 54, and 72 while the light was
        // calling, the light halfway into what that filled; it lay over the
        // corners of the windows once those came closer to the frame.)
        property real corner: lit ? 18 : Theme.frameRounding
        // where the light is from the hole's corner: less than nothing, it
        // is in the border
        readonly property real lightAt: -1.5
        // The filled corner is as deep, along its diagonal, as 0.414 of the
        // radius; a square this size at the hole's corner lies within the
        // fill and is the button, with the border's corner beside it.
        readonly property real button: lit ? corner * 0.29 : 0
        // how far along the two borders the corner is the notifications':
        // a click there opens the list, and the pointer there does not
        // bring the dock up
        readonly property real reach: 45

        function clicked(button) {
            if (button === Qt.MiddleButton)
                Notifications.backend?.setDoNotDisturb(!Notifications.doNotDisturb);
            else
                Notifications.toggleList();
        }

        Behavior on corner {
            Anim {}
        }

        anchors.fill: parent
        edgeX: Theme.frameBorder
        edgeY: root.height - Theme.frameBorder
        contentWidth: listOpen ? (notificationList.item?.implicitWidth ?? 363) : (popping ? popups.item.implicitWidth : 0)
        contentHeight: listOpen ? (notificationList.item?.implicitHeight ?? 120) : (popping ? popups.item.implicitHeight : 0)
        focus: listOpen
        Keys.onEscapePressed: Notifications.listOpen = false

        // clicks on the open list, or between the popups' cards, stop here
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Loader {
            id: popups

            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            active: notificationCorner.here && Notifications.popups !== null
            opacity: notificationCorner.popping ? 1 : 0
            visible: opacity > 0
            sourceComponent: Popups {
                notifications: Notifications.popups
                timeout: Notifications.backend.popupTimeout
                paused: !notificationCorner.popping
            }

            Behavior on opacity {
                SwapFade {
                    incoming: notificationCorner.popping
                }
            }
        }

        Loader {
            id: notificationList

            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            // stays loaded until it has faded out
            active: notificationCorner.listOpen || opacity > 0
            opacity: notificationCorner.listOpen ? 1 : 0
            sourceComponent: NotificationList {}

            Behavior on opacity {
                SwapFade {
                    incoming: notificationCorner.listOpen
                }
            }
        }
    }

    // the filled corner is the button
    MouseArea {
        cursorShape: Qt.PointingHandCursor
        x: Theme.frameBorder
        y: root.height - Theme.frameBorder - height
        width: notificationCorner.button
        height: notificationCorner.button
        enabled: !root.modal
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => notificationCorner.clicked(mouse.button)
    }

    // Without notifications the corner is like the others: the corner of
    // the border itself opens the (empty) list.
    MouseArea {
        cursorShape: Qt.PointingHandCursor
        x: 0
        y: root.height - notificationCorner.reach
        width: Theme.frameBorder
        height: notificationCorner.reach
        enabled: notificationCorner.here && !root.modal
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => notificationCorner.clicked(mouse.button)
    }

    MouseArea {
        cursorShape: Qt.PointingHandCursor
        x: 0
        y: root.height - Theme.frameBorder
        width: notificationCorner.reach
        height: Theme.frameBorder
        enabled: notificationCorner.here && !root.modal
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => notificationCorner.clicked(mouse.button)
    }

    // The light: drawn by a shader on a canvas larger than the filled corner,
    // so that its ripples run out over it. It takes no input.
    ShaderEffect {
        id: light

        readonly property real size: 132
        // seconds, running only while it is calling
        property real time: 0
        readonly property real energy: notificationCorner.calling ? 1 : 0
        readonly property color colorA: Theme.accent
        readonly property color colorB: Theme.desktopColors[1]

        x: notificationCorner.edgeX + notificationCorner.lightAt - size / 2
        y: notificationCorner.edgeY - notificationCorner.lightAt - size / 2
        width: size
        height: size
        visible: opacity > 0
        opacity: notificationCorner.lit ? 1 : 0
        fragmentShader: Qt.resolvedUrl("file://" + Quickshell.shellPath("shaders/orb.frag.qsb"))

        Behavior on opacity {
            SwapFade {
                incoming: !notificationCorner.listOpen
            }
        }

        NumberAnimation on time {
            running: light.visible && notificationCorner.calling
            from: 0
            to: 3600
            duration: 3600000
            loops: Animation.Infinite
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

    // While a menu is open (a window of its own, see widgets/MenuPopup.qml)
    // nothing on the frame answers the pointer being on it: this is over
    // everything and takes the hovering. A press closes the menu and goes on
    // to what is under it, so a right click on another icon opens that one's
    // menu. Not a press on the icon the menu belongs to: that icon closes it.
    //
    // Not there at all otherwise, and not merely disabled: a MouseArea has an
    // arrow for a pointer of its own, and the topmost one under the pointer
    // decides, disabled or not. Disabled, this one took the pointing hand
    // from everything on the frame.
    MouseArea {
        anchors.fill: parent
        visible: Popouts.menuOpen
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            const owner = Popouts.menu?.anchorItem ?? null;
            // an icon of another screen's frame is not under this press
            const here = root.within(owner, bar) || root.within(owner, dock);
            if (!here || !owner.contains(mapToItem(owner, mouse.x, mouse.y)))
                Popouts.closeMenu();
            mouse.accepted = false;
        }
    }
}
