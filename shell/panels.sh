#!/bin/sh
# Keeps Plasma's panels out of the way while the shell runs: loads the KWin
# script that parks them off screen, stays until the shell's process is gone,
# then unloads it and has the panels moved back.
#
#   panels.sh keep <shell pid> <directory with the two KWin scripts>
#
# Like the keeper for the shortcuts (hotkeys.sh): one per shell process, and
# a restarted shell's keeper waits for the previous one to finish, so that
# the panels are not moved back under a shell that has just parked them.

park=kde-quickshell-park-panels
unpark=kde-quickshell-unpark-panels

scripting() {
    busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting "$@"
}

# loads a KWin script under a name and runs it; a leftover of that name goes first
load() {
    scripting unloadScript s "$1" > /dev/null 2>&1
    id=$(scripting loadScript ss "$2" "$1" | cut -d' ' -f2)
    [ -n "$id" ] && [ "$id" -ge 0 ] || return 1
    busctl --user call org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script run > /dev/null
}

keep() {
    shell=$1; scripts=$2
    dir=${XDG_RUNTIME_DIR:-/tmp}
    exec 8> "$dir/kde-quickshell-panels.$shell.lock"
    flock -n 8 || exit 0
    exec 9> "$dir/kde-quickshell-panels.lock"
    flock 9
    load "$park" "$scripts/park-panels.js"
    tail --pid="$shell" -f /dev/null
    scripting unloadScript s "$park" > /dev/null
    load "$unpark" "$scripts/unpark-panels.js"
    sleep 1
    scripting unloadScript s "$unpark" > /dev/null
    rm -f "$dir/kde-quickshell-panels.$shell.lock"
}

command=$1; shift
case $command in
    keep) keep "$@" ;;
    *) echo "panels.sh: unknown command '$command'" >&2; exit 2 ;;
esac
