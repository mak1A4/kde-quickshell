#!/bin/sh
# Puts the theme's background on the desktop, the lock screen and the login
# screen, or gives them back when the theme has none.
#
#   background.sh <plugin directory> <theme name> [<picture or video>]
#
# All three show it through one Plasma wallpaper (plasma/background), which
# has no settings and shows the one file in a directory. So a change of theme
# only replaces that file:
#   - ~/.local/share/kde-quickshell/background: a link, for the desktop and
#     the lock screen;
#   - /var/lib/kde-quickshell/background: a copy, for the login screen, which
#     runs as another user and cannot read the home directory. Only if that
#     directory is there and writable (login.sh makes it, as root).
# With a background, the desktop and the lock screen are switched to that
# wallpaper, and what they had is noted; without one they get that back, and
# the login screen a copy of the desktop's picture.

plugin=io.github.mak1a4.kde-quickshell.background
src=$1
name=$2
file=$3

data="${XDG_DATA_HOME:-$HOME/.local/share}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/kde-quickshell"
own="$data/kde-quickshell/background"
shared=/var/lib/kde-quickshell/background
before="$state/wallpaper-before"

# the wallpaper itself, installed for the user if missing or changed
dest="$data/plasma/wallpapers/$plugin"
if [ -d "$src" ]; then
    if [ ! -d "$dest" ]; then
        kpackagetool6 --type Plasma/Wallpaper --install "$src" > /dev/null
    elif ! diff -rq "$src" "$dest" > /dev/null; then
        kpackagetool6 --type Plasma/Wallpaper --upgrade "$src" > /dev/null && echo upgraded
    fi
fi

plasma() {
    busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$1" 2> /dev/null |
        sed -e 's/^s "//' -e 's/"$//'
}

desktop_plugin() {
    plasma 'const d = desktops().find(d => d.screen >= 0) ?? desktops()[0]; print(d ? d.wallpaperPlugin : "")'
}

set_desktop_plugin() {
    plasma "for (const d of desktops()) if (d.wallpaperPlugin !== '$1') d.wallpaperPlugin = '$1'" > /dev/null
}

lock_plugin() {
    kreadconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin --default org.kde.image
}

# Leaves `$2` as the only file in directory `$1`, as a link or a copy (`$3`).
# The file's name there is the theme's: a new name is what the wallpaper
# takes for a new background. The new file is put there before the old one
# is taken away, so the directory is never empty in between: an empty one
# means "no background" to the wallpaper.
fill() {
    dir=$1 from=$2 how=$3
    target=
    if [ -n "$from" ]; then
        target="$dir/$name.${from##*.}"
        if [ "$how" = link ]; then
            [ "$(readlink "$target" 2> /dev/null)" = "$from" ] || ln -sfn "$from" "$target"
        elif ! cmp -s "$from" "$target"; then
            cp --reflink=auto "$from" "$target.part" && chmod 644 "$target.part" && mv -f "$target.part" "$target"
        fi
    fi
    for old in "$dir"/* "$dir"/.[!.]*; do
        [ -e "$old" ] || [ -L "$old" ] || continue
        [ "$old" = "$target" ] || rm -f "$old"
    done
}

mkdir -p "$own" "$state"

if [ -n "$file" ] && [ ! -r "$file" ]; then
    echo "background.sh: cannot read $file" >&2
    file=
fi

if [ -n "$file" ]; then
    fill "$own" "$file" link
    [ -w "$shared" ] && fill "$shared" "$file" copy

    # what the desktop and the lock screen showed before, noted once
    desktop=$(desktop_plugin)
    lock=$(lock_plugin)
    if [ ! -e "$before" ] && [ -n "$desktop" ]; then
        printf '%s\n%s\n' "$desktop" "$lock" > "$before"
    fi
    [ -z "$desktop" ] || [ "$desktop" = "$plugin" ] || set_desktop_plugin "$plugin"
    [ "$lock" = "$plugin" ] || kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "$plugin"
else
    fill "$own" "" link

    if [ -e "$before" ]; then
        desktop=$(sed -n 1p "$before")
        lock=$(sed -n 2p "$before")
        [ "$(desktop_plugin)" != "$plugin" ] || set_desktop_plugin "${desktop:-org.kde.image}"
        if [ "$(lock_plugin)" = "$plugin" ]; then
            # Plasma's own is what the lock screen has without the entry
            if [ "${lock:-org.kde.image}" = org.kde.image ]; then
                kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin --delete
            else
                kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "$lock"
            fi
        fi
        rm -f "$before"
    fi

    # the login screen keeps this wallpaper (changing that needs root): give
    # it the desktop's picture, if that is one file
    if [ -w "$shared" ]; then
        picture=$(plasma 'const d = desktops().find(d => d.screen >= 0) ?? desktops()[0]; if (d) { d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"]; print(d.readConfig("Image")) }')
        picture=${picture#file://}
        name=desktop
        if [ -f "$picture" ]; then
            fill "$shared" "$picture" copy
        else
            fill "$shared" "" copy
        fi
    fi
fi
