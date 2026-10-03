import QtQuick
import QtQuick.Layouts
import qs

// A cell in the vertical bar. Children stack vertically; give them
// `Layout.alignment: Qt.AlignHCenter`.
Rectangle {
    id: root

    default property alias content: column.data
    property bool highlighted: false
    property bool interactive: true
    // stays lit while something it opened (a popout) is showing
    property bool active: false
    readonly property bool hovered: mouse.containsMouse

    signal clicked(int button)
    // +1 per wheel notch up, -1 per notch down
    signal scrolled(int steps)

    implicitWidth: Theme.barButton
    implicitHeight: Math.max(Theme.barButton, column.implicitHeight + Theme.spacing * 2)
    radius: 9
    color: {
        if (highlighted)
            return Theme.accent;
        if (active || (interactive && hovered))
            return Theme.surfaceHover;
        return "transparent";
    }

    ColumnLayout {
        id: column

        anchors.centerIn: parent
        spacing: 0
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
