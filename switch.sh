#!/bin/sh
# The shell switched off and on as a whole.
#
#   switch.sh off      stops the shell and takes away everything it has put
#                      outside itself: KDE as it was without it
#   switch.sh on       starts the shell again, which puts it all back
#   switch.sh status   says whether it is on
#
# What stays while it is off is the shell's own: its settings in
# ~/.config/kde-quickshell (the theme chosen, the dock's pins, the keys of
# its shortcuts, the themes and backgrounds of one's own) and its history in
# Quickshell's state directory (notifications, the launcher's counts).
# Nothing but the shell reads those. Everything else goes: what the theme
# did to KDE and to other programs is undone with what was noted before it
# was changed (the "-before" files of setup.sh, apply.sh and
# background.sh), and what the shell installed is removed. Root's part (the
# login screen, the browsers' colour, the rounded corners' plugins) asks for
# the password once, and only if it is there.
#
# `on` makes the autostart entry and starts the shell. The shell does the
# rest itself, as at its first start: setup.sh, the theme (ThemeExport.qml,
# apply.sh), the background, the notification helper, the login screen
# (which asks for the password), the shortcuts' keys (hotkeys.sh). The
# rounded corners come back if they were on (`kwin/corners.sh on`, which
# builds them and asks for the password).
#
# Also among the shell's ">" actions: "Switch the shell off".

set -u

here=$(cd "$(dirname "$0")" && pwd -P)
shell="$here/shell"
config=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}
state=${XDG_STATE_HOME:-$HOME/.local/state}/kde-quickshell
cache=${XDG_CACHE_HOME:-$HOME/.cache}/kde-quickshell
own="$config/kde-quickshell"
# what was on when the shell was switched off, for `on`
memo="$own/switched-off"
autostart="$config/autostart/kde-quickshell-shell.desktop"
unit='app-kde\x2dquickshell\x2dshell@autostart.service'
plugins=$(qmake6 -query QT_INSTALL_PLUGINS 2> /dev/null || qtpaths6 --query QT_INSTALL_PLUGINS 2> /dev/null || echo /usr/lib/qt6/plugins)
corners="$plugins/org.kde.kdecoration3/io.github.mak1a4.kde-quickshell.breeze.so $plugins/kwin/plugins/kdequickshell_roundcorners.so"

# what is said goes to the terminal, or, started from the shell's ">"
# actions without one, into a notification at the end
told=
say() {
    printf '%s\n' "$*"
    told="$told$*
"
}

tell() {
    [ -t 1 ] || notify-send --app-name "Quickshell" --icon preferences-desktop-theme-global "$1" "$told" 2> /dev/null
}

running() {
    ! qs list -p "$shell" 2>&1 | grep -q "No running instances"
}

# the keepers put Plasma's panels and the keys back when the shell is gone
keepers() {
    pgrep -f "/panels.sh keep|/hotkeys.sh keep" > /dev/null
}

# A file in KDE's configuration back to what it was, from a note of the
# value, or without the key if there was none. A note of "" means none.
restore_key() {
    file=$1 group=$2 key=$3 note=$4
    [ -e "$note" ] || return 0
    value=$(cat "$note")
    if [ -n "$value" ]; then
        kwriteconfig6 --file "$file" --group "$group" --key "$key" "$value"
    else
        kwriteconfig6 --file "$file" --group "$group" --key "$key" --delete
    fi
}

