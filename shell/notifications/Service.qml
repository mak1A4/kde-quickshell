import Quickshell
import QtQuick
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.workspace.dbus as DBus

// The notification service, while the shell runs: KDE's own notification
// engine (the library Plasma's applet uses) in this process. It keeps the
// history, applies System Settings > Notifications (per-application rules,
// do not disturb, timeouts), tracks jobs (file copies and the like) and
// answers the applications. The shell only draws what it reports.
//
// Plasma normally is that service, and does not allow being replaced. The
// handover is a matter of asking: this process announces itself on the bus
// (it owns `presence`), and a small helper running inside plasmashell
// (../../plasma/handover) makes plasmashell let go of the service's names
// for as long as the announcement is there. When this process ends, however
// it ends, the announcement ends with it and plasmashell takes the names
// back at once. Without the helper nothing happens: plasmashell keeps the
// service and shows notifications as ever.
//
// Loaded by the Notifications singleton through a Loader, because both
// imports are optional.
Item {
    id: root

    readonly property string presence: "io.github.mak1a4.kde-quickshell.notifications"
    // the announcement is on the bus
    property bool announced: false
    // this process is the notification service
    readonly property bool serving: NotificationManager.Server.valid
    // What pops up, and everything not yet cleared; null while not serving.
    // Only critical notifications pop up. The others go straight into the
    // list, which the bar's bell opens; it shows a dot while some are unread.
    readonly property var popups: models.item?.popups ?? null
    readonly property var history: models.item?.history ?? null
    // how many are in the list; kept by sync(), the model's own `count` was
    // seen not to announce the first row
    property int count: 0
    // Which of them are unread is not kept here but with the history
    // (../Notifications.qml): KDE's own count of unread ones only covers
    // expired notifications, and it goes with the engine.
    onHistoryChanged: sync()

    // something in the list arrived, went or was changed
    signal touched

    // What is in the list, newest first, as plain data: for the history on
    // disk (../Notifications.qml). null while there is no list. Without jobs
    // (a file copy is not news once it is over) and without what is about to
    // be dropped.
    function listed() {
        if (!history)
            return null;
        const Roles = NotificationManager.Notifications;
        const rows = [];
        for (let row = 0; row < history.rowCount(); row++) {
            const index = history.index(row, 0);
            if (history.data(index, Roles.TypeRole) === Roles.JobType || history.data(index, Roles.TransientRole))
                continue;
            const created = history.data(index, Roles.CreatedRole);
            rows.push({
                id: String(history.data(index, Roles.IdRole)),
                created: created && !isNaN(created.getTime()) ? created.getTime() : Date.now(),
                applicationName: history.data(index, Roles.ApplicationNameRole) ?? "",
                applicationIconName: history.data(index, Roles.ApplicationIconNameRole) ?? "",
                iconName: history.data(index, Roles.IconNameRole) ?? "",
                summary: history.data(index, Roles.SummaryRole) ?? "",
                body: history.data(index, Roles.BodyRole) ?? "",
                urgency: history.data(index, Roles.UrgencyRole) ?? Roles.NormalUrgency
            });
        }
        return rows;
    }

    function sync() {
        count = history ? history.rowCount() : 0;
    }

    // Closes everything in the list except critical notifications still
    // showing: towards their applications too, as the cross on a card does.
    function clear() {
        if (!history)
            return;
        for (let row = history.count - 1; row >= 0; row--) {
            const index = history.index(row, 0);
            const showing = history.data(index, NotificationManager.Notifications.UrgencyRole) === NotificationManager.Notifications.CriticalUrgency && !history.data(index, NotificationManager.Notifications.ExpiredRole);
            if (!showing)
                history.close(index);
        }
    }

    // closes the notification with this id (as listed() gives it), if it is there
    function close(id) {
        if (!history)
            return;
        for (let row = 0; row < history.rowCount(); row++) {
            const index = history.index(row, 0);
            if (String(history.data(index, NotificationManager.Notifications.IdRole)) === id) {
                history.close(index);
                return;
            }
        }
    }

    // Do not disturb as Plasma's applet switches it: "until" a date a year
    // off, or no date. Stored in KDE's notification settings.
    function setDoNotDisturb(on) {
        if (on) {
            const until = new Date();
            until.setFullYear(until.getFullYear() + 1);
            settings.notificationsInhibitedUntil = until;
        } else {
            settings.notificationsInhibitedUntil = undefined;
            settings.revokeApplicationInhibitions();
        }
        settings.save();
        now = Date.now();
    }
    // how long a popup stays unless the notification says otherwise (ms)
    readonly property int popupTimeout: settings.popupTimeout

    // Do not disturb, as System Settings and Plasma's applet set it: until a
    // time, by an application, or while screens are mirrored.
    property real now: Date.now()
    readonly property bool inhibited: {
        const until = settings.notificationsInhibitedUntil;
        if (until && !isNaN(until.getTime()) && now < until.getTime())
            return true;
        if (settings.notificationsInhibitedByApplication)
            return true;
        return settings.inhibitNotificationsWhenScreensMirrored && settings.screensMirrored;
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // applications can ask whether notifications are inhibited
    Binding {
        target: NotificationManager.Server
        property: "inhibited"
        value: root.inhibited
        when: root.serving
    }

    NotificationManager.Settings {
        id: settings

        // follows changes made in System Settings
        live: true
    }

    DBus.DBusServiceWatcher {
        id: service

        busType: DBus.BusType.Session
        watchedService: "org.freedesktop.Notifications"
        onRegisteredChanged: Qt.callLater(root.decide)
    }

    // The models exist while this process is the service, or could become
    // it: creating them is what makes KDE's library ask for the names. If
    // plasmashell takes the names back while the shell runs (it was
    // restarted), they go, and return once its helper has let go again.
    // Decided in a function, a moment later, and not in a binding: creating
    // the models changes what the decision depends on.
    //
    // Except when the shell reloads its configuration. KDE's library keeps
    // the notifications for as long as one model on them exists, and the
    // process stays the service throughout. So the models of the new
    // configuration are made at once, while those of the old one are still
    // there (Quickshell builds the new one first), and the notifications
    // pass from one to the other: nothing in the list is lost, none that
    // arrives meanwhile is dropped, and each stays open towards its
    // application. Made a moment later, they found the list empty. The
    // announcement is not waited for either: it is asked for anew on every
    // load and answered late, and the process that is the service has it.
    property bool wanted: NotificationManager.Server.valid

    function decide() {
        wanted = serving || (announced && !service.registered);
    }

    onAnnouncedChanged: Qt.callLater(decide)
    onServingChanged: Qt.callLater(decide)

    Loader {
        id: models

        active: root.wanted
        sourceComponent: Item {
            readonly property alias popups: popups
            readonly property alias history: history

            // A model of KDE's, newly made, shows nothing of what the engine
            // already holds, only what arrives from then on, until one of
            // its filters is set, be it to what it was. So each has one set
            // once. This is the second half of keeping the list when the
            // shell reloads its configuration (the first is `wanted`): the
            // notifications were all still there, 17 of them after as many
            // reloads, and the list empty.
            Component.onCompleted: {
                for (const model of [popups, quiet, history]) {
                    model.showDismissed = !model.showDismissed;
                    model.showDismissed = !model.showDismissed;
                }
                root.sync();
            }

            NotificationManager.Notifications {
                id: popups

                // Critical ones only; in do not disturb if System Settings
                // says so. The two "inhibition" switches are not optional:
                // left at their defaults, anything that arrives during do
                // not disturb passes the urgency filter and pops up.
                limit: 4
                showExpired: false
                showDismissed: false
                showJobs: false
                showAddedDuringInhibition: false
                ignoreBlacklistDuringInhibition: false
                blacklistedDesktopEntries: settings.popupBlacklistedApplications
                blacklistedNotifyRcNames: settings.popupBlacklistedServices
                sortMode: NotificationManager.Notifications.SortByDate
                sortOrder: Qt.DescendingOrder
                groupMode: NotificationManager.Notifications.GroupDisabled
                urgencies: root.inhibited && !settings.criticalPopupsInDoNotDisturbMode ? 0 : NotificationManager.Notifications.CriticalUrgency
            }

            // Everything else that would pop up. It is left as it is, open
            // towards its application, and merely not shown: KDE's engine
            // has "expire" for a popup that has had its time, but that
            // tells the application its notification is closed and takes
            // the actions away, and then nothing in the list could be
            // answered or opened. Only a transient notification (one that
            // asks not to be kept: a track change, a volume step) is closed
            // at once: unseen as a popup, there is nothing left of it.
            NotificationManager.Notifications {
                id: quiet

                showExpired: false
                showDismissed: false
                showJobs: false
                groupMode: NotificationManager.Notifications.GroupDisabled
                urgencies: NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.LowUrgency
            }

            Instantiator {
                model: quiet

                QtObject {
                    required property var model
                    required property int index

                    Component.onCompleted: {
                        if (!model.transient)
                            return;
                        // the row may have moved by the time this runs
                        const row = quiet.makePersistentModelIndex(quiet.index(index, 0));
                        Qt.callLater(() => quiet.close(row));
                    }
                }
            }

            // Everything, whatever System Settings says about keeping an
            // application's notifications in the history. Those settings
            // assume a popup was seen first: by default they keep out low
            // priority ones and everything from programs without a desktop
            // entry (scripts using notify-send). Here nothing pops up, so
            // what is not in the list would never be seen at all.
            NotificationManager.Notifications {
                id: history

                showExpired: true
                showDismissed: true
                showJobs: settings.jobsInNotifications
                sortMode: NotificationManager.Notifications.SortByDate
                sortOrder: Qt.DescendingOrder
                groupMode: NotificationManager.Notifications.GroupDisabled
                urgencies: NotificationManager.Notifications.CriticalUrgency | NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.LowUrgency
                onRowsInserted: {
                    root.sync();
                    root.touched();
                }
                onRowsRemoved: {
                    root.sync();
                    root.touched();
                }
                onModelReset: {
                    root.sync();
                    root.touched();
                }
                onDataChanged: root.touched()
            }
        }
    }

    // Owning the name is the announcement. "Do not queue" (flag 4): there is
    // one shell.
    Component.onCompleted: {
        const reply = DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus",
            member: "RequestName",
            arguments: [new DBus.string(presence), new DBus.uint32(4)]
        });
        reply.finished.connect(() => {
            if (reply.isError)
                console.warn("Notifications: could not announce the shell on the bus:", reply.error.message);
            else
                root.announced = true;
        });
    }
}
