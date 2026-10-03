import QtQuick
import qs

// Horizontal slider over 0..to. `level` (0..1) is a live signal meter drawn
// inside the filled part, like Plasma's volume sliders.
Item {
    id: root

    property real value: 0
    property real to: 1
    property real level: 0
    property real step: 0.05
    property bool dimmed: false

    signal moved(real value)

    readonly property real fraction: Math.max(0, Math.min(1, value / to))
    readonly property real span: width - handle.width

    implicitWidth: 180
    implicitHeight: 18

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        x: handle.width / 2
        width: root.span
        height: 6
        radius: 3
        color: Theme.surface
    }

    Rectangle {
        id: fill

        anchors.verticalCenter: parent.verticalCenter
        x: track.x
        width: root.span * root.fraction
        height: 6
        radius: 3
        color: root.dimmed ? Theme.fgDim : Theme.accent
        opacity: 0.45
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: track.x
        visible: !root.dimmed && root.level > 0
        width: fill.width * Math.min(1, root.level)
        height: 6
        radius: 3
        color: Theme.accent
    }

    // 100% mark, only when the range goes beyond it
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.to > 1
        x: track.x + root.span / root.to - width / 2
        width: 3
        height: 12
        radius: 1.5
        color: Theme.surfaceHover
    }

    Rectangle {
        id: handle

        anchors.verticalCenter: parent.verticalCenter
        x: root.span * root.fraction
        width: 15
        height: 15
        radius: 7.5
        color: root.dimmed ? Theme.fgDim : Theme.fg
    }

    MouseArea {
        property real wheelAccumulator: 0

        function update(x) {
            root.moved(Math.max(0, Math.min(1, (x - handle.width / 2) / root.span)) * root.to);
        }

        anchors.fill: parent
        preventStealing: true
        onPressed: event => update(event.x)
        onPositionChanged: event => {
            if (pressed)
                update(event.x);
        }
        onWheel: event => {
            wheelAccumulator += event.angleDelta.y;
            const steps = Math.trunc(wheelAccumulator / 120);
            if (steps !== 0) {
                wheelAccumulator -= steps * 120;
                root.moved(Math.max(0, Math.min(root.to, root.value + steps * root.step)));
            }
        }
    }
}
