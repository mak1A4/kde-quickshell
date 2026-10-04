.pragma library

// Which Tabler glyph stands for an icon the icon theme would draw.
//
// Notifications name their icon as the icon theme knows it. An application's
// icon stays what it is, in colour. But the standard names for states and
// devices (battery-caution, network-wireless, dialog-information, ...) are
// the system speaking, and those get a glyph: forIcon() returns the Tabler
// icon's name for them, and "" for everything else.
//
// The glyphs are in ../icons/tabler; a name used here must have its file
// there (tools/tabler.sh fetches them).

// Exact names first, then the first matching prefix, most specific first.
const exact = {
    "dialog-information": "info-circle",
    "dialog-warning": "alert-triangle",
    "dialog-error": "alert-circle",
    "dialog-question": "help-circle",
    "dialog-password": "lock",
    "dialog-ok": "circle-check",
    "dialog-ok-apply": "circle-check",
    "dialog-cancel": "circle-x",
    "emblem-important": "alert-circle",
    "emblem-default": "circle-check",
    "emblem-success": "circle-check",
    "emblem-error": "circle-x",
    "emblem-warning": "alert-triangle",
    "applications-internet": "world",
    "computer": "device-desktop",
    "computer-laptop": "device-laptop",
    "smartphone": "device-mobile",
    "phone": "device-mobile",
    "device-notifier": "usb",
    "system-lock-screen": "lock",
    "object-locked": "lock",
    "system-shutdown": "power",
    "system-reboot": "rotate",
    "system-log-out": "logout",
    "system-software-update": "package",
    "configure": "settings",
    "chronometer": "alarm",
    "notifications": "bell",
    "edit-copy": "copy"
};

const prefixes = [
    ["battery-caution", "battery-1"],
    ["battery-empty", "battery-1"],
    ["battery-low", "battery-1"],
    ["battery-0", "battery-1"],
    ["battery-full", "battery-4"],
    ["battery-good", "battery-3"],
    ["battery", "battery-2"],
    ["network-wireless-disconnected", "wifi-off"],
    ["network-wireless-offline", "wifi-off"],
    ["network-wireless", "wifi"],
    ["network-vpn", "shield-lock"],
    ["network-server", "server"],
    ["network-offline", "plug-connected-x"],
    ["network-disconnect", "plug-connected-x"],
    ["network", "network"],
    ["preferences-system-bluetooth", "bluetooth"],
    ["bluetooth", "bluetooth"],
    ["audio-volume-muted", "volume-off"],
    ["audio-volume", "volume"],
    ["audio-headphones", "headphones"],
    ["audio-headset", "headphones"],
    ["audio-input-microphone", "microphone"],
    ["microphone", "microphone"],
    ["audio", "music"],
    ["media-optical", "disc"],
    ["drive-removable", "usb"],
    ["media-removable", "usb"],
    ["drive", "database"],
    ["camera", "camera"],
    ["video-display", "device-desktop"],
    ["printer", "printer"],
    ["input-keyboard", "keyboard"],
    ["input-mouse", "mouse"],
    ["input-gaming", "device-gamepad"],
    ["mail", "mail"],
    ["appointment", "calendar-event"],
    ["view-calendar", "calendar-event"],
    ["alarm", "alarm"],
    ["software-update", "package"],
    ["update", "package"],
    ["folder-download", "download"],
    ["emblem-downloads", "download"],
    ["download", "download"],
    ["security-high", "shield-check"],
    ["security", "shield-lock"],
    ["system-suspend", "moon"],
    ["preferences-system-power", "bolt"],
    ["preferences-desktop-notification", "bell"],
    ["notification", "bell"],
    ["preferences", "settings"],
    ["user-trash", "trash"],
    ["weather", "cloud"],
    ["im-", "message"]
];

function forIcon(name) {
    // "-symbolic" is the same icon in another drawing
    const icon = name.replace(/-symbolic$/, "");
    if (icon in exact)
        return exact[icon];
    for (const [prefix, glyph] of prefixes)
        if (icon.startsWith(prefix))
            return glyph;
    return "";
}

// every glyph the tables can name, plus the one for a notification without
// any icon; for tools/tabler.sh
function all() {
    const names = ["bell"].concat(Object.values(exact), prefixes.map(pair => pair[1]));
    return names.filter((name, at) => names.indexOf(name) === at).sort();
}
