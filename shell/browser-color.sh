#!/bin/sh
# Gives Chromium and the browsers made from it the colour of the shell's
# theme, the way Omarchy does: as machine policy ("BrowserThemeColor"), which
# counts for every profile and which a running browser takes up at once.
#
#   kde-quickshell-browser-color <rrggbb>
#   kde-quickshell-browser-color off        takes the policy away again
#
# While the policy is there, a browser does not let its theme be chosen in
# its own settings ("set by your organization"): `off` is for leaving the
# colour to the browser, which can take it from KDE itself ("Use Qt").
#
# Policy is root's to write. So this is not run from the repository: login.sh
# installs a copy as /usr/local/libexec/kde-quickshell-browser-color, root's,
# with a polkit rule that lets the user's session run that one file without
# the password (apply.sh, through pkexec, at a change of theme). What that
# grants is no more than this file does: the caller chooses a colour, six
# hexadecimal digits, or none, and nothing else: not a path, not a policy.

set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin

colour=${1:-}
[ "$(id -u)" -eq 0 ] || { echo "kde-quickshell-browser-color: needs root" >&2; exit 1; }

if [ "$colour" = off ]; then
    for dir in /etc/chromium/policies/managed /etc/opt/chrome/policies/managed /etc/opt/edge/policies/managed /etc/brave/policies/managed; do
        rm -f "$dir/kde-quickshell.json"
    done
    exit 0
fi

case "$colour" in
    *[!0-9a-f]* | "") echo "kde-quickshell-browser-color: expected six lowercase hex digits" >&2; exit 2 ;;
esac
[ ${#colour} -eq 6 ] || { echo "kde-quickshell-browser-color: expected six lowercase hex digits" >&2; exit 2; }

# Chromium's, which Helium reads too, is made if it is not there; the others
# only where their browser has made them.
install -d -m 755 -o root -g root /etc/chromium/policies /etc/chromium/policies/managed

for dir in /etc/chromium/policies/managed /etc/opt/chrome/policies/managed /etc/opt/edge/policies/managed /etc/brave/policies/managed; do
    # a directory of root's, not a link to somewhere else
    [ -d "$dir" ] && [ ! -L "$dir" ] && [ "$(stat -c %U "$dir")" = root ] || continue
    new=$(mktemp "$dir/.kde-quickshell.XXXXXX")
    # "device": dark or light as the desktop says
    printf '{"BrowserThemeColor": "#%s", "BrowserColorScheme": "device"}\n' "$colour" > "$new"
    chmod 644 "$new"
    mv -f "$new" "$dir/kde-quickshell.json"
done
