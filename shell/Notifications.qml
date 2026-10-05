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
    // How many have arrived since the list was last looked at, critical ones
    // (they pop up) not counted: the entries of the history that say so.
    readonly property int unread: entries.filter(entry => entry.unread).length
    readonly property int count: (backend?.count ?? 0) + earlier.length
    readonly property bool doNotDisturb: backend?.inhibited ?? false

    Connections {
        target: root.backend

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
    // been looked at was gone. And it drops one the moment its application
    // takes it back, which some do after a few seconds (Teams): the light in
    // the corner came on and went out again, nothing left to see what for.
    // So everything in the list is also written to a file as it arrives, and
    // what is in the file but no longer in the list is shown under it
    // ("earlier") until the user closes it: what a past run of the shell
    // left, and what its application has taken back. Such a notification is a
    // record: text, time and icon. Its application no longer knows it, so it
    // has no actions and a click does nothing.
    //
    // An entry is what Service.listed() says of a notification, with the
    // run of the shell it belongs to (`session`), a `key`, and whether it
    // has been seen (`unread`: it arrived while the list was closed, and the
    // list has not been opened since; what arrives while it is open is
    // seen). The file holds all entries.
    readonly property int maxEarlier: 200
    // this run of the shell: the same over a reload, another after a restart
    property string session: ""
    property bool journalLoaded: false
    property var entries: []
    // what the engine no longer has: of a past run, taken back by its
    // application, or lost
    readonly property var earlier: entries.filter(entry => entry.session !== session)
    // Keys of notifications the user has closed or answered. When one of
    // these goes from the list it goes for good; any other that goes was
    // taken back by its application and stays as a record.
    property var dismissed: ({})
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
    // list is in the file. What is in the file but no longer in the list
    // stays as a record, unless the user closed it. `fresh`: the list has
    // just been made, after a start or a reload; what arrives then is not
    // news.
    function reconcile(fresh) {
        if (!journalLoaded)
            return;
        const listed = backend?.listed() ?? null;
        // no list just now: nothing is known, nothing changes
        if (listed === null)
            return;
        const known = {};
        for (const entry of entries)
            known[entry.key] = entry;
        const present = {};
        const mine = listed.map(row => {
            const key = session + "/" + row.id;
            present[key] = true;
            return Object.assign({
                key: key,
                session: session,
                // 4: critical, which pops up
                unread: known[key]?.unread ?? (!fresh && !listOpen && row.urgency !== 4)
            }, row);
        });
        const records = [];
        for (const entry of entries) {
            if (entry.session !== session)
                records.push(entry);
            else if (!present[entry.key] && !dismissed[entry.key])
                // taken back, or lost by the engine
                records.push(Object.assign({}, entry, {
                    session: "gone"
                }));
        }
        records.sort((a, b) => b.created - a.created);
        const left = {};
        for (const key in dismissed)
            if (present[key])
                left[key] = true;
        dismissed = left;
        entries = mine.concat(records.slice(0, maxEarlier));
        save();
    }

    // ---- groups ---------------------------------------------------------------
    //
    // The list shows the entries by application: an application that has
    // sent several (Teams, a message each) is one group, its newest on top,
    // the rest behind a header. Live notifications and records alike: most
    // of what Teams sends is a record seconds later.
    readonly property var byKey: {
        const byKey = {};
        for (const entry of entries)
            byKey[entry.key] = entry;
        return byKey;
    }
    // application name -> the keys of its entries, newest first; the
    // applications in the order of their newest entry
    readonly property var groups: {
        const groups = {};
        for (const entry of entries.slice().sort((a, b) => b.created - a.created)) {
            const name = entry.applicationName || "";
            if (!(name in groups))
                groups[name] = [];
            groups[name].push(entry.key);
        }
        return groups;
    }
    readonly property list<string> groupNames: Object.keys(groups)

    // closes everything of one application, as the cross on each card would
    function closeGroup(name) {
        const keys = groups[name] ?? [];
        for (const key of keys) {
            const entry = byKey[key];
            if (entry?.session !== session)
                continue;
            dismissed[key] = true;
            backend?.close(entry.id);
        }
        entries = entries.filter(entry => entry.session === session || !keys.includes(entry.key));
        save();
        reconcile(false);
    }

    // The user closes or answers the notification with this id (as
    // Service.listed() gives it): when it goes, it goes for good.
    function dismiss(id) {
        dismissed[session + "/" + id] = true;
    }

    // closes one of the earlier ones
    function forget(key) {
        entries = entries.filter(entry => entry.key !== key);
        save();
    }

    // the clear button: everything, the records with it
    function clearAll() {
        for (const entry of entries)
            if (entry.session === session)
                dismissed[entry.key] = true;
        backend?.clear();
        entries = entries.filter(entry => entry.session === session);
        save();
        reconcile(false);
    }

    function save() {
        if (!journalLoaded)
            return;
        const text = JSON.stringify({
            session: session,
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
        journalLoaded = true;
        reconcile(true);
        save();
    }

    // the list is showing
    property bool listOpen: false

    // looked at, everything is seen
    onListOpenChanged: {
        if (listOpen && entries.some(entry => entry.unread)) {
            entries = entries.map(entry => entry.unread ? Object.assign({}, entry, {
                    unread: false
                }) : entry);
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

        // as the list's clear button
        function clear(): void {
            root.clearAll();
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
