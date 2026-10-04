#!/bin/sh
# The shell's global shortcuts in KDE's shortcut service (KGlobalAccel), over
# its D-Bus interface with busctl. Used by Hotkeys.qml and by the settings.
#
#   hotkeys.sh register <component> <name> [<action> <action name> <default key>]...
#       Makes the actions known to KDE and active. Keys are Qt key numbers,
#       0 for none.
#   hotkeys.sh keep <shell pid> <component> <name> [<action> ...]...
#       Stays until the shell's process is gone, then gives the keys back.
#       Registers and applies the overrides first.
#   hotkeys.sh override <component> <action> <key> <owner component> <owner action>
#       Lets <action> have a key that another KDE action has, while the shell
#       runs: remembers it, and applies it now if the shell is running.
#   hotkeys.sh drop <component> <action>
#       Forgets the overrides of <action>; their owners get their keys back.
#
# An override does not take the key away from its owner. The owner keeps it
# in KDE's settings and is only switched off (inactive) while the shell runs,
# which lets our action hold the same key. When the shell is gone the owner
# is switched on again. So KRunner, say, works as ever whenever the shell is
# not running, also after a crash or a logout that left no time to clean up:
# inactive is not stored, KDE starts every session with the owner active.
#
# Overrides are kept in a file, one per line: action, key, owner component,
# owner action, separated by tabs.

overrides="${XDG_CONFIG_HOME:-$HOME/.config}/kde-quickshell/shortcut-overrides.tsv"
tab=$(printf '\t')

accel() {
    busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@"
}

# Per action: make it known, tell KDE its default key (flag 8), and mark it
# present (flag 2), which loads the stored key or, for an action KDE sees for
# the first time, takes the one given.
register() {
    component=$1; name=$2; shift 2
    while [ $# -ge 3 ]; do
        if [ "$3" = 0 ]; then keys=0; else keys="1 4 $3 0 0 0"; fi
        accel doRegister as 4 "$component" "$1" "$name" "$2"
        accel setShortcutKeys 'asa(ai)u' 4 "$component" "$1" "$name" "$2" $keys 8 > /dev/null
        accel setShortcutKeys 'asa(ai)u' 4 "$component" "$1" "$name" "$2" $keys 2 > /dev/null
        shift 3
    done
}

# switches the owner off and gives our action the key
apply() {
    accel setInactive as 4 "$4" "$5" "" ""
    accel setForeignShortcutKeys 'asa(ai)' 4 "$1" "$2" "" "" 1 4 "$3" 0 0 0
}

# switches an owner on again; present (flag 2) loads its stored keys, the
# empty list given here is not used
restore() {
    accel setShortcutKeys 'asa(ai)u' 4 "$1" "$2" "" "" 0 2 > /dev/null
}

apply_all() {
    [ -f "$overrides" ] || return 0
    while IFS=$tab read -r action key owner owner_action; do
        [ -n "$owner_action" ] && apply "$1" "$action" "$key" "$owner" "$owner_action"
    done < "$overrides"
}

# everything of ours inactive, every owner back on
release_all() {
    path=/component/$(printf %s "$1" | tr -c 'A-Za-z0-9' '_')
    for action in $(busctl --user call org.kde.kglobalaccel "$path" org.kde.kglobalaccel.Component shortcutNames | tr -d '"' | cut -d' ' -f3-); do
        accel setInactive as 4 "$1" "$action" "" ""
    done
    [ -f "$overrides" ] || return 0
    while IFS=$tab read -r action key owner owner_action; do
        [ -n "$owner_action" ] && restore "$owner" "$owner_action"
    done < "$overrides"
}

# KGlobalAccel does not notice a client going away, so someone has to tell it.
#   - One keeper per shell process: every reload starts this again, and the
#     later ones leave at the first lock.
#   - A restarted shell must not have its fresh registration undone by the
#     previous shell's keeper, which may only now be noticing the end. Hence
#     the second lock, held for a keeper's whole life: the new one waits for
#     the old one to finish, then registers.
keep() {
    shell=$1; shift
    dir=${XDG_RUNTIME_DIR:-/tmp}
    exec 8> "$dir/kde-quickshell-hotkeys.$shell.lock"
    flock -n 8 || exit 0
    exec 9> "$dir/kde-quickshell-hotkeys.lock"
    flock 9
    register "$@"
    apply_all "$1"
    tail --pid="$shell" -f /dev/null
    release_all "$1"
    rm -f "$dir/kde-quickshell-hotkeys.$shell.lock"
}

# Forgets the overrides of one action, except those for the key given (if
# any), and switches their owners on again. Call once the action has let go
# of the keys concerned.
forget() {
    [ -f "$overrides" ] || return 0
    kept=
    while IFS=$tab read -r action key owner owner_action; do
        [ -n "$owner_action" ] || continue
        if [ "$action" = "$1" ] && [ "$key" != "$2" ]; then
            restore "$owner" "$owner_action"
        else
            kept="$kept$action$tab$key$tab$owner$tab$owner_action
"
        fi
    done < "$overrides"
    printf '%s' "$kept" > "$overrides"
}

drop() {
    forget "$2" ""
}

override() {
    # With the shell not running there is nothing to apply: the owner stays
    # on, and the shell applies the override when it starts.
    path=/component/$(printf %s "$1" | tr -c 'A-Za-z0-9' '_')
    case $(busctl --user call org.kde.kglobalaccel "$path" org.kde.kglobalaccel.Component isActive 2> /dev/null) in
        *true*) apply "$@" ;;
    esac
    # an earlier override of this action, for another key, is over
    forget "$2" "$3"
    mkdir -p "$(dirname "$overrides")"
    line="$2$tab$3$tab$4$tab$5"
    grep -qxF "$line" "$overrides" 2> /dev/null || printf '%s\n' "$line" >> "$overrides"
}

command=$1; shift
case $command in
    register) register "$@" ;;
    keep) keep "$@" ;;
    override) override "$@" ;;
    drop) drop "$@" ;;
    *) echo "hotkeys.sh: unknown command '$command'" >&2; exit 2 ;;
esac
