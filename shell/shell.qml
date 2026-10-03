import Quickshell
import QtQuick

ShellRoot {
    PanelWindow {
        id: bar

        anchors {
            top: true
            left: true
            right: true
        }
        implicitHeight: 32
        color: "#1e1e2e"

        SystemClock {
            id: clock
            precision: SystemClock.Seconds
        }

        Text {
            anchors.centerIn: parent
            color: "#cdd6f4"
            font.pixelSize: 14
            text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm:ss")
        }

        Component.onCompleted: console.log("bar dpr:", bar.screen.devicePixelRatio, "screen:", bar.screen.name, bar.screen.width + "x" + bar.screen.height)
    }
}
