.pragma library

// Which one-colour icon stands for a tray item.
//
// A tray item brings its own icon, usually in colour, often as a pixmap with
// no name at all. Some are drawn like the rest of the bar instead: the ones
// the user has chosen an icon for (BarItems.qml, set in the settings window)
// and, unless the user says otherwise, the ones listed here. forItem()
// returns the icon for the latter, and "" for everything else, which keeps
// the icon it came with.
//
// An icon is written as the icon theme's name for it ("mail-unread-symbolic"),
// "tabler/<name>" for one of the glyphs in icons/tabler, or a file's path.

// By the icon the item names, exactly.
const icons = {
    "krfb": "screen-shared-symbolic"
};

// By what the item calls itself (id, title and tooltip, lower case): the
// first entry found in it. Electron applications send a pixmap and an id like
// "chrome_status_icon_1", so the tooltip is often all there is to go by.
const names = [
    ["teams", "teams-for-linux-tray"],
    ["outlook", "mail-unread-symbolic"]
];

// The name of the item's own icon in the icon theme, or "" if it has none:
// a pixmap, or an icon from a theme directory the item brings. `icon` is the
// item's icon as Quickshell gives it: "image://icon/<name>" for a named one,
// with "?path=..." for the item's own directory.
function named(icon) {
    const found = /^image:\/\/icon\/([^?]+)$/.exec(icon);
    return found ? found[1] : "";
}

function forItem(id, title, tooltip, icon) {
    const name = named(icon);
    if (name in icons)
        return icons[name];
    const text = `${id} ${title} ${tooltip}`.toLowerCase();
    for (const [name, symbol] of names)
        if (text.includes(name))
            return symbol;
    return "";
}

const counted = /\s*\((\d+)\+?\)\s*$/;

// The count an item shows in its tooltip, as in "Microsoft Teams (2)", else 0.
// Such an item paints it into its own icon, which a replaced icon loses.
function count(tooltip) {
    const found = counted.exec(tooltip);
    return found ? Number(found[1]) : 0;
}

// What the user's choice for an item is filed under: its id, with its title
// if it has one (one program can have several items). Electron numbers its
// items ("teams-for-linux_status_icon_1"), and names them after itself if the
// application does not ("chrome_status_icon_1"): then the tooltip, without a
// count, has to do.
function key(id, title, tooltip) {
    const program = id.replace(/_status_icon_\d+$/, "");
    if (program === "" || program === "chrome")
        return tooltip.replace(counted, "").trim() || title || id;
    return title ? `${program}: ${title}` : program;
}

// What to call the item in a list.
function label(id, title, tooltip) {
    return tooltip.replace(counted, "").trim() || title || id.replace(/_status_icon_\d+$/, "");
}

// The icon as something `Kirigami.Icon` takes as its source; `tablerDir` is
// where the Tabler glyphs are.
function source(icon, tablerDir) {
    if (icon.startsWith("tabler/"))
        return `file://${tablerDir}/${icon.slice(7)}.svg`;
    return icon.startsWith("/") ? `file://${icon}` : icon;
}

// The size to draw the icon at, in the bar's icon square of `square` px, so
// that what is drawn is as large as the icon theme's symbolic icons beside
// it; 0 for no size of its own. Kirigami draws those at 16 px (the standard
// size below 18), and they nearly reach its edges. A Tabler glyph keeps 3 of
// its 24 units clear on every side, so it is drawn at 21 px to span 16.
function size(icon, square) {
    return icon.startsWith("tabler/") ? Math.round(square * 7 / 6) : 0;
}

// The bar's own modules that can be hidden like a tray item: what the module
// calls itself (BarItems.tucked()), what to call it in a list, and an icon
// for the list while the shell is not running: when it is, the list shows the
// icon the module has in the bar. What is chosen for one is filed under
// moduleKey().
function modules() {
    return [
        ["media", "Media Player", "media-playback-start-symbolic"],
        ["connect", "KDE Connect", "smartphone-symbolic"],
        ["network", "Network", "network-wired-symbolic"],
        ["audio", "Volume", "audio-volume-high-symbolic"],
        ["power", "Power and Battery", "battery-full-symbolic"],
        ["session", "Session", "system-shutdown-symbolic"]
    ];
}

function moduleKey(module) {
    return "module/" + module;
}
