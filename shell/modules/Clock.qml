import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

BarButton {
    interactive: false

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

    Label {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 3
        color: Theme.fgDim
        font.pixelSize: Theme.fontSizeSmall
        text: Qt.formatDateTime(clock.date, "dd.MM")
    }
}
