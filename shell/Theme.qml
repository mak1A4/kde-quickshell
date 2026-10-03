pragma Singleton

import Quickshell
import QtQuick

Singleton {
    readonly property color bg: "#1e1e2e"
    readonly property color surface: "#313244"
    readonly property color surfaceHover: "#45475a"
    readonly property color surfaceActive: "#585b70"
    readonly property color fg: "#cdd6f4"
    readonly property color fgDim: "#a6adc8"
    readonly property color accent: "#89b4fa"
    readonly property color accentFg: "#1e1e2e"
    readonly property color warning: "#f9e2af"
    readonly property color error: "#f38ba8"
    // one per virtual desktop, by position, repeating
    readonly property list<color> desktopColors: ["#89b4fa", "#cba6f7", "#f5c2e7", "#fab387", "#a6e3a1", "#94e2d5", "#f9e2af", "#f38ba8"]

    // Sizes are multiples of 3 logical px: whole device pixels at scale 1.333
    readonly property int frameBorder: 9
    // inner corners of the frame; anything above 0 covers the corners of maximized windows
    readonly property real frameRounding: 7.5
    // corners and fillets of panels growing out of the frame (dock, popouts)
    readonly property int panelRounding: 24
    readonly property int barWidth: 48
    readonly property int barButton: 36
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
    // How the dock tooltip is joined to the dock (see Frame.qml):
    //   "neck"   - slender neck above the icon
    //   "bridge" - thick liquid bridge
    //   "tab"    - no gap: the bubble sits on the dock like a raised tab
    //   "bead"   - not joined: a small bead bounces between dock and bubble
    readonly property string dockHintStyle: "neck"
    // time the bead takes to cross from dock to bubble, one way
    readonly property int beadTravel: 600
    // hover time before a hint appears; switching between hints is immediate
    readonly property int hintDelay: 400
}
