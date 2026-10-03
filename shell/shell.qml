// QApplication is needed for native (QWidget-styled) tray menus
//@ pragma UseQApplication

import Quickshell
import QtQuick

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData

            screen: modelData
        }
    }
}
