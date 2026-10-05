pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Notifications in the shell: while it runs it is the notification service,
// and Plasma is again the moment it does not. The service is
// notifications/Service.qml (KDE's own notification engine), the popups are
// notifications/Popups.qml, shown by the Frame.
Singleton {
    id: root

    // imports KDE modules, hence the Loader: a failed import must not take
    // the shell down
    Loader {
        id: service

        source: Qt.resolvedUrl("notifications/Service.qml")
    }

    readonly property var backend: service.item
    readonly property bool failed: service.status === Loader.Error
    // false: Plasma is showing the notifications (the shell is not the
    // service, for want of the helper in plasmashell or of KDE's modules)
    readonly property bool serving: backend?.serving ?? false
    // Only critical notifications pop up. The rest collect in a list that
    // grows out of the frame's bottom left corner, where a light says there
    // are some: see the Frame.
    // `history` is what KDE's engine holds, `earlier` what only the file
    // further down still knows.
    readonly property var popups: backend?.popups ?? null
    readonly property var history: backend?.history ?? null
    // with what is only in the history on disk, see below
    readonly property int unread: (backend?.unread ?? 0) + unreadEarlier
    readonly property int count: (backend?.count ?? 0) + earlier.length
    readonly property bool doNotDisturb: backend?.inhibited ?? false

    // How many are unread is counted by the service, which is made anew
    // when the shell reloads its configuration, while the notifications
    // themselves stay (see notifications/Service.qml). This carries the
    // count over, so the light in the corner does not go out, or come on
    // for everything in the list.
    PersistentProperties {
        id: kept

        reloadableId: "notifications"
        property int unread: 0

        onReloaded: {
            if (root.backend)
                root.backend.unread = Math.min(unread, root.backend.count);
        }
    }

    Connections {
        target: root.backend

        function onUnreadChanged() {
            kept.unread = root.backend.unread;
            root.save();
        }

        // the list is there, or there again: after a start or a reload
        function onHistoryChanged() {
            root.reconcile(true);
        }

        function onTouched() {
            settle.restart();
        }
    }

    // ---- the history on disk ------------------------------------------------
    //
    // KDE's engine keeps the notifications in the process, so they end with
    // it: a restart of the shell, a crash, a logout, and whatever had not
    // been looked at was gone. So everything in the list is also written to a
    // file as it arrives, and what a past run of the shell left there is
    // shown under the list ("earlier") until it is closed. Such a
    // notification is a record: text, time and icon. Its application no
    // longer knows it, so it has no actions and a click does nothing.
    //
    // An entry is what Service.listed() says of a notification, with the
    // run of the shell it belongs to (`session`) and a `key`. The file holds
    // all entries, newest first, and how many of them were unread.
    readonly property int maxEarlier: 200
    // this run of the shell: the same over a reload, another after a restart
    property string session: ""
    property bool journalLoaded: false
    property var entries: []
    // unread ones among those of past runs
    property int unreadEarlier: 0
    // what the engine no longer has: of a past run, or lost by this one
    readonly property var earlier: entries.filter(entry => entry.session !== session)
    // what was last written
    property string written: ""

    FileView {
        id: bootId

        path: "/proc/sys/kernel/random/boot_id"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: processStat

        path: "/proc/self/stat"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: journalFile

        path: Quickshell.statePath("notifications.json")
        blockLoading: true
        // no file before the first notification
        printErrors: false
    }

    // a burst (a job's progress, several arriving at once) is one write
    Timer {
        id: settle

        interval: 100
        onTriggered: root.reconcile(false)
    }

    // Brings the entries of this run in line with the list: what is in the
    // list is in the file. What is in the file but no longer in the list was
    // closed, by the user or its application, and goes. Unless the list has
    // just been made (`fresh`, after a reload): then nothing can have been
    // closed, the engine has lost it, and it is kept as a record.
    function reconcile(fresh) {
        if (!journalLoaded)
            return;
        const listed = backend?.listed() ?? null;
        // no list just now: nothing is known, nothing changes
        if (listed === null)
            return;
        const present = {};
        const mine = listed.map(row => {
            const key = session + "/" + row.id;
            present[key] = true;
            return Object.assign({
                key: key,
                session: session
            }, row);
        });
        const lost = fresh ? entries.filter(entry => entry.session === session && !present[entry.key]).map(entry => Object.assign({}, entry, {
                session: "lost"
            })) : [];
        entries = mine.concat(lost, earlier).slice(0, mine.length + maxEarlier);
        save();
    }

    // closes one of the earlier ones
    function forget(key) {
        entries = entries.filter(entry => entry.key !== key);
        save();
    }

    function clearEarlier() {
        entries = entries.filter(entry => entry.session === session);
        unreadEarlier = 0;
        save();
    }

    function save() {
        if (!journalLoaded)
            return;
        const text = JSON.stringify({
            session: session,
            unreadLive: backend?.unread ?? 0,
            unreadEarlier: unreadEarlier,
            entries: entries
        });
        if (text === written)
            return;
        written = text;
        journalFile.setText(text + "\n");
    }

    Component.onCompleted: {
        // boot, process and the time it started: no two runs share that
        session = [bootId.text().trim(), Quickshell.processId, processStat.text().split(") ").pop().split(" ")[19] ?? ""].join(":");
        let stored = {};
        try {
            stored = JSON.parse(journalFile.text()) ?? {};
        } catch (error) {}
        entries = stored.entries ?? [];
        // what a past run had not shown is still not seen
        unreadEarlier = (stored.unreadEarlier ?? 0) + (stored.session === session ? 0 : stored.unreadLive ?? 0);
        if (earlier.length === 0)
            unreadEarlier = 0;
        journalLoaded = true;
        reconcile(true);
        save();
    }

    // the list is showing
    property bool listOpen: false

    // looked at, the earlier ones are seen too
    onListOpenChanged: {
        if (listOpen && unreadEarlier > 0) {
            unreadEarlier = 0;
            save();
        }
    }

    function toggleList() {
        if (listOpen) {
            listOpen = false;
            return;
        }
        Popouts.close();
        Launcher.hide();
        CommandPalette.hide();
        listOpen = true;
    }

    // while it is open, what is in it and what arrives counts as seen
    Binding {
        target: root.backend
        property: "listOpen"
        value: root.listOpen
        when: root.backend !== null
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.toggleList();
        }

        function isOpen(): bool {
            return root.listOpen;
        }

        function unread(): int {
            return root.unread;
        }

        function count(): int {
            return root.count;
        }
    }

    // The helper plasmashell needs for the handover is a Plasma widget. It
    // is installed for the user here if it is missing or differs from the
    // one in this repository. Plasma's system tray loads a new one by
    // itself; a changed one only when plasmashell next starts.
    Process {
        running: true
        command: ["sh", "-c", `
            src=$1
            dest="\${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/io.github.mak1a4.kde-quickshell.handover"
            [ -d "$src" ] || exit 0
            if [ ! -d "$dest" ]; then
                kpackagetool6 --type Plasma/Applet --install "$src" > /dev/null && echo installed
            elif ! diff -rq "$src" "$dest" > /dev/null; then
                kpackagetool6 --type Plasma/Applet --upgrade "$src" > /dev/null && echo upgraded
            fi
        `, "sh", Quickshell.shellDir.replace(/[^\/]+\/?$/, "plasma/handover")]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.includes("upgraded"))
                    console.warn("Notifications: the handover helper in Plasma was updated; plasmashell uses it from its next start");
            }
        }
    }
}
