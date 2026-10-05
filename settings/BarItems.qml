import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import QtQuick
import "symbols.js" as Symbols

// What is chosen for the items in the bar, for a tray item an icon in place
// of the one it brings and for it or one of the bar's own modules whether it
// is in the bar: the file shell/BarItems.qml reads (which says what is in
// it), and the list of items to choose for. Which item is which, which
// modules there are and how an icon is written is the shell's
// (shell/modules/tray/symbols.js), not repeated here: symbols.js in this
// directory is a link to it, as Quickshell loads no script from outside the
// config's own directory.
Scope {
    id: root

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kde-quickshell/bar-items.json"
    // the shell's glyphs; it is next to this config
    readonly property string tablerDir: Quickshell.shellDir.replace(/[^\/]+\/?$/, "shell/icons/tabler")
    // key -> { icon, hide }
    property var chosen: ({})
    // The icon each module has in the bar at the moment, by the module's
    // name, as the running shell says: asked again every few seconds, the
    // volume or the network may change while the window is open. Empty while
    // the shell is not running.
    property var moduleIcons: ({})
    readonly property string shell: Quickshell.shellDir.replace(/[^\/]+\/?$/, "shell")

    function askModuleIcons(): void {
        command.createObject(root, {
            command: ["qs", "ipc", "-p", shell, "call", "bar", "moduleIcons"],
            done: (output, code) => {
                let icons = {};
                try {
                    if (code === 0)
                        icons = JSON.parse(output);
                } catch (error) {}
                if (JSON.stringify(icons) !== JSON.stringify(moduleIcons))
                    moduleIcons = icons;
            }
        });
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.askModuleIcons()
    }

    // One per module of the bar, one per item in the tray now, then one per
    // choice for a tray item that is not there: key, label, module (one of
    // the bar's own), own (a tray item's icon, an image), preset (what the
    // shell draws for it unasked, or ""), icon (what it draws now, or "" for
    // its own), isChosen (an icon is), hide ("", "idle" or "always"), running.
    readonly property list<var> entries: {
        const entries = [];
        const seen = {};
        for (const [module, label, standIn] of Symbols.modules()) {
            const key = Symbols.moduleKey(module);
            const icon = moduleIcons[module] || standIn;
            seen[key] = true;
            entries.push({
                key: key,
                label: label,
                module: true,
                own: "",
                preset: icon,
                icon: icon,
                isChosen: false,
                hide: chosen[key]?.hide ?? "",
                running: true
            });
        }
        for (const item of SystemTray.items.values) {
            const key = Symbols.key(item.id, item.title, item.tooltipTitle);
            if (key in seen)
                continue;
            seen[key] = true;
            const preset = Symbols.forItem(item.id, item.title, item.tooltipTitle, item.icon);
            const choice = chosen[key] ?? {};
            entries.push({
                key: key,
                label: Symbols.label(item.id, item.title, item.tooltipTitle),
                module: false,
                own: item.icon,
                preset: preset,
                icon: choice.icon ?? preset,
                isChosen: "icon" in choice,
                hide: choice.hide ?? "",
                running: true
            });
        }
        for (const key of Object.keys(chosen).sort())
            if (!(key in seen))
                entries.push({
                    key: key,
                    label: key,
                    module: false,
                    own: "",
                    preset: "",
                    icon: chosen[key].icon ?? "",
                    isChosen: "icon" in chosen[key],
                    hide: chosen[key].hide ?? "",
                    running: false
                });
        return entries;
    }

    // The same by key, and the keys in that order: the window makes a row
    // per key and keeps it while its entry changes.
    readonly property list<string> keys: entries.map(entry => entry.key)
    readonly property var byKey: {
        const byKey = {};
        for (const entry of entries)
            byKey[entry.key] = entry;
        return byKey;
    }

    function source(icon: string): string {
        return Symbols.source(icon, tablerDir);
    }

    // the size the bar draws the icon at, or 0 for the size of its square
    function size(icon: string, square: int): int {
        return Symbols.size(icon, square);
    }

    // "mail-unread-symbolic", "Tabler: mail", a file's name
    function describe(icon: string): string {
        if (icon.startsWith("tabler/"))
            return "Tabler: " + icon.slice(7);
        return icon.replace(/^.*\//, "");
    }

    // `icon` as symbols.js writes it; "" is the item's own icon
    function choose(key: string, icon: string): void {
        change(key, "icon", icon);
    }

    // back to the icon the shell draws unasked
    function reset(key: string): void {
        change(key, "icon", undefined);
    }

    // "" (in the bar), "idle" (hidden until it wants attention) or "always"
    function hide(key: string, when: string): void {
        change(key, "hide", when === "" ? undefined : when);
    }

    // everything chosen for the item
    function forget(key: string): void {
        const next = Object.assign({}, chosen);
        delete next[key];
        save(next);
    }

    // Sets one thing chosen for an item, or with `undefined` drops it; an
    // item with nothing chosen has no entry.
    function change(key: string, what: string, value: var): void {
        const next = Object.assign({}, chosen);
        const choice = Object.assign({}, next[key] ?? {});
        if (value === undefined)
            delete choice[what];
        else
            choice[what] = value;
        if (Object.keys(choice).length > 0)
            next[key] = choice;
        else
            delete next[key];
        save(next);
    }

    function save(next: var): void {
        chosen = next;
        file.setText(JSON.stringify(next, null, 2) + "\n");
    }

    // Every icon there is to choose from, as symbols.js writes icons: the
    // Tabler glyphs, then the one-colour icons of the icon theme. Listed by
    // the shell's icons.sh when first asked for.
    property list<string> names: []
    property bool namesAsked: false
    readonly property Component command: Command {}

    function loadNames(): void {
        if (namesAsked)
            return;
        namesAsked = true;
        command.createObject(root, {
            command: ["sh", shell + "/icons.sh", tablerDir],
            done: (output, code) => names = output.split("\n").filter(name => name !== "")
        });
    }

    FileView {
        id: file

        path: root.path
        blockLoading: true
        // no file until something is chosen
        printErrors: false
        onLoaded: {
            try {
                root.chosen = JSON.parse(text()) ?? {};
            } catch (error) {
                console.warn("BarItems: ignoring unreadable", root.path, error);
            }
        }
    }
}
