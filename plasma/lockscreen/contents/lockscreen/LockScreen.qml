import QtQuick

// The lock screen of the Quickshell shell, shown by KDE's screen locker
// (kscreenlocker): the shell cannot lock the session itself (KWin has no
// ext_session_lock_v1), but the locker takes its whole interface from QML
// files, and these are ours. See "Lock screen" in docs/decisions.md.
Item {
    id: root

    property string notification
    signal clearPassword
    signal notificationRepeated

    // properties kscreenlocker looks for
    property bool debug: false
    property bool viewVisible: false

    implicitWidth: 800
    implicitHeight: 600

    LockScreenUi {
        anchors.fill: parent
    }
}
