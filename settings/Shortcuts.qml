import Quickshell
import QtQuick
import "keys.js" as KeyText

// The shell's global shortcuts, as KDE's shortcut service (KGlobalAccel) has
// them. The shell registers its actions there under the component
// "kde-quickshell" (see shell/Hotkeys.qml); this reads whatever is
// registered and changes the keys, over the service's D-Bus interface with
// busctl. So the list of actions is not repeated here.
//
// A key that something else in KDE already has is not taken silently:
// request() then leaves `conflict` set, for the view to offer takeOver().
// Taking it from another program (KRunner) is an override: the owner keeps
// the key and only yields it while the shell runs. shell/hotkeys.sh does
// that, and explains it.
QtObject {
    id: root

    readonly property string component: "kde-quickshell"

    // per action: id, name, componentName, keys (numbers), keyText (the first, as text)
    property list<var> actions: []
    // false until the first answer from KDE
    property bool ready: false
    property string error: ""
    // A requested key that others have: { action, key, text, owners }, each
    // owner with its names and keys as KGlobalAccel reports them. null if none.
    property var conflict: null
    // some of them are not the shell's own actions
    readonly property bool conflictForeign: (conflict?.owners ?? []).some(owner => owner.component !== component)
    // the shell's script for overrides; it is next to this config
    property string script: Quickshell.shellDir.replace(/[^\/]+\/?$/, "shell/hotkeys.sh")
    // who has it, for a message: "KRunner", "KWin (Switch to Desktop 1)"
    readonly property string conflictOwners: (conflict?.owners ?? []).map(owner => owner.name !== "" && owner.name !== owner.componentName ? `${owner.componentName} (${owner.name})` : owner.componentName).join(", ")

    readonly property list<string> accel: ["busctl", "--user", "--json=short", "call", "org.kde.kglobalaccel", "/kglobalaccel", "org.kde.KGlobalAccel"]
    readonly property Component command: Command {}

    function run(command, done) {
        root.command.createObject(root, {
            command: command,
            done: done
        });
    }

    // One action as KGlobalAccel describes it: its id and name, its
    // component's, its context's, its keys, its default keys.
    function parse(info) {
        return {
            id: info[0],
            name: info[1],
            component: info[2],
            componentName: info[3],
            keys: info[6],
            keyText: KeyText.toText(info[6][0] ?? 0)
        };
    }

    function load() {
        const path = "/component/" + component.replace(/[^A-Za-z0-9]/g, "_");
        run(["busctl", "--user", "--json=short", "call", "org.kde.kglobalaccel", path, "org.kde.kglobalaccel.Component", "allShortcutInfos"], (output, code) => {
            try {
                actions = JSON.parse(output).data[0].map(parse).sort((a, b) => a.name.localeCompare(b.name));
                error = "";
            } catch (problem) {
                actions = [];
                error = "KDE has no shortcuts registered for the shell yet. They appear once the shell has been started.";
            }
            ready = true;
        });
    }

    // busctl arguments naming an action, and a list of single keys as a(ai)
    function actionArgs(action) {
        return ["4", action.component, action.id, action.componentName, action.name];
    }

    function keyArgs(keys) {
        let args = [String(keys.length)];
        for (const key of keys)
            args = args.concat(["4", String(key), "0", "0", "0"]);
        return args;
    }

    // What the user asked for in an action's shortcut field; "" clears. Sets
    // it if the key is free, otherwise reports who has it in `conflict`.
    function request(action, text) {
        const key = KeyText.toInt(text);
        conflict = null;
        if (key === null) {
            error = `"${text}" cannot be set from here. Use System Settings > Keyboard > Shortcuts for it.`;
            load();
            return;
        }
        // the key it already has: nothing to do, and its owner, if this is
        // an override, is not a conflict
        if (key === 0 ? action.keys.length === 0 : action.keys.includes(key)) {
            load();
            return;
        }
        if (key === 0) {
            assign(action, 0);
            return;
        }
        run(accel.concat(["getGlobalShortcutsByKey", "i", String(key)]), (output, code) => {
            let owners;
            try {
                owners = JSON.parse(output).data[0].map(parse).filter(owner => owner.component !== action.component || owner.id !== action.id);
            } catch (problem) {
                error = "KDE's global shortcut service did not answer.";
                load();
                return;
            }
            if (owners.length === 0) {
                assign(action, key);
                return;
            }
            conflict = {
                action: action,
                key: key,
                text: text,
                owners: owners
            };
            // the field goes back to what is really set
            load();
        });
    }

    // The one click. Another action of the shell loses the key for good
    // (its other keys stay). Another program keeps it and is overridden
    // while the shell runs.
    function takeOver() {
        const wanted = conflict;
        if (!wanted)
            return;
        conflict = null;
        const failed = owner => {
            error = `Could not take ${wanted.text} from ${owner.componentName}.`;
            load();
        };
        const own = wanted.owners.filter(owner => owner.component === component);
        const foreign = wanted.owners.filter(owner => owner.component !== component);
        const next = () => {
            if (own.length > 0) {
                const owner = own.shift();
                run(accel.concat(["setForeignShortcutKeys", "asa(ai)"], actionArgs(owner), keyArgs(owner.keys.filter(key => key !== wanted.key))), (output, code) => {
                    if (code !== 0)
                        failed(owner);
                    else
                        // if it had the key by an override itself, that is over
                        run(["sh", script, "drop", component, owner.id], next);
                });
            } else if (foreign.length > 0) {
                const owner = foreign.shift();
                run(["sh", script, "override", component, wanted.action.id, String(wanted.key), owner.component, owner.id], (output, code) => code !== 0 ? failed(owner) : next());
            } else if (wanted.owners.some(owner => owner.component !== component)) {
                // the override has set it
                load();
            } else {
                assign(wanted.action, wanted.key);
            }
        };
        next();
    }

    function dismiss() {
        conflict = null;
    }

    // Key as a number, one that is free; 0 clears. The action then needs no
    // override any more: the owners of its old key get it back.
    function assign(action, key) {
        run(accel.concat(["setForeignShortcutKeys", "asa(ai)"], actionArgs(action), keyArgs(key === 0 ? [] : [key])), (output, code) => {
            error = code === 0 ? "" : `KDE did not accept ${KeyText.toText(key)} for "${action.name}".`;
            run(["sh", script, "drop", component, action.id], load);
        });
    }

    Component.onCompleted: load()
}
