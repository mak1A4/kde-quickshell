import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root

    default property alias content: row.data
    property bool highlighted: false
    property bool flat: false
    property bool interactive: true
    readonly property bool hovered: mouse.containsMouse

    signal clicked(int button)
    // +1 per wheel notch up, -1 per notch down
    signal scrolled(int steps)

    implicitWidth: row.implicitWidth + Theme.padding * 2
    implicitHeight: Theme.pillHeight
    radius: Theme.radius
    color: {
        if (highlighted)
            return Theme.accent;
        if (interactive && hovered)
            return Theme.surfaceHover;
        return flat ? "transparent" : Theme.surface;
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Theme.spacing
    }

    MouseArea {
        id: mouse

        property real wheelAccumulator: 0

        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: event => root.clicked(event.button)
        onWheel: event => {
            // touchpads send many small deltas; emit one step per 120 units
            wheelAccumulator += event.angleDelta.y;
            const steps = Math.trunc(wheelAccumulator / 120);
            if (steps !== 0) {
                wheelAccumulator -= steps * 120;
                root.scrolled(steps);
            }
        }
    }
}
