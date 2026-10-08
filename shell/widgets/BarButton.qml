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
    // a background while the pointer is on it
    property bool hoverEffect: true
    // stays lit while something it opened (a popout) is showing
    property bool active: false
    readonly property bool hovered: hover.hovered
    // shown beside the bar while hovered; no hint when the title is empty
    property string hintTitle: ""
    property list<string> hintLines: []

    // Put away (an item the user has hidden, see BarItems): it takes no room,
    // and grows back into its place when shown again.
    property bool tucked: false
    property real shownPart: tucked ? 0 : 1

    signal clicked(int button)
    // +1 per wheel notch up, -1 per notch down
    signal scrolled(int steps)

    implicitWidth: Theme.barButton
    implicitHeight: Math.max(Theme.barButtonHeight, column.implicitHeight + Theme.spacing * 2) * shownPart
    opacity: shownPart
    // no cell, and none of the layout's spacing, for what is put away
    visible: implicitHeight > 0
    clip: shownPart < 1
    radius: 9
    color: {
        if (highlighted)
            return Theme.accent;
        if (active || (interactive && hoverEffect && hovered))
            return Theme.surfaceHover;
        return Theme.none;
    }

    Behavior on color {
        ColorAnim {}
    }

    Behavior on shownPart {
        Anim {}
    }

    // separate from the MouseArea so non-interactive buttons report hover too
    HoverHandler {
        id: hover

        onHoveredChanged: Popouts.hover(root, hovered)
    }

    ColumnLayout {
        id: column

        anchors.centerIn: parent
        spacing: 0
    }

    MouseArea {
        id: mouse

        cursorShape: Qt.PointingHandCursor
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
