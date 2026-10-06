pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// Which theme the shell wears, which there are to choose from, and the
// background that goes with it.
//
// A theme is a file of colours, `<name>.json`:
//   { "colors": { "bg": "#eff1f5", ..., "desktops": ["#1e66f5", ...] },
//     "apps": { "nvim": "catppuccin-latte" } }
// under the names Theme.qml has for them; `apps` says what the theme is
// called where an application has it under a name of its own. The themes are
// existing ones (Catppuccin, Tokyo Night, Gruvbox, ...), not made here. They
// are in two places: the shell's own `themes` directory, and the user's,
// ~/.config/kde-quickshell/themes, where a file replaces the shell's of the
// same name. What a file leaves out, or does not write as "#rrggbb", is as in
// the theme Theme.qml carries in itself, which needs no file.
//
// A theme's backgrounds are the pictures and videos in
// ~/.config/kde-quickshell/themes/backgrounds/<name>/: to give a theme a
// background, put a file there. The desktop, the lock screen and the login
// screen show the chosen one (background.sh); with none they show what they
// are set to in Plasma.
//
// The choice, of the theme and of each theme's background, is in
// ~/.config/kde-quickshell/theme.json, made among the ">" actions
// ("Theme: ...", "Background: ...") or with `qs ipc call theme set <name>`.
// The chosen theme's file is watched: saving it recolours the shell.
Singleton {
    id: root

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kde-quickshell"
    // the theme in Theme.qml
    readonly property string builtin: "catppuccin-mocha"

    property string chosen: builtin
    // what the chosen theme's file says; {} without one
    property var colors: ({})
    property var apps: ({})
    // How Chromium and the browsers made from it get their colour: "policy",
    // the shell writes the theme's colour as machine policy (and the browser
    // then lets nothing else be chosen in its settings); or "system", the
    // shell keeps out, for "Use Qt" in the browser's own settings, which
    // takes KDE's colours.
    property string browsers: "policy"

    // every theme there is, by file name without the ending
    readonly property list<string> names: {
        const found = [builtin];
        for (const folder of [bundled, own])
            for (let i = 0; i < folder.count; i++)
                found.push(folder.get(i, "fileName").replace(/\.json$/, ""));
        return found.filter((name, i) => found.indexOf(name) === i).sort();
    }

    // "tokyo-night" -> "Tokyo Night"
    function title(name: string): string {
        return name.replace(/\.[^.]*$/, "").split(/[-_]/).filter(word => word).map(word => word[0].toUpperCase() + word.slice(1)).join(" ");
    }

    // Chooses a theme, here and for the next start. False if there is none
    // of that name.
    function set(name: string): bool {
        if (!names.includes(name))
            return false;
        chosen = name;
        save();
        return true;
    }

    // The colours of a theme that is only being looked at, in the theme
    // switcher: the shell is drawn with them, nothing else changes. null:
    // none.
    property var preview: null
    // a theme has just been chosen from the preview, and its file is not
    // read yet: the preview stays until it is, so the old theme's colours
    // do not show in between
    property bool confirming: false

    // Chooses a theme together with one of its backgrounds ("" for the
    // first, or none), as the theme switcher does.
    function choose(name: string, file: string): bool {
        if (!names.includes(name))
            return false;
        if (file !== "") {
            const next = Object.assign({}, picked);
            next[name] = file;
            picked = next;
        }
        if (name === chosen) {
            preview = null;
        } else {
            confirming = preview !== null;
            chosen = name;
        }
        save();
        return true;
    }

    function save() {
        choice.setText(JSON.stringify({
            theme: chosen,
            backgrounds: picked,
            browsers: browsers
        }, null, 2) + "\n");
    }

    function setBrowsers(how: string): bool {
        if (how !== "policy" && how !== "system")
            return false;
        browsers = how;
        save();
        return true;
    }

    function isColor(value: var): bool {
        return typeof value === "string" && /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(value);
    }

    // The colours of a theme file that can be used. Of the lists, `desktops`
    // needs two at least (the frame's light drifts between the first two)
    // and `terminal` all sixteen.
    function usable(given: var, path: string): var {
        const lists = {
            desktops: 2,
            terminal: 16
        };
        const colors = {};
        for (const key in given ?? {}) {
            const value = given[key];
            if (key in lists ? Array.isArray(value) && value.length >= lists[key] && value.every(isColor) : isColor(value))
                colors[key] = value;
            else
                console.warn(`Themes: ${path}: "${key}" is not a colour, ignored`);
        }
        return colors;
    }

    function readChoice() {
        let stored;
        try {
            stored = JSON.parse(choice.text());
        } catch (error) {
            // no file yet, or one being written: nothing is known, nothing changes
            return;
        }
        // names only, never a path
        if (typeof stored?.theme === "string" && /^[\w.-]+$/.test(stored.theme))
            chosen = stored.theme;
        const files = {};
        for (const theme in stored?.backgrounds ?? {}) {
            const file = stored.backgrounds[theme];
            if (typeof file === "string" && file !== "" && !file.includes("/"))
                files[theme] = file;
        }
        if (JSON.stringify(files) !== JSON.stringify(picked))
            picked = files;
        browsers = stored?.browsers === "system" ? "system" : "policy";
    }

    function read() {
        let found = {};
        let named = {};
        const file = [ownFile, bundledFile].find(file => file.text() !== "");
        if (file) {
            try {
                const theme = JSON.parse(file.text());
                found = usable(theme?.colors, file.path);
                named = theme?.apps ?? {};
            } catch (error) {
                // probably half written: the theme stays as it is
                console.warn("Themes: ignoring unreadable", file.path, error);
                return;
            }
        } else if (chosen !== builtin) {
            console.warn(`Themes: no theme named "${chosen}"`);
        }
        // not assigned if the same: nothing then has to fade
        if (JSON.stringify(found) !== JSON.stringify(colors))
            colors = found;
        if (JSON.stringify(named) !== JSON.stringify(apps))
            apps = named;
        if (confirming) {
            confirming = false;
            preview = null;
        }
    }

    // ---- backgrounds -----------------------------------------------------

    readonly property string backgroundDir: configDir + "/themes/backgrounds/" + chosen
    // What `ls` found, and for which theme: for a moment after a change of
    // theme that is still the one before. One value, so that the two never
    // disagree.
    property var listing: ({
            theme: "",
            files: []
        })
    readonly property string listed: listing.theme
    // the chosen theme's, as file names
    readonly property list<string> backgrounds: listed === chosen ? listing.files : []
    // theme -> the file chosen among its backgrounds
    property var picked: ({})
    // The one to show, as a path: the one chosen for this theme if it is
    // still there, else the first; "" if the theme has none.
    readonly property string background: {
        if (backgrounds.length === 0)
            return "";
        const file = picked[chosen] ?? "";
        return configDir + "/themes/backgrounds/" + chosen + "/" + (backgrounds.includes(file) ? file : backgrounds[0]);
    }

    function setBackground(file: string): bool {
        if (!backgrounds.includes(file))
            return false;
        const next = Object.assign({}, picked);
        next[chosen] = file;
        picked = next;
        save();
        return true;
    }

    // The directory is listed by `ls`, when the theme is chosen and when
    // something in it changes. Until the list is that of the chosen theme,
    // nothing is known about its backgrounds and nothing is shown.
    function list() {
        if (lister.running)
            return;
        lister.theme = chosen;
        // not `backgroundDir`: at a change of theme that may still be the
        // directory of the theme before
        lister.command = ["ls", "-1", configDir + "/themes/backgrounds/" + chosen];
        lister.running = true;
    }

    onChosenChanged: list()

    Process {
        id: lister

        property string theme

        stdout: StdioCollector {
            onStreamFinished: {
                root.listing = {
                    theme: lister.theme,
                    files: text.split("\n").filter(name => /\.(png|jpe?g|webp|gif|mp4|webm|mkv|mov)$/i.test(name))
                };
            }
        }
        // the theme was changed while this ran
        onExited: {
            if (theme !== root.chosen)
                root.list();
        }
    }

    // a file put there or taken away
    FolderListModel {
        folder: "file://" + root.backgroundDir
        showDirs: false
        onCountChanged: root.list()
    }

    readonly property string wanted: listed === chosen ? chosen + "\n" + background : ""
    onWantedChanged: showBackground()

    // The theme and background the desktop, the lock screen and the login
    // screen were last given. One run of the script at a time: what is
    // chosen meanwhile is given when the run has ended.
    property string shown: ""

    function showBackground() {
        if (backgroundScript.running || wanted === "" || wanted === shown)
            return;
        shown = wanted;
        // Each background has a name of its own for the script: by a new
        // name the wallpaper knows a new file.
        const name = background === "" ? chosen : chosen + "-" + background.replace(/^.*\//, "").replace(/\.[^.]*$/, "");
        backgroundScript.command = ["sh", Quickshell.shellPath("background.sh"), Quickshell.shellDir.replace(/[^\/]+\/?$/, "plasma/background"), name, background];
        backgroundScript.running = true;
    }

    // for LoginScreen: the login screen's directory has just been made
    function showBackgroundAgain() {
        shown = "";
        showBackground();
    }

    Process {
        id: backgroundScript

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.includes("upgraded"))
                    console.warn("Themes: the background wallpaper in Plasma was updated; plasmashell uses it from its next start");
            }
        }
        onExited: root.showBackground()
    }

    // ---- files -----------------------------------------------------------

    FolderListModel {
        id: bundled

        folder: Qt.resolvedUrl("themes")
        nameFilters: ["*.json"]
        showDirs: false
    }

    // The user's directory is made if it is not there: a directory that
    // appears later would not be seen, and it is where a theme of one's own
    // goes.
    FolderListModel {
        id: own

        nameFilters: ["*.json"]
        showDirs: false
        // the chosen theme may just have been put there, or taken away, and
        // a file that was not there is not watched
        onCountChanged: ownFile.reload()
    }

    Process {
        running: true
        command: ["mkdir", "-p", root.configDir + "/themes"]
        onExited: own.folder = "file://" + root.configDir + "/themes"
    }

    FileView {
        id: choice

        path: root.configDir + "/theme.json"
        blockLoading: true
        // edited by hand, or written by the settings: read again
        watchChanges: true
        onFileChanged: reload()
        // no file until a theme is chosen, and one that was not there is
        // not watched: read again once it has been written
        printErrors: false
        onSaved: reload()
        onLoaded: root.readChoice()
    }

    component ThemeFile: FileView {
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        // a theme is in one of the two places, or in neither (the built-in)
        printErrors: false
        onLoaded: root.read()
        onLoadFailed: root.read()
    }

    ThemeFile {
        id: ownFile

        path: root.configDir + "/themes/" + root.chosen + ".json"
    }

    ThemeFile {
        id: bundledFile

        path: Quickshell.shellPath("themes/" + root.chosen + ".json")
    }

    Component.onCompleted: {
        readChoice();
        read();
        list();
    }

    // `qs ipc call theme set tokyo-night`
    IpcHandler {
        target: "theme"

        function set(name: string): string {
            return root.set(name) ? name : `No theme named "${name}". There are: ${root.names.join(", ")}`;
        }

        function get(): string {
            return root.chosen;
        }

        function list(): string {
            return root.names.join("\n");
        }

        // the chosen theme's backgrounds, and which of them is shown
        function backgrounds(): string {
            return root.backgrounds.join("\n");
        }

        function background(): string {
            return root.background.replace(/^.*\//, "");
        }

        // "policy" or "system": see `browsers`
        function browsers(): string {
            return root.browsers;
        }

        function setBrowsers(how: string): string {
            return root.setBrowsers(how) ? how : "policy or system";
        }

        function setBackground(file: string): string {
            return root.setBackground(file) ? file : `"${root.chosen}" has no background "${file}". It has: ${root.backgrounds.join(", ")}`;
        }
    }
}
