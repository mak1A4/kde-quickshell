#!/bin/sh
# Prints the one-colour icons there are, one a line, as
# shell/modules/tray/symbols.js writes icons: the Tabler glyphs in the given
# directory as "tabler/<name>", then the one-colour icons of the icon theme
# and of the themes it inherits from, by name. For the settings window, as
# the icons to choose from for a tray item, and for the bar, which draws a
# tray item's own icon in its colour if it is one of these (BarItems.qml). One-colour are the symbolic
# icons ("...-symbolic") and what a theme keeps for panels (Papirus' "panel"
# directories, with icons for many applications' tray items).
#
#   icons.sh [<directory of the Tabler glyphs>]

for file in ${1:+"$1"/*.svg}; do
    [ -f "$file" ] || continue
    name=${file##*/}
    echo "tabler/${name%.svg}"
done

theme=$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null)
theme=${theme:-breeze}

# where icon themes are, in the order they are looked up
bases="$HOME/.icons
${XDG_DATA_HOME:-$HOME/.local/share}/icons"
old_ifs=$IFS
IFS=:
for data in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
    bases="$bases
$data/icons"
done
IFS=$old_ifs

# the theme, then what it inherits from, each once
seen=" "
queue=$theme
while [ -n "$queue" ]; do
    current=${queue%% *}
    case $queue in
        *" "*) queue=${queue#* } ;;
        *) queue= ;;
    esac
    case $seen in *" $current "*) continue ;; esac
    seen="$seen$current "
    inherits=
    while IFS= read -r base; do
        dir=$base/$current
        [ -d "$dir" ] || continue
        find -L "$dir" -type f \( -name '*-symbolic.svg' -o -path '*/panel/*.svg' \) 2>/dev/null
        if [ -z "$inherits" ] && [ -f "$dir/index.theme" ]; then
            inherits=$(sed -n 's/^Inherits=//p' "$dir/index.theme" | head -n 1 | tr ',' ' ')
        fi
    done <<LIST
$bases
LIST
    queue="$queue${queue:+ }$inherits"
done | sed 's|.*/||; s|\.svg$||' | sort -u
