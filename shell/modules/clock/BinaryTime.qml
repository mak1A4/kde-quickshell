import Quickshell
import QtQuick
import qs

// The time as a binary clock: two columns of dots, the hour (of 24) on the
// left and the minutes on the right, each as one binary number. The lowest
// dot is worth 1, then 2, 4, 8, 16 and 32, lit where the number has that
// bit. 13:25 is
//       ·        32
//    ·  ●        16
//    ●  ●         8
//    ●  ·         4
//    ·  ·         2
//    ●  ●         1
// A column is only as high as its number can need (the hour never passes
// 23: five dots). The hour's dots are lit in the text's colour, the
// minutes' in the accent.
//
// The dots are drawn as the workspace switcher draws its own
// (modules/Workspaces.qml): flat, a lit one solid, an unlit one smaller and
// faint, in its column's colour.
//
// Or, with `liquid`, by a shader (shaders/binary.frag, which says how it
// looks): the lit dots are liquid, breathe and glow. This gives it, for each
// column, how far each dot is lit, and a clock to move by.
Item {
    id: root

    required property date date
    // drawn by the shader, not flat
    property bool liquid: false
    property real dot: 9
    // between the dots of a column, and between the two columns
    property real gap: 3
    property real columnGap: 6
    // The rest is the shader's.
    // How fast the dots breathe and the glow drifts: 1 is the shader's own
    // pace, a breath every four seconds. A dot coming on or going out takes
    // its half second whatever this is.
    property real speed: 0.4
    // around the dots, for the glow and the ring of one coming on
    readonly property real margin: 9

    readonly property int hours: date.getHours()
    readonly property int minutes: date.getMinutes()

    implicitWidth: dot * 2 + columnGap
    // the minutes' six dots
    implicitHeight: dot * 6 + gap * 5

    // Which of a number's dots are lit, four at a time (a vector has room
    // for four): x the lowest. `from` 0 is the dots worth 1 to 8, 4 those
    // worth 16 and more.
    function bits(number: int, from: int): vector4d {
        const n = number >> from;
        return Qt.vector4d(n & 1, (n >> 1) & 1, (n >> 2) & 1, (n >> 3) & 1);
    }

    // A wave through the flat dots (Dots.qml), for the pointer coming onto
    // the clock.
    function wave() {
        hourDots.wave();
        minuteDots.wave();
    }

    // the flat dots, both columns standing on the same line
    Dots {
        id: hourDots

        anchors.bottom: parent.bottom
        visible: !root.liquid
        number: root.hours
        count: 5
        tint: Theme.fg
        dot: root.dot
        gap: root.gap
    }

    Dots {
        id: minuteDots

        anchors.bottom: parent.bottom
        x: root.dot + root.columnGap
        visible: !root.liquid
        number: root.minutes
        count: 6
        tint: Theme.accent
        dot: root.dot
        gap: root.gap
    }

    // a dot changing swells a little past its size and settles
    component Change: PropertyAnimation {
        duration: Theme.moveDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.moveCurve
    }

    // The liquid dots. Not loaded for the flat ones: its clock draws the
    // whole frame's surface again 20 times a second.
    Loader {
        active: root.liquid
        x: -root.margin
        y: -root.margin
        sourceComponent: ShaderEffect {
            id: drawing

            width: root.implicitWidth + root.margin * 2
            height: root.implicitHeight + root.margin * 2
            fragmentShader: Qt.resolvedUrl("file://" + Quickshell.shellPath("shaders/binary.frag.qsb"))

            readonly property vector2d resolution: Qt.vector2d(width, height)
            readonly property real margin: root.margin
            readonly property real dotSize: root.dot
            readonly property real gap: root.gap
            readonly property real columnGap: root.columnGap
            property real time: 0
            property vector4d hourLow: root.bits(root.hours, 0)
            property vector4d hourHigh: root.bits(root.hours, 4)
            property vector4d minuteLow: root.bits(root.minutes, 0)
            property vector4d minuteHigh: root.bits(root.minutes, 4)
            readonly property color hourColor: Theme.fg
            readonly property color minuteColor: Theme.accent
            readonly property color offColor: Theme.surfaceHover

            Behavior on hourLow {
                Change {}
            }

            Behavior on hourHigh {
                Change {}
            }

            Behavior on minuteLow {
                Change {}
            }

            Behavior on minuteHigh {
                Change {}
            }

            // Slow movement, which 20 pictures a second are enough for: the
            // whole frame is drawn again for each. The count wraps where every
            // wave in the shader is at a whole turn.
            Timer {
                interval: 50
                running: true
                repeat: true
                onTriggered: drawing.time = (drawing.time + 0.05 * root.speed) % (Math.PI * 2000)
            }
        }
    }
}
