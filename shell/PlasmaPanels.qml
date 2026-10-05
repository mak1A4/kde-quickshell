import Quickshell
import QtQuick

// Plasma's panels are out of the way while the shell runs, and back when it
// does not: a keeper process has KWin park them off screen (panels.sh,
// ../kwin/park-panels.js) and outlives the shell to undo it. Nothing about
// the panels is changed in Plasma. One instance, in shell.qml.
Scope {
    // a reload starts the keeper again; it then finds itself running and leaves
    Component.onCompleted: Quickshell.execDetached(["sh", Quickshell.shellPath("panels.sh"), "keep", String(Quickshell.processId), Quickshell.shellDir.replace(/[^\/]+\/?$/, "kwin")])
}
