#!/bin/sh
# Rounded corners on every window, maximized ones too: builds and switches on
# the shell's own Breeze window decoration (kwin/breeze) and the KWin plugin
# that rounds the windows without a decoration (kwin/roundcorners).
#
#   kwin/corners.sh on            build both, install them, switch them on
#   kwin/corners.sh off           back to Breeze as installed, plugin unloaded
#   kwin/corners.sh radius <px>   the corners' radius (logical pixels), or
#   kwin/corners.sh radius        Breeze's own again (5)
#   kwin/corners.sh build         only build, and say where the two files are
#
# `on` asks for root once, to put the two files into Qt's plugin directory
# (not when they are there already and the same), and stays on at the next
# login. `off` leaves the files where they are. Both are built against the
# KWin installed here: run `on` again after a Plasma update. A plugin that is
# already loaded is replaced by its new build only at the next login.
set -e

here=$(cd "$(dirname "$0")" && pwd)
cache=${XDG_CACHE_HOME:-$HOME/.cache}/kde-quickshell
decoration=io.github.mak1a4.kde-quickshell.breeze
plugin=kdequickshell_roundcorners
plugins=$(qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null || qtpaths6 --query QT_INSTALL_PLUGINS 2>/dev/null || echo /usr/lib/qt6/plugins)

build() {
    breeze=$("$here/breeze/build.sh" "$cache/breeze" | tail -n 1)
    cmake -S "$here/roundcorners" -B "$cache/roundcorners-build" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo > "$cache/roundcorners-cmake.log" 2>&1 || {
        cat "$cache/roundcorners-cmake.log" >&2
        exit 1
    }
    cmake --build "$cache/roundcorners-build"
    corners=$cache/roundcorners-build/bin/kwin/plugins/$plugin.so
    [ -s "$breeze" ] && [ -s "$corners" ]
}

reconfigure() {
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
}

case "$1" in
    build)
        build
        printf '%s\n%s\n' "$breeze" "$corners"
        ;;
    on)
        build
        if ! cmp -s "$breeze" "$plugins/org.kde.kdecoration3/$decoration.so" || ! cmp -s "$corners" "$plugins/kwin/plugins/$plugin.so"; then
            as_root=sudo
            command -v pkexec > /dev/null && as_root=pkexec
            $as_root sh -c 'install -m 755 "$1" "$3/org.kde.kdecoration3/" && install -m 755 "$2" "$3/kwin/plugins/"' sh "$breeze" "$corners" "$plugins"
        fi
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "$decoration"
        kwriteconfig6 --file kwinrc --group Plugins --key "${plugin}Enabled" true
        reconfigure
        qdbus6 org.kde.KWin /Plugins org.kde.KWin.Plugins.LoadPlugin "$plugin" > /dev/null
        if qdbus6 org.kde.KWin /Plugins org.kde.KWin.Plugins.LoadedPlugins | grep -qx "$plugin"; then
            echo "on"
        else
            echo "the decoration is switched on, but KWin did not load $plugin" >&2
            exit 1
        fi
        ;;
    off)
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze
        kwriteconfig6 --file kwinrc --group Plugins --key "${plugin}Enabled" --delete
        qdbus6 org.kde.KWin /Plugins org.kde.KWin.Plugins.UnloadPlugin "$plugin"
        reconfigure
        echo "off"
        ;;
    radius)
        if [ -n "$2" ]; then
            kwriteconfig6 --file kwinrc --group KDEQuickshellRoundCorners --key Radius "$2"
        else
            kwriteconfig6 --file kwinrc --group KDEQuickshellRoundCorners --key Radius --delete
        fi
        reconfigure
        ;;
    *)
        sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
        exit 2
        ;;
esac
