pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The launcher's state and logic; the panel is launcher/LauncherPanel.qml,
// shown by the Dock. Open it from the dock's first button, with its keys
// (Hotkeys.qml) or with
//   qs ipc -p <config> call launcher toggle
// or with a query already typed: `call launcher search "> "`.
//
// With nothing typed it is a menu with what KDE's own has: the favourites,
// all applications or one category of them, the places, the session.
// Typing searches as KRunner does, with every runner plugin enabled in
// System Settings > Search > KRunner: apps, windows, settings, files,
// calculator, units, web shortcuts and so on. ">" lists the shell's own
// actions.
//
// Menu and search were two panels until 2026-10-12: this one, which searched
// applications by itself, and a command palette from the top edge with
// KRunner's search.
Singleton {
    id: root

    property bool open: false
    // the screen whose dock shows it; null means every screen's
    property var screen: null
    property string query: ""

    function show(onScreen, text) {
        screen = onScreen ?? Quickshell.screens[0] ?? null;
        Popouts.close();
        CommandPalette.hide();
        Notifications.listOpen = false;
        runner.active = true;
        query = text ?? "";
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

        function search(text: string): void {
            root.show(null, text);
        }

        // the titles of what typing has found
        function results(): string {
            return root.results.map(row => row.title).join("\n");
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

    readonly property var apps: DesktopEntries.applications.values.filter(entry => !entry.noDisplay)

    // ---- the menu: favourites, categories, places -------------------------

    // what is listed while nothing is typed: the key of one of `categories`
    property string category: "favorites"

    // An icon of the rail: one of the Tabler glyphs in icons/tabler
    // (tools/tabler.sh fetches what is named here). One set, drawn alike,
    // for the fourteen that stand in a column; the icon theme's are of
    // several hands, and its "other" is three dots.
    function glyph(name: string): string {
        return Quickshell.shellPath("icons/tabler/" + name + ".svg");
    }

    // KDE's menu, as far as it is a matter of categories: the main
    // categories a desktop entry can name (freedesktop's), under the names
    // KDE's menu has them. An application is in every one it names.
    readonly property var groups: [
        {
            key: "development",
            title: "Development",
            icon: glyph("code"),
            match: ["Development"]
        },
        {
            key: "education",
            title: "Education",
            icon: glyph("school"),
            match: ["Education", "Science"]
        },
        {
            key: "games",
            title: "Games",
            icon: glyph("device-gamepad-2"),
            match: ["Game"]
        },
        {
            key: "graphics",
            title: "Graphics",
            icon: glyph("palette"),
            match: ["Graphics"]
        },
        {
            key: "internet",
            title: "Internet",
            icon: glyph("world"),
            match: ["Network"]
        },
        {
            key: "multimedia",
            title: "Multimedia",
            icon: glyph("movie"),
            match: ["AudioVideo", "Audio", "Video"]
        },
        {
            key: "office",
            title: "Office",
            icon: glyph("briefcase"),
            match: ["Office"]
        },
        {
            key: "system",
            title: "System",
            icon: glyph("settings"),
            match: ["System", "Settings"]
        },
        {
            key: "utilities",
            title: "Utilities",
            icon: glyph("tool"),
            match: ["Utility", "Accessibility"]
        }
    ]

    // every application, by name
    readonly property var sorted: apps.slice().sort((a, b) => a.name.localeCompare(b.name))

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
                icon: glyph("layout-grid"),
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
                icon: glyph("apps"),
                entries: rest
            });
        return list;
    }

    // Everything there is to choose between, in the order it is shown:
    // [{ key, title, icon, part }]. The favourites, the applications by
    // group, and last the two that are not applications. `part` is which
    // of the rail's three groups it stands in: "first" for the two lists
    // that are not a category, "apps" for the categories, "last" for what
    // is not applications.
    readonly property var categories: [
        {
            key: "favorites",
            title: "Favorites",
            icon: glyph("star"),
            part: "first"
        }
    ].concat(grouped.map(group => ({
                key: group.key,
                title: group.title,
                icon: group.icon,
                part: group.key === "all" ? "first" : "apps"
            }))).concat([
        {
            key: "places",
            title: "Places",
            icon: glyph("folder"),
            part: "last"
        },
        {
            key: "session",
            title: "Session",
            icon: glyph("power"),
            part: "last"
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
            subtitle: "Shortcuts, and what the bar shows",
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
            title: Themes.glass ? "Frame: solid" : "Frame: transparent and blurred",
            subtitle: Themes.glass ? "The frame and its panels in the theme's colour, nothing showing through" : "Glass: what is behind the frame and its panels shows through, blurred",
            icon: "blur-symbolic",
            glass: Themes.glass ? "off" : "on"
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

    // ---- KRunner ---------------------------------------------------------

    // Created on first use and kept, so the runner plugins load once.
    Loader {
        id: runner

        active: false
        source: Qt.resolvedUrl("launcher/Runner.qml")
    }

    readonly property var backend: runner.item
    // org.kde.milou is missing or no longer loads here
    readonly property bool backendFailed: runner.status === Loader.Error
    readonly property bool searching: query.trim() !== ""
    readonly property bool shellMode: query.trim().startsWith(">")
    readonly property bool runnerMode: searching && !shellMode
    // results for the typed query are still on their way
    readonly property bool waiting: runnerMode && backend !== null && !backend.fresh
    readonly property bool querying: runnerMode && backend !== null && (backend.querying || !backend.fresh)

    Binding {
        target: root.backend
        property: "query"
        value: root.runnerMode ? root.query : ""
        when: root.backend !== null
    }

    Connections {
        target: root.backend

        function onQueryRequested(text) {
            root.query = text;
        }

        // Enter was pressed before the results arrived: run the first one now
        function onFreshChanged() {
            if (!root.backend.fresh || !root.pendingRun)
                return;
            root.pendingRun = false;
            if (root.open && root.results.length > 0)
                root.activate(root.results[0], 0, -1);
        }
    }

    // The application a result of KRunner's stands for, if it is one: such a
    // result names what it runs ("exec:///usr/bin/dolphin"), not the desktop
    // entry, so that is found by its name, and among several of one name by
    // what it runs.
    function entryOf(result) {
        if (!result)
            return null;
        if (result.entry)
            return result.entry;
        if (result.kind !== "match" || !result.id.startsWith("exec://"))
            return null;
        const named = sorted.filter(entry => entry.name === result.title);
        if (named.length < 2)
            return named[0] ?? null;
        const runs = result.id.slice(7);
        return named.find(entry => entry.execString.replace(/\s*%[a-zA-Z]/g, "").trim() === runs) ?? named[0];
    }

    // ---- results ---------------------------------------------------------

    // What the panel lists for what is typed. Each result has key (its
    // identity, to find it again in the next list), kind, title, subtitle,
    // icon, symbolic (recolour the icon), category and actions (extra
    // things it can do: text and icon each).
    readonly property var results: {
        if (shellMode) {
            const words = query.trim().slice(1).toLowerCase().split(/\s+/).filter(word => word);
            return actions.filter(action => words.every(word => action.title.toLowerCase().includes(word))).map(action => ({
                        key: "action\n" + action.title,
                        kind: "action",
                        title: action.title,
                        subtitle: action.subtitle,
                        icon: action.icon,
                        symbolic: true,
                        category: "Shell",
                        actions: [],
                        action: action
                    }));
        }
        return backend?.matches ?? [];
    }

    // Enter was pressed while results were still on their way
    property bool pendingRun: false

    onOpenChanged: pendingRun = false
    onQueryChanged: pendingRun = false

    // Enter or a click on `result`, row `index` of what is listed; `action`
    // >= 0 picks one of its actions.
    function submit(result, index, action) {
        if (waiting) {
            pendingRun = true;
            return;
        }
        activate(result, index, action);
    }

    function activate(result, index, action) {
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
        } else if (result.kind === "action") {
            LastWindow.expectWindow();
            hide();
            runAction(result.action);
        } else if (result.kind === "match") {
            // The calculator and the unit converter only copy their answer.
            // They would do it through this process's clipboard; wl-copy is
            // the way that is known to work from here
            // (Quickshell.clipboardText did not reach the clipboard either).
            // As in KRunner, the converter's action copies the unit too.
            if (result.answer) {
                const number = /^[-+\d.,'\s]*\d/.exec(result.title);
                const bare = result.id === "unitconverter" && action < 0 && number;
                Quickshell.execDetached(["wl-copy", "--", bare ? number[0].trim() : result.title]);
                hide();
            } else if (backend.run(index, result.id, action)) {
                LastWindow.expectWindow();
                hide();
            }
        }
    }

    // one of `actions`
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
        else if (action.glass)
            Themes.setGlass(action.glass === "on");
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
