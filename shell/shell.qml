import Quickshell
import QtQuick

ShellRoot {
    Hotkeys {}
    PlasmaPanels {}

    // a singleton exists once something names it; these have work to do
    // at the start
    readonly property var loginScreen: LoginScreen
    readonly property var themeExport: ThemeExport
    readonly property var looks: Looks

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
