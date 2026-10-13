#!/bin/sh
# Backgrounds for the shell's themes from Studio Ghibli's films: stills the
# studio itself gives out (https://www.ghibli.jp/works/, fifty of each film,
# 1920x1038, "to be used freely within the bounds of common sense"). Those
# that are a wallpaper on their own, landscapes and skies rather than faces.
# Each is put with the existing theme whose colours it goes with
# (shell/Themes.qml: a theme's backgrounds are the files in
# ~/.config/kde-quickshell/themes/backgrounds/<theme>/). Which goes with
# which is a matter of taste: move a file to another theme's directory to
# change it.
#
#   ghibli.sh [<name> ...]     all of them, or only those named
#
# The files are fetched from the studio's site, about 20 MB in all, and are
# not part of this repository. One that is already there is not fetched
# again.

set -e

from=https://www.ghibli.jp/gallery
backgrounds="${XDG_CONFIG_HOME:-$HOME/.config}/kde-quickshell/themes/backgrounds"

# theme, name, the still's name on the studio's site
list='everforest-light arrietty-garden karigurashi022
everforest-light totoro-house totoro001
everforest-light wind-rises-clearing kazetachinu050
solarized-light marnie-silo marnie003
solarized-light ponyo-house ponyo006
catppuccin-latte howl-balcony howl050
catppuccin-latte ponyo-flood ponyo041
rose-pine-dawn kaguya-blossom kaguyahime037
rose-pine-dawn porco-dusk porco015
breeze-light wind-rises-sky kazetachinu044
breeze-light ponyo-island ponyo005
gruvbox-light kaguya-hut kaguyahime006
gruvbox-light totoro-field totoro041
kanagawa-lotus kaguya-flowers kaguyahime036
kanagawa-lotus kaguya-tree kaguyahime012
flexoki-light kaguya-meadow kaguyahime013
ayu-light wind-rises-painter kazetachinu024
ayu-light heron-stones kimitachi044
github-light wind-rises-glider kazetachinu043
github-light poppy-hill-flags kokurikozaka002
one-light howl-castle-sky howl049
one-light laputa-island laputa036
tokyo-night-day whisper-city mimi033
tokyo-night-day marnie-marsh marnie010
iceberg-light marnie-bay marnie006
iceberg-light marnie-beach marnie050
dayfox spirited-train chihiro043
dayfox marnie-sunset marnie021
melange-light howl-meadow howl009
melange-light marnie-mansion marnie009
ayu-mirage porco-sunset porco007
ayu-mirage howl-scarecrow howl010
one-dark howl-castle howl011
one-dark whisper-dawn mimi046
flexoki-dark spirited-bathhouse chihiro011
github-dark-dimmed poppy-hill-ship kokurikozaka036
oxocarbon ponyo-moon ponyo038
oxocarbon whisper-cave mimi040
rose-pine-moon totoro-dusk totoro047
everforest totoro-tunnel totoro019
everforest mononoke-kodama mononoke023
gruvbox-dark mononoke-forest mononoke010
tokyo-night totoro-flight totoro036
tokyo-night kiki-night majo011
nord mononoke-night mononoke024
kanagawa laputa-sunset laputa050
catppuccin-mocha totoro-tree totoro034
catppuccin-macchiato marnie-night marnie022
catppuccin-frappe whisper-sunrise mimi048
solarized-dark spirited-tracks chihiro041
dracula nausicaa-jungle nausicaa002
breeze-dark totoro-rain totoro029'

echo "$list" | while read -r theme name still; do
    if [ $# -gt 0 ]; then
        case " $* " in
            *" $name "*) ;;
            *) continue ;;
        esac
    fi
    file="$backgrounds/$theme/$name.jpg"
    # with another theme already: the user has moved it
    if ls "$backgrounds"/*/"$name".* > /dev/null 2>&1; then
        continue
    fi
    mkdir -p "$backgrounds/$theme"
    echo "$name: fetching $still.jpg for $theme"
    # fetched next to the themes' directories and moved in whole: the shell
    # lists a theme's directory again when a file appears in it
    curl -fL --retry 3 --progress-bar -o "$backgrounds/.$name.part" "$from/$still.jpg"
    mv "$backgrounds/.$name.part" "$file"
done