off() {
    # ---- the shell itself
    if running; then
        systemctl --user stop "$unit" 2> /dev/null
        running && qs kill -p "$shell" > /dev/null 2>&1
        say "stopped the shell"
    fi
    waited=0
    while keepers && [ "$waited" -lt 20 ]; do
        sleep 0.5
        waited=$((waited + 1))
    done
    # Should a keeper have been ended before its time: by hand. Nothing
    # happens if they did their work.
    if keepers; then
        say "warning: the panels' or the shortcuts' keeper is still running"
    else
        sh "$shell/panels.sh" show-icons
        sh "$shell/panels.sh" show-panels "$here/kwin"
    fi
    if [ -e "$autostart" ]; then
        rm -f "$autostart"
        say "removed the autostart entry"
    fi
    rm -rf "$config/systemd/user/app-kde\\x2dquickshell\\x2dshell@autostart.service.d"

    # ---- what is noted for `on`
    mkdir -p "$own"
    : > "$memo.new"
    if [ "$(kreadconfig6 --file kwinrc --group Plugins --key kdequickshell_roundcornersEnabled)" = true ]; then
        echo "corners=on" >> "$memo.new"
        radius=$(kreadconfig6 --file kwinrc --group KDEQuickshellRoundCorners --key Radius)
        [ -n "$radius" ] && echo "radius=$radius" >> "$memo.new"
    fi
    # a second `off` keeps what the first one noted
    if [ -s "$memo.new" ] || [ ! -e "$memo" ]; then
        mv "$memo.new" "$memo"
    else
        rm -f "$memo.new"
    fi

    # ---- shortcuts: the keys noted for the next start, the actions out of
    # KDE, KRunner's and Plasma's keys their own again
    sh "$shell/hotkeys.sh" off kde-quickshell && say "took the shortcuts out of KDE"

    # ---- rounded corners
    if [ "$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key library)" = io.github.mak1a4.kde-quickshell.breeze ] ||
        [ -n "$(kreadconfig6 --file kwinrc --group Plugins --key kdequickshell_roundcornersEnabled)" ]; then
        sh "$here/kwin/corners.sh" off > /dev/null 2>&1
        say "switched the rounded corners off"
    fi
    kwriteconfig6 --file kwinrc --group KDEQuickshellRoundCorners --key Radius --delete

    # ---- backgrounds: the desktop's and the lock screen's wallpaper back
    sh "$shell/background.sh" "" "" "" > /dev/null 2>&1
    kpackagetool6 --type Plasma/Wallpaper --remove io.github.mak1a4.kde-quickshell.background > /dev/null 2>&1 &&
        say "removed the background wallpaper plugin"

    # ---- lock screen
    rm -rf "$data/plasma/shells/io.github.mak1a4.kde-quickshell.lock"
    if [ -e "$config/systemd/user/plasma-kwin_wayland.service.d/kde-quickshell-lock.conf" ]; then
        rm -f "$config/systemd/user/plasma-kwin_wayland.service.d/kde-quickshell-lock.conf"
        say "removed the lock screen (KDE's own from the next login)"
    fi
    rmdir "$config/systemd/user/plasma-kwin_wayland.service.d" 2> /dev/null
    systemctl --user daemon-reload 2> /dev/null

    # ---- KDE's colours and icons
    if [ -e "$state/colorscheme-before" ]; then
        plasma-apply-colorscheme "$(cat "$state/colorscheme-before")" > /dev/null 2>&1 && say "KDE's colours: $(cat "$state/colorscheme-before")"
    else
        case "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)" in
            Quickshell*) plasma-apply-colorscheme BreezeLight > /dev/null 2>&1 && say "KDE's colours: BreezeLight (what it was is not known)" ;;
        esac
    fi
    if [ -e "$state/icons-before" ] && [ "$(kreadconfig6 --file kdeglobals --group Icons --key Theme)" != "$(cat "$state/icons-before")" ]; then
        /usr/lib/plasma-changeicons "$(cat "$state/icons-before")" > /dev/null 2>&1 && say "icons: $(cat "$state/icons-before")"
    fi
    rm -f "$data"/color-schemes/Quickshell*.colors

    # ---- the calendar's holidays, if the shell chose them
    if [ -e "$state/holidays-set" ]; then
        kwriteconfig6 --file plasma_calendar_holiday_regions --group General --key selectedRegions --delete
    fi

    # ---- other programs
    if [ -e "$config/gtk-4.0/kde-quickshell.css" ] || grep -qsF "@import 'kde-quickshell.css';" "$config/gtk-4.0/gtk.css"; then
        rm -f "$config/gtk-4.0/kde-quickshell.css"
        if [ -f "$config/gtk-4.0/gtk.css" ]; then
            grep -vF "@import 'kde-quickshell.css';" "$config/gtk-4.0/gtk.css" > "$config/gtk-4.0/gtk.css.new"
            cat "$config/gtk-4.0/gtk.css.new" > "$config/gtk-4.0/gtk.css"
            rm -f "$config/gtk-4.0/gtk.css.new"
        fi
        say "GTK: the shell's style sheet removed"
    fi
    if grep -qs '^color_theme = "kde-quickshell"' "$config/btop/btop.conf"; then
        before=$(cat "$state/btop-before" 2> /dev/null)
        sed "s|^color_theme = .*|color_theme = \"${before:-Default}\"|" "$config/btop/btop.conf" > "$config/btop/btop.conf.new"
        cat "$config/btop/btop.conf.new" > "$config/btop/btop.conf"
        rm -f "$config/btop/btop.conf.new"
        say "btop: ${before:-Default}"
    fi
    rm -f "$config/btop/themes/kde-quickshell.theme"
    vscode_off
    for extension in $(cat "$state/vscode-installed" 2> /dev/null); do
        code --uninstall-extension "$extension" > /dev/null 2>&1
    done
    [ -s "$state/vscode-installed" ] && say "VS Code: the themes' extensions the shell installed removed"

    # ---- what the shell installed for itself
    kpackagetool6 --type Plasma/Applet --remove io.github.mak1a4.kde-quickshell.handover > /dev/null 2>&1 &&
        say "removed the notification helper from Plasma (gone from plasmashell at its next start)"
    if [ -e "$data/applications/kde-quickshell.desktop" ]; then
        rm -f "$data/applications/kde-quickshell.desktop"
        kbuildsycoca6 > /dev/null 2>&1
    fi
    rm -rf "$data/kde-quickshell" "$cache"

    # ---- root's part
    login_root=
    for file in /etc/plasmalogin.conf.d/kde-quickshell.conf /var/lib/kde-quickshell /usr/local/libexec/kde-quickshell-browser-color \
        /usr/share/polkit-1/actions/io.github.mak1a4.kde-quickshell.login.policy /usr/share/plasma/wallpapers/io.github.mak1a4.kde-quickshell.background $corners; do
        [ -e "$file" ] && login_root=1
    done
    if [ -n "$login_root" ]; then
        say "root's part (login screen, browsers' colour, corners' plugins): asking for the password"
        if pkexec "$here/switch.sh" root-off "$plugins"; then
            say "root's part removed"
        else
            say "root's part NOT removed: run  sudo $here/switch.sh root-off $plugins"
        fi
    fi

    # Last: the notes of what was before. (The terminals and Neovim take
    # their own colours again once the theme's files are gone.)
    rm -rf "$state"
    say "the shell is off; $here/switch.sh on starts it again"
    tell "The shell is switched off"
}

