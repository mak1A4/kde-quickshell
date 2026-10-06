import QtQuick

// The shell's colours and sizes as the lock screen has them when the shell
// has not written its own (Look.qml in ~/.local/share/kde-quickshell/lock,
// from shell/Theme.qml, in this form): Catppuccin Mocha.
QtObject {
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
    readonly property int frameBorder: 9
    readonly property real frameRounding: 7.5
    readonly property int panelRounding: 18
    readonly property int panelSmoothing: 21
    readonly property real shadowOpacity: 0.5
    readonly property int radius: 6
    readonly property int spacing: 6
    readonly property int padding: 9
    readonly property int fontSize: 13
    readonly property int fontSizeSmall: 10
    readonly property int iconSize: 18
    readonly property int moveDuration: 500
    readonly property list<real> moveCurve: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property int fadeDuration: 200
    readonly property list<real> fadeCurve: [0.34, 0.8, 0.34, 1, 1, 1]
}
