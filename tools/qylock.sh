#!/bin/sh
# Backgrounds for the shell's themes from qylock
# (https://github.com/Darkkal44/qylock), a collection of login and lock
# screens: those of its pictures and videos that are a wallpaper on their own,
# without the screens made around them. Each is put with the existing theme
# whose colours it goes with (shell/Themes.qml: a theme's backgrounds are the
# files in ~/.config/kde-quickshell/themes/backgrounds/<theme>/). Which goes
# with which is a matter of taste: move a file to another theme's directory
# to change it.
#
#   qylock.sh [<name> ...]     all of them, or only those named
#
# The files are fetched from qylock's repository, about 470 MB in all, and are
# not part of this one: most are artwork of games and films. One that is
# already there is not fetched again.

set -e

from=https://raw.githubusercontent.com/Darkkal44/qylock/main/themes
backgrounds="${XDG_CONFIG_HOME:-$HOME/.config}/kde-quickshell/themes/backgrounds"

# theme, name, file in qylock's themes directory
list='everforest dog-samurai dog-samurai/bg.mp4
everforest forest forest/bg.mp4
rose-pine enfield enfield/bg.mp4
rose-pine pixel-skyscrapers pixel-skyscrapers/bg.mp4
catppuccin-latte genshin-dawn Genshin/dawn.mp4
catppuccin-latte genshin-day Genshin/day.mp4
catppuccin-latte pixel-munchlax pixel-munchlax/bg.mp4
catppuccin-macchiato genshin-dusk Genshin/dusk.mp4
tokyo-night genshin-night Genshin/night.mp4
tokyo-night pixel-cyberpunk pixel-cyberpunk/bg.mp4
tokyo-night pixel-night-city pixel-night-city/bg.mp4
tokyo-night pixel-rainyroom pixel-rainyroom/bg.mp4
gruvbox-dark last-of-us last-of-us/bg.mp4
gruvbox-dark pixel-hollowknight pixel-hollowknight/bg.mp4
gruvbox-dark r1999 R1999_1/bg.mp4
catppuccin-mocha pixel-coffee pixel-coffee/bg.mp4
catppuccin-mocha star-rail star-rail/bg.mp4
kanagawa pixel-dusk-city pixel-dusk-city/bg.mp4
kanagawa field field/bg.png
everforest-light pixel-emerald pixel-emerald/bg.mp4
everforest-light material-you material-you/bg.png
rose-pine-dawn pixel-sakura pixel-sakura/bg.mp4
rose-pine-dawn women-umbrella women-umbrella/bg.png
solarized-dark pixel-waterfall pixel-waterfall/bg.mp4
solarized-light man-bicycle man-bicycle/bg.png
nord sword sword/bg.mp4
nord winter winter/bg.mp4
nord wuwa wuwa/bg.mp4
catppuccin-frappe girl-coffee girl-coffee/bg.png
dracula material-you-dark material-you-dark/bg.png'

echo "$list" | while read -r theme name path; do
    if [ $# -gt 0 ]; then
        case " $* " in
            *" $name "*) ;;
            *) continue ;;
        esac
    fi
    file="$backgrounds/$theme/$name.${path##*.}"
    # with another theme already: the user has moved it
    if ls "$backgrounds"/*/"$name".* > /dev/null 2>&1; then
        continue
    fi
    mkdir -p "$backgrounds/$theme"
    echo "$name: fetching $path for $theme"
    curl -fL --retry 3 --progress-bar -o "$file.part" "$from/$path"
    mv "$file.part" "$file"
done