# VS Code's three theme settings back to what they were (noted by apply.sh
# as "file<TAB>key<TAB>value" lines, the value "-" for none), or without
# them where nothing was noted.
vscode_off() {
    for settings in "$config/Code/User/settings.json" "$config/Code - OSS/User/settings.json" "$config/VSCodium/User/settings.json"; do
        [ -f "$settings" ] || continue
        python3 - "$settings" "$state/vscode-before" << 'EOF' && say "VS Code: its theme settings as before ($settings)"
import re, sys
path, notes = sys.argv[1], sys.argv[2]
text = open(path).read()
keys = ["workbench.colorTheme", "workbench.preferredDarkColorTheme", "workbench.preferredLightColorTheme"]
before = {}
try:
    for line in open(notes):
        file, key, value = line.rstrip("\n").split("\t")
        if file == path:
            before[key] = value
except FileNotFoundError:
    pass
new = text
for key in keys:
    pattern = r'("' + re.escape(key) + r'"\s*:\s*)"[^"]*"'
    if key in before and before[key] != "-":
        new = re.sub(pattern, lambda m: m.group(1) + '"' + before[key] + '"', new)
    else:
        new = re.sub(r'\n[ \t]*"' + re.escape(key) + r'"\s*:\s*"[^"]*",?', "", new)
if new == text:
    sys.exit(1)
open(path, "w").write(new)
EOF
    done
}

# as root, through pkexec: the login screen's part (login.sh undo) and the
# rounded corners' plugins
root_off() {
    [ "$(id -u)" = 0 ] || { echo "switch.sh root-off: needs root" >&2; exit 1; }
    sh "$here/shell/login.sh" undo > /dev/null
    for file in $corners; do
        rm -f "$file"
    done
}

on() {
    if running; then
        say "the shell is running already"
        return 0
    fi
    if [ -e "$autostart" ]; then
        # switched off in System Settings, Autostart: on again
        sed -i '/^Hidden=true/d' "$autostart"
    elif [ "$(jq -r '.autostart // true' "$own/setup.json" 2> /dev/null)" != false ]; then
        mkdir -p "$(dirname "$autostart")"
        sed "s|@QS@|$(command -v qs)|; s|@SHELL@|$shell|" "$here/packaging/kde-quickshell-shell.desktop" > "$autostart"
        say "made the autostart entry"
    fi
    # KWin gives the window list only to a program whose desktop entry it
    # knew when the program started (setup.sh puts it there too, but from
    # inside the shell: too late for this start)
    mkdir -p "$data/applications"
    cp "$here/packaging/kde-quickshell.desktop" "$data/applications/kde-quickshell.desktop"
    kbuildsycoca6 > /dev/null 2>&1
    systemctl --user daemon-reload
    if [ -e "$autostart" ]; then
        systemctl --user start "$unit"
    else
        systemd-run --user --scope --quiet -- qs -n -p "$shell" -d > /dev/null 2>&1
    fi
    say "started the shell: it puts its theme, lock screen and the rest back by itself"
    if grep -qx "corners=on" "$memo" 2> /dev/null; then
        say "rounded corners: building and switching them on (asks for the password)"
        if sh "$here/kwin/corners.sh" on; then
            radius=$(sed -n 's/^radius=//p' "$memo")
            [ -n "$radius" ] && sh "$here/kwin/corners.sh" radius "$radius"
        fi
    fi
    rm -f "$memo"
}

case "${1:-}" in
    off) off ;;
    on) on ;;
    root-off) plugins=${2:-$plugins}; corners="$plugins/org.kde.kdecoration3/io.github.mak1a4.kde-quickshell.breeze.so $plugins/kwin/plugins/kdequickshell_roundcorners.so"; root_off ;;
    status)
        if running; then
            say "on (running)"
        elif [ -e "$autostart" ] && ! grep -qs '^Hidden=true' "$autostart"; then
            say "on (not running; starts at the next login)"
        else
            say "off"
        fi
        ;;
    *)
        echo "usage: switch.sh off | on | status" >&2
        exit 2
        ;;
esac
