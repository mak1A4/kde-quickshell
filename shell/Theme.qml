pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    // Catppuccin Mocha. A theme (see Themes.qml) replaces these, name by
    // name; what it leaves out stays as it is here. The shell itself is
    // drawn with the first ten and `desktops`; the others are for what wears
    // the theme outside it (ThemeExport.qml): `view` is the background of
    // what an application shows, where `bg` is that of its window, and the
    // terminal's sixteen colours are the theme's own.
    readonly property var defaults: ({
            bg: "#1e1e2e",
            surface: "#313244",
            surfaceHover: "#45475a",
            surfaceActive: "#585b70",
            fg: "#cdd6f4",
            fgDim: "#a6adc8",
            accent: "#89b4fa",
            accentFg: "#1e1e2e",
            warning: "#f9e2af",
            error: "#f38ba8",
            desktops: ["#89b4fa", "#cba6f7", "#f5c2e7", "#fab387", "#a6e3a1", "#94e2d5", "#f9e2af", "#f38ba8"],
            view: "#181825",
            terminal: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8", "#585b70", "#f37799", "#89d88b", "#ebd391", "#74a8fc", "#f2aede", "#6bd7ca", "#bac2de"],
            terminalBackground: "#1e1e2e",
            terminalForeground: "#cdd6f4",
            terminalCursor: "#f5e0dc",
            terminalSelection: "#585b70"
        })

    // A theme's colours in full: what its file gives, and the rest from
    // here. A theme that says nothing about the terminal or the view has
    // them from its own colours, not from Catppuccin's.
    function resolved(given: var): var {
        const colors = Object.assign({}, defaults, given);
        // tooltip above the dock: deliberately not the frame's colour, so it
        // reads as a separate thing floating over it
        colors.tooltipBg = given.tooltipBg ?? colors.accent;
        colors.tooltipFg = given.tooltipFg ?? colors.accentFg;
        // The six colours the bar's icons are drawn in: the theme's own red,
        // green, yellow, blue, magenta and cyan, which are its terminal's.
        // Those are made for text on the terminal's background and can be
        // faint as a small icon on the frame: each is taken towards the
        // text's colour until it stands out enough.
        colors.hues = colors.terminal.slice(1, 7).map(hue => legible(hue, colors.bg, colors.fg));
        if (given.bg) {
            colors.view = given.view ?? given.bg;
            colors.terminalBackground = given.terminalBackground ?? given.bg;
            colors.terminalForeground = given.terminalForeground ?? colors.fg;
            colors.terminalCursor = given.terminalCursor ?? colors.terminalForeground;
            colors.terminalSelection = given.terminalSelection ?? colors.surfaceActive;
        }
        return colors;
    }

    // how bright a colour is, 0 to 1, and how far two are apart (WCAG)
    function luminance(colour: color): real {
        const linear = channel => channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
        return 0.2126 * linear(colour.r) + 0.7152 * linear(colour.g) + 0.0722 * linear(colour.b);
    }

    function contrast(a: color, b: color): real {
        const [high, low] = [luminance(a), luminance(b)].sort((x, y) => y - x);
        return (high + 0.05) / (low + 0.05);
    }

    // `colour`, or as little of `towards` mixed into it as makes it stand
    // out from `on` three to one; at most half
    function legible(colour: color, on: color, towards: color): color {
        let found = colour;
        for (let share = 0; share <= 0.5; share += 0.1) {
            found = Qt.tint(colour, Qt.alpha(towards, share));
            if (contrast(found, on) >= 3)
                break;
        }
        return found;
    }

    // the theme that is in use, which everything outside the shell has too
    readonly property var applied: resolved(Themes.colors)
    // What the shell is drawn with: that, or for as long as the theme
    // switcher is open, the theme it is showing (Themes.preview).
    readonly property var chosen: Themes.preview ? resolved(Themes.preview) : applied

    // the colours the shell is drawn with: these fade
    readonly property list<string> drawn: ["bg", "surface", "surfaceHover", "surfaceActive", "fg", "fgDim", "accent", "accentFg", "warning", "error", "tooltipBg", "tooltipFg"]

    // A change of theme fades: every colour is on its way from what was on
    // screen when the theme changed (`from`) to the new theme's (`to`), and
    // `blend` says how far it has got.
    property var from: chosen
    property var to: chosen
    property real blend: 1

    function mix(a: color, b: color): color {
        return Qt.tint(a, Qt.alpha(b, blend));
    }

    function shown(): var {
        const colors = {
            desktops: [...desktopColors],
            hues: [...hues]
        };
        for (const key of drawn)
            colors[key] = mix(from[key], to[key]);
        return colors;
    }

    // not before the first theme is in place: until then `from` and `to`
    // follow `chosen` by themselves
    property bool settled: false

    Component.onCompleted: {
        from = to = chosen;
        settled = true;
    }

    onChosenChanged: {
        if (!settled)
            return;
        from = shown();
        blend = 0;
        to = chosen;
        fade.restart();
    }

    NumberAnimation {
        id: fade

        target: root
        property: "blend"
        from: 0
        to: 1
        duration: root.fadeDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.fadeCurve
    }

    readonly property color bg: mix(from.bg, to.bg)
    readonly property color surface: mix(from.surface, to.surface)
    readonly property color surfaceHover: mix(from.surfaceHover, to.surfaceHover)
    readonly property color surfaceActive: mix(from.surfaceActive, to.surfaceActive)
    readonly property color fg: mix(from.fg, to.fg)
    readonly property color fgDim: mix(from.fgDim, to.fgDim)
    readonly property color accent: mix(from.accent, to.accent)
    readonly property color accentFg: mix(from.accentFg, to.accentFg)
    readonly property color warning: mix(from.warning, to.warning)
    readonly property color error: mix(from.error, to.error)
    readonly property color tooltipBg: mix(from.tooltipBg, to.tooltipBg)
    readonly property color tooltipFg: mix(from.tooltipFg, to.tooltipFg)
    // No colour at all, for what has a background only under the pointer.
    // Not "transparent": that is black without opacity, and a fade from it
    // to a light colour goes through dark on the way.
    readonly property color none: Qt.alpha(surfaceHover, 0)
    // one per virtual desktop, by position, repeating
    readonly property list<color> desktopColors: to.desktops.map((color, i) => mix(from.desktops[i % from.desktops.length], color))

    // red, green, yellow, blue, magenta, cyan: see `resolved`
    readonly property list<color> hues: to.hues.map((color, i) => mix(from.hues[i], color))
    // Which of them the icon of each of the bar's modules has. Power is not
    // the accent's colour in any theme: its icon turns to the accent while
    // sleep is blocked. Network is neither red nor yellow, which say that
    // something is wrong with it.
    readonly property var moduleHues: ({
            session: 0,
            audio: 1,
            power: 2,
            network: 3,
            media: 4,
            connect: 5
        })

    // the colour of a module's icon in the bar
    function hue(module: string): color {
        return hues[moduleHues[module] ?? -1] ?? fg;
    }

    // one of the six for anything with a name, always the same one: an
    // item in the tray
    function hueOf(name: string): color {
        let sum = 0;
        for (let i = 0; i < name.length; i++)
            sum = (sum * 31 + name.charCodeAt(i)) % 9973;
        return hues[sum % hues.length];
    }

    // Sizes are multiples of 3 logical px: whole device pixels at scale 1.333
    readonly property int frameBorder: 9
    // inner corners of the frame; anything above 0 covers the corners of maximized windows
    readonly property real frameRounding: 7.5
    // corners and fillets of panels growing out of the frame (dock, popouts)
    readonly property int panelRounding: 18
    readonly property int barWidth: 48
    readonly property int barButton: 36
    // A cell in the bar is that wide and this high, and the cells of the lower
    // group are this far apart: together the distance from one icon to the next.
    readonly property int barButtonHeight: 30
    readonly property int barSpacing: 0
    readonly property int dockHeight: 60
    readonly property int popupWidth: 420
    readonly property int pillHeight: 24
    readonly property int iconSize: 18
    readonly property int spacing: 6
    readonly property int padding: 9
    readonly property int radius: 6
    readonly property int fontSize: 13
    readonly property int fontSizeSmall: 10
    readonly property int maxTextWidth: 240

    // fillet radius where a panel flows into the frame
    readonly property int panelSmoothing: 21
    // drop shadow the frame and its panels cast on the windows below
    readonly property real shadowOpacity: 0.5

    // Motion, after Caelestia (Material 3 expressive): things that move
    // overshoot slightly and settle; things that fade or recolour are quick.
    readonly property int moveDuration: 500
    readonly property list<real> moveCurve: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property int fadeDuration: 200
    readonly property list<real> fadeCurve: [0.34, 0.8, 0.34, 1, 1, 1]
    // A highlight that follows the pointer from row to row has to keep up
    // with it: at the fade's 200 ms it trails behind and the list feels slow.
    readonly property int followDuration: 70
    // When one content replaces another in the same panel, the new one waits
    // this long before fading in, so the two are not on screen together.
    readonly property int swapDelay: 140
    // hover time before a hint appears; switching between hints is immediate
    readonly property int hintDelay: 400
}
