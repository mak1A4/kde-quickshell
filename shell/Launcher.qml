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
// With nothing typed it is a menu with what KDE's own has: the favourites,
// all applications or one category of them, the places, the session. Typing
// searches applications. ">" lists session actions, "=" calculates; plain
// arithmetic is recognised without the "=".
Singleton {
    id: root

    property bool open: false
    // the screen whose dock shows it; null means every screen's
    property var screen: null
    property string query: ""

    function show(onScreen) {
        screen = onScreen ?? Quickshell.screens[0] ?? null;
        Popouts.close();
        CommandPalette.hide();
        Notifications.listOpen = false;
        query = "";
        category = "favorites";
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

        // state for scripts and tests: `qs ipc call launcher isOpen`. (Functions, not
        // properties: those make Quickshell warn about their change signals
        // on every load.)
        function isOpen(): bool {
            return root.open;
        }

        function query(): string {
            return root.query;
        }

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

        // the menu, for scripts and tests: which list is shown, and what is in it
        function category(key: string): string {
            if (!root.categories.some(category => category.key === key))
                return "There are: " + root.categories.map(category => category.key).join(", ");
            root.category = key;
            return key;
        }

        function listing(): string {
            return root.listing.map(row => row.title).join("\n");
        }

        function categories(): string {
            return root.categories.map(category => category.key).join("\n");
        }

        // adds an application to the favourites, or takes it out
        function favorite(id: string): string {
            root.toggleFavorite(id);
            return root.favorites.join("\n");
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

    // ---- the menu: favourites, categories, places -------------------------

    // what is listed while nothing is typed: the key of one of `categories`
    property string category: "favorites"

    // KDE's menu, as far as it is a matter of categories: the main
    // categories a desktop entry can name (freedesktop's), under the names
    // KDE's menu has them. An application is in every one it names.
    readonly property var groups: [
        {
            key: "development",
            title: "Development",
            icon: "applications-development-symbolic",
            match: ["Development"]
        },
        {
            key: "education",
            title: "Education",
            icon: "applications-education-symbolic",
            match: ["Education", "Science"]
        },
        {
            key: "games",
            title: "Games",
            icon: "applications-games-symbolic",
            match: ["Game"]
        },
        {
            key: "graphics",
            title: "Graphics",
            icon: "applications-graphics-symbolic",
            match: ["Graphics"]
        },
        {
            key: "internet",
            title: "Internet",
            icon: "applications-internet-symbolic",
            match: ["Network"]
        },
        {
            key: "multimedia",
            title: "Multimedia",
            icon: "applications-multimedia-symbolic",
            match: ["AudioVideo", "Audio", "Video"]
        },
        {
            key: "office",
            title: "Office",
            icon: "applications-office-symbolic",
            match: ["Office"]
        },
        {
            key: "system",
            title: "System",
            icon: "applications-system-symbolic",
            match: ["System", "Settings"]
        },
        {
            key: "utilities",
            title: "Utilities",
            icon: "applications-utilities-symbolic",
            match: ["Utility", "Accessibility"]
        }
    ]

    // every application, by name
    readonly property var sorted: apps.map(app => app.entry).sort((a, b) => a.name.localeCompare(b.name))

    // The favourites, in their order; one whose application is gone is
    // left out (and kept in the list: it may be installed again).
    readonly property var favoriteEntries: {
        const byId = {};
        for (const entry of sorted)
            byId[entry.id] = entry;
        return favorites.map(id => byId[id]).filter(entry => entry);
    }

    // [{ key, title, icon, entries }]: all applications, then each group
    // that has any, then what is in none. The favourites are kept apart, so
    // that marking one does not make every other list anew.
    readonly property var grouped: {
        const list = [
            {
                key: "all",
                title: "All Applications",
                icon: "applications-all-symbolic",
                entries: sorted
            }
        ];
        const taken = {};
        for (const group of groups) {
            const members = sorted.filter(entry => entry.categories.some(category => group.match.includes(category)));
            for (const entry of members)
                taken[entry.id] = true;
            if (members.length > 0)
                list.push({
                    key: group.key,
                    title: group.title,
                    icon: group.icon,
                    entries: members
                });
        }
        const rest = sorted.filter(entry => !taken[entry.id]);
        if (rest.length > 0)
            list.push({
                key: "other",
                title: "Other",
                icon: "applications-other-symbolic",
                entries: rest
            });
        return list;
    }

    // Everything there is to choose between, in the order it is shown:
    // [{ key, title, icon }]. The favourites, the applications by group,
    // and last the two that are not applications.
    readonly property var categories: [
        {
            key: "favorites",
            title: "Favorites",
            icon: "starred-symbolic"
        }
    ].concat(grouped.map(group => ({
                key: group.key,
                title: group.title,
                icon: group.icon
            }))).concat([
        {
            key: "places",
            title: "Places",
            icon: "folder-symbolic"
        },
        {
            key: "session",
            title: "Session",
            icon: "system-shutdown-symbolic"
        }
    ])

    // the session actions as rows; what ends the session asks first
    readonly property var sessionRows: SessionActions.available.map(action => ({
                kind: "session",
                title: action.title,
                subtitle: action.confirm ? "Asks for confirmation" : "",
                icon: action.icon,
                symbolic: true,
                session: action
            }))

    function appResult(entry) {
        return {
            kind: "app",
            title: entry.name,
            subtitle: entry.comment || entry.genericName || "",
            icon: entry.icon,
            symbolic: false,
            entry: entry
        };
    }

    // what the panel lists while nothing is typed
    readonly property var listing: {
        if (category === "places")
            return places;
        if (category === "session")
            return sessionRows;
        const entries = category === "favorites" ? favoriteEntries : (grouped.find(group => group.key === category) ?? grouped[0]).entries;
        return entries.map(appResult);
    }

    // ---- favourites ------------------------------------------------------

    // Desktop entries by name, without ".desktop", in the order they are
    // listed. Kept in ~/.config/kde-quickshell/launcher.json; without that
    // file they start out as the favourites of KDE's own menu
    // (launcher.sh), or, where that has none, as what is pinned to the dock.
    property list<string> favorites: []

    function isFavorite(id: string): bool {
        return favorites.includes(id);
    }

    function toggleFavorite(id: string): void {
        favorites = isFavorite(id) ? favorites.filter(other => other !== id) : favorites.concat([id]);
        saveFavorites();
    }

    function saveFavorites(): void {
        menuFile.setText(JSON.stringify({
            favorites: favorites
        }, null, 2) + "\n");
    }

    FileView {
        id: menuFile

        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kde-quickshell/launcher.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const stored = JSON.parse(text())?.favorites;
                if (Array.isArray(stored))
                    root.favorites = stored.filter(id => typeof id === "string");
            } catch (error) {
                console.warn("Launcher: ignoring unreadable", path, error);
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                firstFavorites.running = true;
        }
    }

    Process {
        id: firstFavorites

        command: ["sh", Quickshell.shellPath("launcher.sh"), "favorites"]
        stdout: StdioCollector {
            onStreamFinished: {
                let found = text.split("\n").filter(id => id !== "");
                if (found.length === 0)
                    found = Pins.pinned.filter(address => address.startsWith("applications:")).map(address => address.slice(13).replace(/\.desktop$/, ""));
                root.favorites = found;
                root.saveFavorites();
            }
        }
    }

    // ---- places ----------------------------------------------------------

    // The places of KDE's file manager, from the file it keeps them in:
    // each a title, an address and an icon. Only what can be opened as it
    // stands: a directory, the trash, the network; not the searches and
    // timelines the file manager makes up itself.
    property string placesText: ""
    readonly property var places: {
        const list = [];
        const home = "file://" + Quickshell.env("HOME");
        // (no `matchAll` in QML's JavaScript)
        const bookmark = /<bookmark href="([^"]*)">([\s\S]*?)<\/bookmark>/g;
        for (let found = bookmark.exec(placesText); found; found = bookmark.exec(placesText)) {
            const url = found[1].replace(/&amp;/g, "&");
            const body = found[2];
            if (!/^(file|trash|remote|smb|sftp|fish|nfs|ftp):/.test(url) || /<IsHidden>true<\/IsHidden>/.test(body))
                continue;
            let path = url;
            try {
                path = decodeURIComponent(url.startsWith(home) ? "~" + url.slice(home.length) : url.replace(/^file:\/\//, ""));
            } catch (error) {}
            list.push({
                kind: "place",
                title: (/<title>([^<]*)<\/title>/.exec(body)?.[1] ?? "").replace(/&amp;/g, "&") || path,
                subtitle: path,
                icon: /<bookmark:icon name="([^"]*)"/.exec(body)?.[1] ?? "folder",
                symbolic: false,
                url: url
            });
        }
        return list;
    }

    FileView {
        path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/user-places.xbel"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.placesText = text()
    }

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
        LastWindow.expectWindow();
        hide();
    }

    // ---- actions (">") ---------------------------------------------------

    // The session actions, plus the shell's settings, reloading it, its
    // setup (and each thing of it that is not simply in place), one per
    // theme and one per background of the theme in use. From here, anything that ends the session goes through KDE's
    // own confirmation screen: one Enter on a typed query should not be
    // enough to shut the machine down.
    readonly property var actions: SessionActions.available.map(action => ({
                title: action.title,
                subtitle: action.confirm ? "Asks for confirmation" : "",
                icon: action.icon,
                session: action
            })).concat([
        {
            title: "Shell settings",
            subtitle: "Shortcuts for the palette and the launcher",
            icon: "configure-symbolic",
            settings: true
        },
        {
            title: "Update the login screen",
            subtitle: "Display scaling, keyboard layout, fonts and the theme's background; asks for the password",
            icon: "system-users-symbolic",
            login: true
        },
        {
            title: "Theme switcher",
            subtitle: "Themes and their backgrounds, to look through",
            icon: "palette-symbolic",
            switcher: true
        },
        {
            title: Themes.browsers === "system" ? "Browsers: colour from the theme" : "Browsers: colour from KDE",
            subtitle: Themes.browsers === "system" ? "The shell sets the theme's colour by policy; the browser's own theme setting is locked" : "The shell stops setting it; choose \"Use Qt\" in the browser's appearance settings",
            icon: "internet-web-browser-symbolic",
            browsers: Themes.browsers === "system" ? "policy" : "system"
        },
        {
            title: "Check the shell's setup",
            subtitle: Setup.summary,
            icon: "checkmark-symbolic",
            setup: true
        },
        {
            title: "Reload shell",
            subtitle: "Reload this shell's configuration",
            icon: "view-refresh-symbolic",
            reload: true
        }
    ]).concat(Setup.open.map(item => ({
                title: "Setup: " + item.title,
                subtitle: item.detail,
                icon: item.state === "problem" ? "dialog-warning-symbolic" : (item.state === "fixed" ? "checkmark-symbolic" : "dialog-information-symbolic"),
                setup: true
            }))).concat(Themes.names.map(name => ({
                title: "Theme: " + Themes.title(name),
                subtitle: name === Themes.chosen ? "In use" : "",
                icon: "palette-symbolic",
                theme: name
            }))).concat(Themes.backgrounds.map(file => ({
                title: "Background: " + Themes.title(file),
                subtitle: Themes.background.endsWith("/" + file) ? "In use" : "",
                icon: "image-x-generic-symbolic",
                background: file
            })))

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

        for (const item of ranked)
            list.push(appResult(item.app.entry));
        return list;
    }

    function activate(result) {
        if (!result)
            return;
        if (result.kind === "app") {
            launch(result.entry);
        } else if (result.kind === "place") {
            Quickshell.execDetached(["xdg-open", result.url]);
            LastWindow.expectWindow();
            hide();
        } else if (result.kind === "session") {
            hide();
            SessionActions.runWithPrompt(result.session);
        } else if (result.kind === "calc") {
            // wl-copy rather than Quickshell.clipboardText: setting that did not reach the clipboard here
            Quickshell.execDetached(["wl-copy", "--", result.value]);
            hide();
        } else if (result.kind === "action") {
            LastWindow.expectWindow();
            hide();
            runAction(result.action);
        }
    }

    // One of `actions`; also used by the command palette.
    function runAction(action) {
        if (action.reload)
            Quickshell.reload(false);
        else if (action.settings)
            openSettings();
        else if (action.switcher)
            CommandPalette.show(null, "", "themes");
        else if (action.theme)
            Themes.set(action.theme);
        else if (action.background)
            Themes.setBackground(action.background);
        else if (action.browsers)
            Themes.setBrowsers(action.browsers);
        else if (action.login)
            LoginScreen.check(true);
        else if (action.setup)
            Setup.check(true);
        else
            SessionActions.runWithPrompt(action.session);
    }

    // The settings are a program of their own, an ordinary KDE window: the
    // config in ../settings. `-n`: a second start while the window is open
    // does nothing.
    function openSettings() {
        Quickshell.execDetached(["qs", "-n", "-p", Quickshell.shellDir.replace(/[^\/]+\/?$/, "settings")]);
    }
}
