import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets
import qs.modules.clock

// The time, as a binary clock (BinaryTime.qml); in figures in the hint. A
// click opens the calendar.
BarButton {
    id: root

    // no background, not under the pointer and not while the calendar is open
    hoverEffect: false
    hintTitle: Qt.formatDateTime(clock.date, "HH:mm")
    hintLines: [Qt.locale().toString(clock.date, "dddd"), Qt.locale().toString(clock.date, "d MMMM yyyy")]
    onClicked: button => {
        if (button === Qt.LeftButton)
            Popouts.toggle("clock", root, panel);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // the dots answer the pointer, as there is no background to
    onHoveredChanged: {
        if (hovered)
            time.wave();
    }

    BinaryTime {
        id: time

        Layout.alignment: Qt.AlignHCenter
        date: clock.date
    }

    Component {
        id: panel

        CalendarPanel {
            now: clock.date
        }
    }

    // `qs ipc call clock toggle`
    IpcHandler {
        target: "clock"

        function toggle(): void {
            Popouts.toggle("clock", root, panel);
        }
    }
}
