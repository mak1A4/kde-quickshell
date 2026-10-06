#!/bin/sh
# Keeps what is Plasma's own out of the way while the shell runs, and gives it
# back when the shell is gone:
#   - its panels: loads the KWin script that parks them off screen, and at
#     the end unloads it and has the panels moved back;
#   - the icons on the desktop: Plasma's desktop (Folder View) is told to
#     show no file, and at the end what it was told before. Nothing is moved:
#     the files stay in the desktop folder.
#
#   panels.sh keep <shell pid> <directory with the two KWin scripts>
#   panels.sh hide-icons | show-icons     the second part by hand
#
# Like the keeper for the shortcuts (hotkeys.sh): one per shell process, and
# a restarted shell's keeper waits for the previous one to finish, so that
# nothing is given back under a shell that has just put it away.

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

# ---- desktop icons --------------------------------------------------------

# Plasma has no switch for them: its desktop is one of two layouts, and only
# its own dialog changes the layout. But the layout with icons has a filter,
# and "hide what matches *", for files of every type, is an empty desktop.
# What the filter was is kept in a file until it is put back: also over a
# logout, when this is ended before it gets to that.
before="${XDG_STATE_HOME:-$HOME/.local/state}/kde-quickshell/desktop-icons-before"

plasma() {
    busctl --user --json=short call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$1" 2> /dev/null | jq -r '.data[0] // empty'
}

hide_icons() {
    was=$(plasma '
        const was = {};
        for (const d of desktops()) {
            if (d.type !== "org.kde.plasma.folder")
                continue;
            d.currentConfigGroup = ["General"];
            was[d.id] = { filterMode: d.readConfig("filterMode"), filterPattern: d.readConfig("filterPattern"), filterMimeTypes: d.readConfig("filterMimeTypes") };
            d.writeConfig("filterMode", 2);
            d.writeConfig("filterPattern", "*");
            d.writeConfig("filterMimeTypes", ["all/all"]);
            d.reloadConfig();
        }
        print(JSON.stringify(was));')
    # not over what is noted already: that is the filter as the user had it
    if [ ! -s "$before" ] && [ -n "$was" ] && [ "$was" != "{}" ]; then
        mkdir -p "$(dirname "$before")"
        echo "$was" > "$before"
    fi
    [ -n "$was" ]
}

show_icons() {
    [ -s "$before" ] || return 0
    plasma "
        const was = $(jq -c . "$before");
        for (const d of desktops()) {
            const filter = was[d.id];
            if (!filter)
                continue;
            d.currentConfigGroup = ['General'];
            d.writeConfig('filterMode', filter.filterMode === '' ? 0 : Number(filter.filterMode));
            d.writeConfig('filterPattern', filter.filterPattern === '' ? '*' : filter.filterPattern);
            d.writeConfig('filterMimeTypes', /^(\\\\0)?\$/.test(filter.filterMimeTypes) ? [] : filter.filterMimeTypes.split(','));
            d.reloadConfig();
        }
        print('shown');" > /dev/null && rm -f "$before"
}

keep() {
    shell=$1; scripts=$2
    dir=${XDG_RUNTIME_DIR:-/tmp}
    exec 8> "$dir/kde-quickshell-panels.$shell.lock"
    flock -n 8 || exit 0
    exec 9> "$dir/kde-quickshell-panels.lock"
    flock 9
    load "$park" "$scripts/park-panels.js"
    # at a login plasmashell may not be there yet
    for try in 1 2 3 4 5 6; do
        hide_icons && break
        sleep 2
    done
    tail --pid="$shell" -f /dev/null
    show_icons
    scripting unloadScript s "$park" > /dev/null
    load "$unpark" "$scripts/unpark-panels.js"
    sleep 1
    scripting unloadScript s "$unpark" > /dev/null
    rm -f "$dir/kde-quickshell-panels.$shell.lock"
}

command=$1; shift
case $command in
    keep) keep "$@" ;;
    hide-icons) hide_icons ;;
    show-icons) show_icons ;;
    *) echo "panels.sh: unknown command '$command'" >&2; exit 2 ;;
esac
