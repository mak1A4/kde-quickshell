#!/bin/sh
# What the launcher asks of the system once.
#
#   launcher.sh favorites   the applications KDE's own menu has as favourites,
#                           a desktop entry's name without ".desktop" each, in
#                           its order: what the launcher starts out with

config="${XDG_CONFIG_HOME:-$HOME/.config}"

case "$1" in
favorites)
    # KDE keeps the list itself in a database; their order is in this file,
    # a line for each menu there has been, the last the one in use
    ordering=$(awk '/^\[Favorites-org\.kde\.plasma\.kickoff\.favorites\.instance-.*-global\]/ { found = 1; next }
                    /^\[/ { found = 0 }
                    found && /^ordering=/ { sub(/^ordering=/, ""); line = $0 }
                    END { print line }' "$config/kactivitymanagerd-statsrc" 2> /dev/null)
    printf '%s\n' "$ordering" | tr ',' '\n' | while read -r item; do
        case "$item" in
            applications:*.desktop)
                item=${item#applications:}
                echo "${item%.desktop}"
                ;;
            preferred://browser)
                browser=$(xdg-settings get default-web-browser 2> /dev/null)
                [ -n "$browser" ] && echo "${browser%.desktop}"
                ;;
        esac
    done
    ;;

*)
    echo "usage: launcher.sh favorites" >&2
    exit 2
    ;;
esac
