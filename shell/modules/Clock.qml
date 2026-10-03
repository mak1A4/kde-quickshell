import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

BarButton {
    interactive: false
    hintTitle: Qt.formatDateTime(clock.date, "dddd")
    hintLines: [Qt.locale().toString(clock.date, "d MMMM yyyy")]

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        font.pixelSize: 15
        font.bold: true
        text: Qt.formatDateTime(clock.date, "HH")
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        font.pixelSize: 15
        font.bold: true
        text: Qt.formatDateTime(clock.date, "mm")
    }
}
