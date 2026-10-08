pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import QtQuick
import "modules/tray/symbols.js" as Symbols

// What the user has chosen for the items in the bar: for a tray item an icon
// in place of the one it brings, and for it or one of the bar's own modules
// whether it is in the bar at all. A file the settings window writes and this
// reads again whenever it changes. An entry is a tray item's key, or a
// module's (see symbols.js), and any of
//   icon: as symbols.js writes icons, or "" for "the item's own icon,
//         whatever symbols.js says"
//   hide: "always", or for a tray item "idle": hidden until it wants attention
// A hidden item is not gone: the bar shows it when asked (`expanded`, the
// arrow in Bar.qml).
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kde-quickshell/bar-items.json"
    // key -> { icon, hide }
    property var chosen: ({})

    function entry(item: var): var {
        return chosen[Symbols.key(item.id, item.title, item.tooltipTitle)] ?? {};
    }

    // The one-colour icon to draw for a tray item, as symbols.js writes
    // icons, or "" to draw the item's own.
    function icon(item: var): string {
        return entry(item).icon ?? Symbols.forItem(item.id, item.title, item.tooltipTitle, item.icon);
    }

    // that icon as a source for widgets/Icon.qml
    function source(icon: string): string {
        return Symbols.source(icon, Quickshell.shellPath("icons/tabler"));
    }

    // Whether the item is kept out of the bar for now. One hidden while idle
    // comes back while it says it needs attention, or has a count to show.
    function hidden(item: var): bool {
        const hide = entry(item).hide ?? "";
        if (hide === "idle")
            return item.status !== Status.NeedsAttention && Symbols.count(item.tooltipTitle) === 0;
        return hide === "always";
    }

    // Whether one of the bar's modules is put away: hidden, and not asked for.
    function tucked(module: string): bool {
        return !expanded && moduleHidden(module);
    }

    function moduleHidden(module: string): bool {
        return (chosen[Symbols.moduleKey(module)]?.hide ?? "") !== "";
    }

    // The icon theme's one-colour icons, by name: its symbolic icons and
    // what it keeps for panels (icons.sh lists them once, at the start). A
    // tray item that names one of these as its own icon gets it in the bar's
    // colour: drawn as it comes, it has the theme's colour for text on a
    // light panel, dark grey on the dark bar (KDE's microphone indicator).
    property var plainIcons: ({})

    function isPlain(name: string): bool {
        return name.endsWith("-symbolic") || plainIcons[name] === true;
    }

    // The one-colour icon of the icon theme to draw for a tray item's own
    // icon, by name, or "" to draw the icon as it comes. An item that brings
    // a directory for its icon gets the theme's of that name where it has
    // one, as in Plasma's tray: Steam's "steam_tray_mono" is a grey pixmap
    // there, and Papirus has a panel icon for it.
    function plain(icon: string): string {
        const name = Symbols.named(icon);
        if (name !== "")
            return isPlain(name) ? name : "";
        const brought = Symbols.brought(icon);
        return plainIcons[brought] === true ? brought : "";
    }

    Process {
        running: true
        command: ["sh", Quickshell.shellPath("icons.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = {};
                for (const name of text.split("\n"))
                    if (name !== "")
                        names[name] = true;
                root.plainIcons = names;
            }
        }
    }

    // The icon each module of the bar shows at the moment, by the module's
    // name; widgets/Icon.qml reports them. For the settings window, which
    // lists the modules with the icons they have in the bar.
    property var moduleIcons: ({})

    function report(module: string, icon: string): void {
        if (moduleIcons[module] === icon)
            return;
        const next = Object.assign({}, moduleIcons);
        next[module] = icon;
        moduleIcons = next;
    }

    // how many items are hidden now, and whether the bar shows them anyway
    readonly property int hiddenCount: SystemTray.items.values.filter(item => hidden(item)).length + Symbols.modules().filter(module => moduleHidden(module[0])).length
    property bool expanded: false

    // the next thing hidden starts out put away
    onHiddenCountChanged: {
        if (hiddenCount === 0)
            expanded = false;
    }

    // for scripts and tests: `qs ipc call bar toggleHidden`
    IpcHandler {
        target: "bar"

        function toggleHidden(): void {
            root.expanded = !root.expanded && root.hiddenCount > 0;
        }

        function isExpanded(): bool {
            return root.expanded;
        }

        function hiddenCount(): int {
            return root.hiddenCount;
        }

        // for the settings window: { "audio": "audio-volume-high-symbolic", ... }
        function moduleIcons(): string {
            return JSON.stringify(root.moduleIcons);
        }
    }

    FileView {
        path: root.path
        watchChanges: true
        // no file until the user chooses something
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: root.chosen = {}
        onLoaded: {
            try {
                root.chosen = JSON.parse(text()) ?? {};
            } catch (error) {
                console.warn("BarItems: ignoring unreadable", root.path, error);
                root.chosen = {};
            }
        }
    }
}
