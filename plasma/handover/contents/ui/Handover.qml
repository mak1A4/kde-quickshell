import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// The handover itself, apart from the plasmoid around it so that it can be
// run and tested outside plasmashell (with other names).
//
// While `presence` is on the bus, the process this runs in lets go of
// `names`; when `presence` is gone it requests them again.
QtObject {
    id: root

    required property string presence
    required property list<string> names
    // Names that belong to another one: taken back along with it even if
    // this process did not have them when it let go. (plasmashell started
    // while the shell runs finds the portal's name taken and never gets it.)
    property var together: ({})
    // The names this process had and has let go of. A `var`, not a
    // list<string>: reading a typed list gives a live view of the property,
    // and reclaim() would empty its own copy by clearing it.
    property var released: []
    // says what it does, for testing
    property bool verbose: false

    function say(...what) {
        if (verbose)
            console.log("handover:", ...what);
    }

    // `done` gets the reply as a number (the module hands out a wrapped
    // value, which is never === 1), or -1 for an error
    function call(member, args, done) {
        const reply = DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus",
            member: member,
            arguments: args
        });
        reply.finished.connect(() => {
            const result = reply.isError ? -1 : Number(reply.value);
            say(member, args[0].value, "->", result, reply.isError ? reply.error.message : "");
            done(result);
        });
    }

    // as plasmashell asks for its names itself: replace an existing owner,
    // do not allow replacement (flags 2)
    function request(name) {
        call("RequestName", [new DBus.string(name), new DBus.uint32(2)], result => {
            // 1: got it; 4: had it already
            if (result !== 1 && result !== 4)
                console.warn("Quickshell handover: could not take", name, "back, reply", result);
        });
    }

    function release() {
        for (const name of names) {
            // 1: released. Anything else: this process did not have it
            // (Plasma's notification applet is off, another service is in
            // use), and then it is not ours to take back later either.
            call("ReleaseName", [new DBus.string(name)], result => {
                if (result !== 1)
                    return;
                // the shell may be gone again before this answer is here
                if (!shell.registered)
                    request(name);
                else if (!released.includes(name))
                    released = released.concat([name]);
            });
        }
    }

    function reclaim() {
        let mine = released;
        released = [];
        for (const name of mine)
            mine = mine.concat((together[name] ?? []).filter(other => !mine.includes(other)));
        say("reclaiming", JSON.stringify(mine));
        for (const name of mine)
            request(name);
    }

    // This process may ask for a name again by itself while the shell runs:
    // plasmashell sets up its notification service some time after it has
    // started, which can be after this has let go of the names (or found
    // nothing to let go of). The bus tells a process every name it gets.
    readonly property DBus.SignalWatcher acquired: DBus.SignalWatcher {
        enabled: true
        busType: DBus.BusType.Session
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        iface: "org.freedesktop.DBus"

        function dbusNameAcquired(name) {
            root.say("acquired", name);
            // the argument is a wrapped value, not a string
            if (root.shell.registered && root.names.includes(String(name)))
                root.release();
        }

        // the interface's other signals; without a handler each one is
        // logged as missing
        function dbusNameOwnerChanged() {
        }

        function dbusNameLost() {
        }
    }

    readonly property DBus.DBusServiceWatcher shell: DBus.DBusServiceWatcher {
        busType: DBus.BusType.Session
        watchedService: root.presence
        onRegisteredChanged: {
            root.say("presence registered:", registered);
            registered ? root.release() : root.reclaim();
        }
    }

    // started while the shell is already running
    Component.onCompleted: {
        if (shell.registered)
            release();
    }
}
