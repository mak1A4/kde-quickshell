import Quickshell
import QtQuick
import QtQml
import org.kde.kholidays as KHolidays

// Not part of the shell: run once by setup.sh (`qs -p` this file), it says
// which sets of holidays KDE's holiday library has, a line "REGION <code>"
// each, and ends. The library can only be asked from a program.
ShellRoot {
    Instantiator {
        model: KHolidays.HolidayRegionsModel {}
        delegate: QtObject {
            required property string region

            Component.onCompleted: console.log("REGION " + region)
        }
    }

    // not at once: what is logged is written by another thread, and lines
    // not yet written when the program ends are lost
    Timer {
        interval: 400
        running: true
        onTriggered: Qt.quit()
    }
}
