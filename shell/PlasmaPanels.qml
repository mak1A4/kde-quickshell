import Quickshell
import QtQuick

// Plasma's panels are out of the way while the shell runs, and back when it
// does not: a keeper process has KWin park them off screen (panels.sh,
// ../kwin/park-panels.js) and outlives the shell to undo it. Nothing about
// the panels is changed in Plasma. The same keeper has Plasma's desktop show
// no icons for as long, by its file filter. One instance, in shell.qml.
Scope {
    // A reload starts the keeper again; it then finds itself running and
    // leaves. It is started in a systemd scope of its own: the shell is
    // started as a systemd unit at login, and a process left in that unit
    // is ended with the shell, before it has undone anything.
    Component.onCompleted: Quickshell.execDetached(["sh", "-c", 'if command -v systemd-run > /dev/null; then exec systemd-run --user --scope --quiet -- "$@"; else exec "$@"; fi', "sh", "sh", Quickshell.shellPath("panels.sh"), "keep", String(Quickshell.processId), Quickshell.shellDir.replace(/[^\/]+\/?$/, "kwin")])
}
