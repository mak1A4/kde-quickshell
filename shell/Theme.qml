pragma Singleton

import Quickshell
import QtQuick

Singleton {
    readonly property color bg: "#1e1e2e"
    readonly property color surface: "#313244"
    readonly property color surfaceHover: "#45475a"
    readonly property color fg: "#cdd6f4"
    readonly property color fgDim: "#a6adc8"
    readonly property color accent: "#89b4fa"
    readonly property color accentFg: "#1e1e2e"
    readonly property color warning: "#f9e2af"
    readonly property color error: "#f38ba8"

    // Sizes are multiples of 3 logical px: whole device pixels at scale 1.333
    readonly property int frameBorder: 9
    readonly property int frameRounding: 24
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

    readonly property int animDuration: 400
    readonly property list<real> animCurve: [0.2, 0, 0, 1, 1, 1]
}
