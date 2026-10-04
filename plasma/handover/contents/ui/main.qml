import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

// Runs inside plasmashell, in the system tray, and never shows anything.
//
// Plasma's notification service cannot be taken over from outside:
// plasmashell claims its D-Bus names without allowing replacement, and only
// the owner of a name can let go of it. So the letting go has to happen in
// plasmashell itself, which is all this does. While the shell announces
// itself on the bus (it owns `presence`), plasmashell releases the names of
// the notification service and of the job tracker, and the shell takes
// them. When the announcement is gone, because the shell quit, was killed or
// crashed, plasmashell requests the names again and is exactly what it was
// before: its service objects were never touched, only unreachable.
//
// Without the shell this does nothing at all.
PlasmoidItem {
    Plasmoid.status: PlasmaCore.Types.HiddenStatus

    Handover {
        // announced by the shell, see shell/Notifications.qml
        presence: "io.github.mak1a4.kde-quickshell.notifications"
        // the notification service, the one sandboxed applications reach
        // through the portal, and the two names of the job (progress) tracker
        names: ["org.freedesktop.Notifications", "org.freedesktop.impl.portal.desktop.plasmanotify", "org.kde.JobViewServer", "org.kde.kuiserver"]
        // one service in plasmashell answers on both
        together: ({
                "org.freedesktop.Notifications": ["org.freedesktop.impl.portal.desktop.plasmanotify"]
            })
    }
}
