import Quickshell
import QtQuick
import qs
import qs.widgets

Pill {
    interactive: false
    flat: true

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Label {
        font.bold: true
        text: Qt.formatDateTime(clock.date, "HH:mm")
    }

    Label {
        color: Theme.fgDim
        text: Qt.formatDateTime(clock.date, "ddd d MMM")
    }
}
