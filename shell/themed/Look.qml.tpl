// Written by the shell (kde-quickshell): the colours of its theme "{{ title }}"
// and its sizes, for the lock screen (plasma/lockscreen), which another
// program draws.
import QtQuick

QtObject {
    readonly property color bg: "{{ bg }}"
    readonly property color surface: "{{ surface }}"
    readonly property color surfaceHover: "{{ surfaceHover }}"
    readonly property color surfaceActive: "{{ surfaceActive }}"
    readonly property color fg: "{{ fg }}"
    readonly property color fgDim: "{{ fgDim }}"
    readonly property color accent: "{{ accent }}"
    readonly property color accentFg: "{{ accentFg }}"
    readonly property color warning: "{{ warning }}"
    readonly property color error: "{{ error }}"
    readonly property int frameBorder: {{ frameBorder }}
    readonly property real frameRounding: {{ frameRounding }}
    readonly property int panelRounding: {{ panelRounding }}
    readonly property int panelSmoothing: {{ panelSmoothing }}
    readonly property real shadowOpacity: {{ shadowOpacity }}
    readonly property int radius: {{ radius }}
    readonly property int spacing: {{ spacing }}
    readonly property int padding: {{ padding }}
    readonly property int fontSize: {{ fontSize }}
    readonly property int fontSizeSmall: {{ fontSizeSmall }}
    readonly property int iconSize: {{ iconSize }}
    readonly property int moveDuration: {{ moveDuration }}
    readonly property list<real> moveCurve: [{{ moveCurve }}]
    readonly property int fadeDuration: {{ fadeDuration }}
    readonly property list<real> fadeCurve: [{{ fadeCurve }}]
}
