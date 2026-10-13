import QtQuick
import qs
import qs.modules.clock

// T3 Code's threads in two numbers, as a notch in the frame's top edge
// (Frame.qml lets the AI panel out this far while it is closed and one of
// the two is not 0), and in the same place at the top of the panel while
// that is open. In binary, dots across as the clock's are down, the lowest
// at the right; and two of them side by side as the clock has two:
//   left, three dots: in how many threads it is the user's turn. One has
//     ended and has not been looked at since, or one waits for an answer
//     and goes no further without it: then the dots have the warning's
//     colour.
//   right, five dots: how many are at work, a thread whose subagent is
//     still going in the background counted too.
// A click on the notch opens the panel.
Item {
    id: root

    signal clicked

    // The numbers on show. They stay while the notch goes back in: the last
    // thread has ended and been looked at, and the dots would all go out on
    // the way. Not while the panel is open: there, none is none.
    property int working: 0
    property int turn: 0
    readonly property bool telling: Ai.workingCount + Ai.turnCount > 0
    readonly property int padding: 15
    // How far the dots reach up out of the notch, into the frame's border,
    // which is of the notch's own stuff: the notch is only as deep as what
    // is left of them and a little under them.
    readonly property int rise: 3

    function take() {
        if (!telling && !Ai.open)
            return;
        working = Math.min(31, Ai.workingCount);
        turn = Math.min(7, Ai.turnCount);
    }

    Connections {
        target: Ai

        function onWorkingCountChanged() {
            root.take();
        }

        function onTurnCountChanged() {
            root.take();
        }

        function onOpenChanged() {
            root.take();
        }
    }

    Component.onCompleted: take()

    implicitWidth: row.implicitWidth + padding * 2
    implicitHeight: Theme.notchHeight

    Row {
        id: row

        x: root.padding
        y: -root.rise
        spacing: 15

        Dots {
            id: turnDots

            across: true
            number: root.turn
            count: 3
            tint: Ai.waitingCount > 0 ? Theme.warning : Theme.systemHue
            dot: 9
            gap: 6
        }

        Dots {
            id: workingDots

            across: true
            number: root.working
            count: 5
            tint: Theme.accent
            dot: 9
            gap: 6
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.topMargin: -root.rise
        // the notch; at the top of the open panel the dots only tell
        enabled: !Ai.open
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        // the dots answer the pointer, as the clock's do
        onEntered: {
            turnDots.wave();
            workingDots.wave();
        }
        onClicked: root.clicked()
    }
}
