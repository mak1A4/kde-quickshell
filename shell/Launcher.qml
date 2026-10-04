pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "launcher/calc.js" as Calc
import "launcher/search.js" as Search

// The app launcher's state and logic; the panel is launcher/LauncherPanel.qml,
// shown by the Dock. Open it from the dock's first button or with
//   qs ipc -p <config> call launcher toggle
// (bind that to a key in System Settings > Shortcuts).
//
// Typing searches applications. ">" lists session actions, "=" calculates;
// plain arithmetic is recognised without the "=".
Singleton {
    id: root

    property bool open: false
    // the screen whose dock shows it; null means every screen's
    property var screen: null
    property string query: ""

    function show(onScreen) {
        screen = onScreen ?? Quickshell.screens[0] ?? null;
        Popouts.close();
        query = "";
        open = true;
    }

    function hide() {
        open = false;
    }

    function toggle(onScreen) {
        if (open)
            hide();
        else
            show(onScreen);
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.toggle(null);
        }

        // not "show"/"hide": `qs ipc` has a `show` subcommand of its own, and
        // a function by that name is listed instead of called
        function open(): void {
            root.show(null);
        }

        function close(): void {
            root.hide();
        }
    }

    // ---- applications ----------------------------------------------------

    // lower-cased text of each application, built once per change of the list
    readonly property var apps: DesktopEntries.applications.values.filter(entry => !entry.noDisplay).map(entry => ({
                entry: entry,
                fields: {
                    id: entry.id.toLowerCase(),
                    name: entry.name.toLowerCase(),
                    generic: entry.genericName.toLowerCase(),
                    comment: entry.comment.toLowerCase(),
                    keywords: String(entry.keywords).toLowerCase()
                }
            }))

    // ---- usage: how often and how recently each app was started here -----

    // id -> { count, last (ms since epoch) }
    property var usage: ({})

    FileView {
        id: usageFile

        path: Quickshell.statePath("launcher-usage.json")
        blockLoading: true
        // a missing file on first run is expected
        printErrors: false
        onLoaded: {
            try {
                root.usage = JSON.parse(text());
            } catch (error) {
                console.warn("Launcher: ignoring unreadable usage file:", error);
                root.usage = {};
            }
        }
    }

    // Launch count, halved for every two weeks since the last launch, so old
    // favourites fade and recent ones rise.
    function frecency(id, now) {
        const record = usage[id];
        if (!record)
            return 0;
        const days = (now - record.last) / 86400000;
        return record.count * Math.pow(0.5, days / 14);
    }

    function recordLaunch(id) {
        const next = Object.assign({}, usage);
        next[id] = {
            count: (usage[id]?.count ?? 0) + 1,
            last: Date.now()
        };
        usage = next;
        usageFile.setText(JSON.stringify(next));
    }

    // ---- launching -------------------------------------------------------

    // Through KDE (kstart): the app gets its own systemd scope, startup
    // feedback, and KDE's terminal for Terminal=true entries, and is not a
    // child of the shell. kstart hangs on ids it cannot resolve, hence the
    // timeout; on any failure Quickshell starts the entry itself.
    Component {
        id: starter

        Process {
            id: process

            required property DesktopEntry entry

            command: ["timeout", "5", "kstart", "--application", entry.id]
            running: true
            onExited: exitCode => {
                if (exitCode !== 0) {
                    console.warn(`Launcher: kstart failed for ${entry.id} (${exitCode}), starting it directly`);
                    entry.execute();
                }
                process.destroy();
            }
        }
    }

    function launch(entry) {
        recordLaunch(entry.id);
        starter.createObject(root, { entry: entry });
        hide();
    }

    // ---- actions (">") ---------------------------------------------------

    // The session actions, plus reloading the shell. From here, anything that
    // ends the session goes through KDE's own confirmation screen: one Enter
    // on a typed query should not be enough to shut the machine down.
    readonly property var actions: SessionActions.available.map(action => ({
                title: action.title,
                subtitle: action.confirm ? "Asks for confirmation" : "",
                icon: action.icon,
                session: action
            })).concat([
        {
            title: "Reload shell",
            subtitle: "Reload this shell's configuration",
            icon: "view-refresh-symbolic",
            reload: true
        }
    ])

    // ---- results ---------------------------------------------------------

    // What the panel lists for the current query. Each result has title,
    // subtitle, icon, symbolic (recolour the icon) and what activating it does.
    readonly property var results: {
        const text = query.trim();

        if (text.startsWith(">")) {
            const words = text.slice(1).toLowerCase().split(/\s+/).filter(word => word);
            return actions.filter(action => words.every(word => action.title.toLowerCase().includes(word))).map(action => ({
                        kind: "action",
                        title: action.title,
                        subtitle: action.subtitle,
                        icon: action.icon,
                        symbolic: true,
                        action: action
                    }));
        }

        const list = [];

        const explicit = text.startsWith("=");
        if (explicit || Calc.looksLikeMath(text)) {
            const value = Calc.evaluate(explicit ? text.slice(1) : text);
            if (value !== null) {
                list.push({
                    kind: "calc",
                    title: Calc.format(value),
                    subtitle: "Enter copies the result",
                    icon: "accessories-calculator",
                    symbolic: false,
                    value: Calc.format(value)
                });
            } else if (explicit) {
                list.push({
                    kind: "none",
                    title: text.length > 1 ? "Not a complete expression" : "Type an expression",
                    subtitle: "For example 2 * (3 + 4), sqrt(2), 10 % 3",
                    icon: "accessories-calculator",
                    symbolic: false
                });
            }
            if (explicit)
                return list;
        }

        const now = Date.now();
        const words = text.toLowerCase().split(/\s+/).filter(word => word);
        const ranked = [];
        for (const app of apps) {
            const used = frecency(app.entry.id, now);
            // without a query: most used first, then alphabetical
            const score = words.length === 0 ? used : Search.score(app.fields, words);
            if (words.length > 0 && score <= 0)
                continue;
            ranked.push({
                app: app,
                // a little help for apps in regular use, never enough to beat a clearly better match
                score: words.length === 0 ? score : score + Math.min(12, used * 3)
            });
        }
        ranked.sort((a, b) => b.score - a.score || a.app.fields.name.localeCompare(b.app.fields.name));

        for (const item of ranked) {
            const entry = item.app.entry;
            list.push({
                kind: "app",
                title: entry.name,
                subtitle: entry.comment || entry.genericName || "",
                icon: entry.icon,
                symbolic: false,
                entry: entry
            });
        }
        return list;
    }

    function activate(result) {
        if (!result)
            return;
        if (result.kind === "app") {
            launch(result.entry);
        } else if (result.kind === "calc") {
            // wl-copy rather than Quickshell.clipboardText: setting that did not reach the clipboard here
            Quickshell.execDetached(["wl-copy", "--", result.value]);
            hide();
        } else if (result.kind === "action") {
            hide();
            if (result.action.reload)
                Quickshell.reload(false);
            else
                SessionActions.runWithPrompt(result.action.session);
        }
    }
}
