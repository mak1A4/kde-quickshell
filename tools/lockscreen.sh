#!/bin/sh
# Makes KDE's lock screen the shell's (plasma/lockscreen), or Plasma's again.
#
#   tools/lockscreen.sh          installs it; run again after changing it
#   tools/lockscreen.sh --undo   takes it away
#
# The locker takes its interface from the "shell package" Plasma runs with,
# and there is no setting for the lock screen alone: naming another package
# in plasmashellrc would change plasmashell too, panels and desktop with it.
# But the package may also be named in the environment, and the locker is
# started by KWin. So this
#   - copies plasma/lockscreen, with the shell's frame shader, to the user's
#     shell packages; it holds nothing but a lock screen, the rest is still
#     found in Plasma's own package;
#   - names it in PLASMA_DEFAULT_SHELL for KWin's service alone, in a drop-in
#     of the user's systemd.
# KWin has its environment from its start: this counts from the next login.
# If the interface cannot be loaded, the locker shows its built-in one. If it
# loads but cannot be used, from a console (Ctrl+Alt+F3):
#   loginctl unlock-sessions

set -e

id=io.github.mak1a4.kde-quickshell.lock
here=$(dirname "$(readlink -f "$0")")
dest="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/shells/$id"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
dropin="$config/systemd/user/plasma-kwin_wayland.service.d/kde-quickshell-lock.conf"

if [ "$1" = --undo ]; then
    rm -rf "$dest"
    rm -f "$dropin"
    rmdir "$(dirname "$dropin")" 2> /dev/null || true
    systemctl --user daemon-reload
    echo "Plasma's own lock screen again, from the next login"
    exit 0
fi

rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
cp -r "$here/../plasma/lockscreen" "$dest"
cp "$here/../shell/shaders/frame.frag.qsb" "$dest/contents/lockscreen/"

if [ ! -e "$dropin" ]; then
    mkdir -p "$(dirname "$dropin")"
    printf '# the lock screen of the Quickshell shell (kde-quickshell, tools/lockscreen.sh)\n[Service]\nEnvironment=PLASMA_DEFAULT_SHELL=%s\n' "$id" > "$dropin"
    systemctl --user daemon-reload
    echo "installed; the lock screen is the shell's from the next login"
else
    echo "updated; the next lock shows it"
fi

if [ -n "$(kreadconfig6 --file plasmashellrc --group Shell --key ShellPackage)" ]; then
    echo "note: plasmashellrc names a shell package, and that counts for more than the environment" >&2
fi
