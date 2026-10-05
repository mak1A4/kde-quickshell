import Quickshell
import QtQuick

ShellRoot {
    Hotkeys {}
    PlasmaPanels {}

    Variants {
        model: Quickshell.screens

        Scope {
            id: scope

            required property ShellScreen modelData

            Exclusions {
                screen: scope.modelData
            }

            Frame {
                screen: scope.modelData
            }
        }
    }
}
