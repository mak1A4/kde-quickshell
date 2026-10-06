#!/bin/sh
# The login screen (Plasma Login Manager) kept in step with the user's
# session: the background of the shell's theme, and the settings KDE's own
# "Apply Plasma Settings" copies there (display scaling and arrangement,
# keyboard layouts, fonts, cursor, colours). The login screen runs as a user
# of its own, reads nothing in a home directory, and its files are root's and
# its own: so what is to be applied is boiled down to one word (`state`),
# what was applied last is kept where everyone can read it, and only when the
# two differ is root asked for (LoginScreen.qml, through pkexec).
#
#   login.sh check <config dir> [force]   "ok", "declined" or "needed <state>"
#   login.sh declined <state>             not to be asked for this state again
#   login.sh apply <config dir> <state>   as root: does it
#   login.sh undo                         as root: takes it all away
#
# What `apply` does:
#   - installs the shell's wallpaper (../plasma/background) for everyone;
#   - makes /var/lib/kde-quickshell/background, the user's and readable by
#     all: background.sh puts a copy of the theme's background there at each
#     change of theme, without root;
#   - sets that wallpaper for the login screen, in a file of its own in
#     /etc/plasmalogin.conf.d (a wallpaper chosen in System Settings is
#     written to /etc/plasmalogin.conf and counts for more);
#   - copies the user's kxkbrc, kdeglobals, plasmarc, kcminputrc,
#     kwinoutputconfig.json and fontconfig/fonts.conf to the login screen's
#     user, as KDE's helper does (plasma-login-manager, kcm/auth);
#   - says in polkit what this script is, so that the next question for the
#     password explains itself;
#   - installs browser-color.sh as a program of root's, and lets the user's
#     session run it without the password: it writes the theme's colour into
#     the browsers' policy at each change of theme, and nothing else;
#   - notes the state.

set -e

plugin=io.github.mak1a4.kde-quickshell.background
action=io.github.mak1a4.kde-quickshell.login
self=$(readlink -f "$0")
source="$(dirname "$self")/../plasma/background"

# Everything of the system's is under `$sys`: nothing as root, and for trying
# this out a directory, which only someone who is not root can name.
sys=
if [ "$(id -u)" != 0 ]; then
    sys=${LOGIN_TEST_ROOT:-}
fi
wallpaper="$sys/usr/share/plasma/wallpapers/$plugin"
shared="$sys/var/lib/kde-quickshell"
setting="$sys/etc/plasmalogin.conf.d/kde-quickshell.conf"
policy="$sys/usr/share/polkit-1/actions/$action.policy"
colourer="$sys/usr/local/libexec/kde-quickshell-browser-color"
applied="$shared/applied"
synced="kxkbrc kdeglobals plasmarc kcminputrc kwinoutputconfig.json fontconfig/fonts.conf"

# What would be applied, as one word. Not the files as they are: several of
# them change all day (the file dialog's size in kdeglobals, a monitor's
# brightness and every screen cast's virtual output in kwinoutputconfig.json),
# and each change would ask for the password.
state() {
    config=$1
    {
        echo 2
        echo "$self"
        find "$source" -type f | sort | xargs cat
        cat "$(dirname "$self")/browser-color.sh"
        for file in kxkbrc plasmarc kcminputrc fontconfig/fonts.conf; do
            cat "$config/$file" 2> /dev/null || true
        done
        # not the colour scheme or the icons: the shell's themes change those,
        # and a change of theme should not ask for the password. The login
        # screen has the colours of the last time something else was applied.
        for key in General/font General/XftHintStyle General/XftSubPixel KScreen/ScaleFactor KScreen/ScreenScaleFactors; do
            kreadconfig6 --file "$config/kdeglobals" --group "${key%/*}" --key "${key#*/}" 2> /dev/null || true
        done
        # the monitors that are monitors: size, scale and turn
        jq -c '[.[] | select(.name == "outputs") | .data[]
                | select((.connectorName // "") | startswith("Virtual") | not)
                | {connectorName, edidIdentifier, scale, mode, transform}]' "$config/kwinoutputconfig.json" 2> /dev/null || true
    } | sha256sum | cut -c1-16
}

case "$1" in
check)
    config=$2
    wanted=$(state "$config")
    remembered="${XDG_STATE_HOME:-$HOME/.local/state}/kde-quickshell/login-declined"
    if [ "$3" != force ] && [ "$(cat "$remembered" 2> /dev/null)" = "$wanted" ]; then
        echo declined
    elif [ "$(cat "$applied" 2> /dev/null)" = "$wanted" ] && [ -w "$shared/background" ] && [ -e "$setting" ] &&
        diff -rq "$source" "$wallpaper" > /dev/null 2>&1 && cmp -s "$(dirname "$self")/browser-color.sh" "$colourer"; then
        echo ok
    else
        echo "needed $wanted"
    fi
    ;;

declined)
    remembered="${XDG_STATE_HOME:-$HOME/.local/state}/kde-quickshell"
    mkdir -p "$remembered"
    echo "$2" > "$remembered/login-declined"
    ;;

apply)
    config=$2
    wanted=$3
    case "$wanted" in
        *[!0-9a-f]* | "") echo "login.sh: no state given" >&2; exit 2 ;;
    esac

    if [ "$(id -u)" = 0 ]; then
        # as root, for the user who asked: pkexec and sudo both say who
        uid=${PKEXEC_UID:-${SUDO_UID:?run this through pkexec or sudo}}
        user=$(id -nu "$uid")
        greeter=plasmalogin
        home=$(getent passwd "$greeter" | cut -d: -f6)
        # the user's files are read as the user, the greeter's written as the greeter
        as_user() { runuser -u "$user" -- "$@"; }
        as_greeter() { runuser -u "$greeter" -- "$@"; }
        [ -n "$home" ] || { echo "login.sh: no user $greeter, is Plasma Login Manager installed?" >&2; exit 1; }
    elif [ -n "$sys" ]; then
        user=$(id -nu)
        home="$sys/var/lib/plasmalogin"
        as_user() { "$@"; }
        as_greeter() { "$@"; }
    else
        echo "login.sh: apply needs root" >&2
        exit 1
    fi
    as_user test -d "$config" || { echo "login.sh: $config is no directory of $user's" >&2; exit 2; }

    rm -rf "$wallpaper"
    mkdir -p "$(dirname "$wallpaper")"
    cp -r "$source" "$wallpaper"
    chmod -R a+rX "$wallpaper"

    install -d -m 755 "$shared"
    if [ -z "$sys" ]; then
        install -d -m 755 -o "$user" "$shared/background"
    else
        install -d -m 755 "$shared/background"
    fi

    install -d -m 755 "$(dirname "$setting")"
    printf '[Greeter]\nWallpaperPluginId=%s\n' "$plugin" > "$setting"

    # the greeter keeps colours in a cache it only fills when it has none
    as_greeter rm -rf "$home/.cache"
    as_greeter mkdir -p "$home/.config/fontconfig"
    for file in $synced; do
        if as_user test -r "$config/$file"; then
            as_user cat "$config/$file" | as_greeter tee "$home/.config/$file" > /dev/null
        else
            as_greeter rm -f "$home/.config/$file"
        fi
    done

    install -d -m 755 "$(dirname "$colourer")"
    install -m 755 "$(dirname "$self")/browser-color.sh" "$colourer"

    install -d -m 755 "$(dirname "$policy")"
    cat > "$policy" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="$action">
    <description>Bring the login screen in step with your session</description>
    <message>The login screen is behind your session. Authenticate to give it your display scaling, keyboard layout, fonts, colours and the background of the shell's theme.</message>
    <icon_name>preferences-system-login</icon_name>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">$self</annotate>
  </action>
  <action id="$action.browser-color">
    <description>Give the browsers the colour of the shell's theme</description>
    <message>Authenticate to give the browsers the colour of the shell's theme.</message>
    <icon_name>preferences-desktop-color</icon_name>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/local/libexec/kde-quickshell-browser-color</annotate>
  </action>
</policyconfig>
EOF

    echo "$wanted" > "$applied"
    chmod 644 "$applied" "$setting" "$policy"
    ;;

undo)
    rm -rf "$wallpaper" "$shared"
    rm -f "$setting" "$policy" "$colourer"
    for dir in chromium opt/chrome opt/edge brave; do
        rm -f "$sys/etc/$dir/policies/managed/kde-quickshell.json"
    done
    echo "the login screen has Plasma's own wallpaper again; its copied settings are reset in System Settings, Login Screen"
    ;;

*)
    echo "usage: login.sh check <config dir> [force] | declined <state> | apply <config dir> <state> | undo" >&2
    exit 2
    ;;
esac
