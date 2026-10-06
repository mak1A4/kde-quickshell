#!/bin/sh
# Looks at everything the shell needs outside itself, at each of its starts,
# puts in place what is its own to put there, and says what it found.
#
#   setup.sh <shell directory> [news|all]
#
# One line for each thing looked at, in four parts separated by tabs: how it
# is, a short name for it, what it is, and what there is to say.
#   ok       as it should be
#   fixed    was missing or stale, and has been put right just now
#   note     as it is for a reason, or not the shell's to change; for knowing
#   problem  wrong, and not something this can put right
# Setup.qml runs it and keeps the result. With `news` a notification says what
# was put right and what is wrong, a wrong thing once and not at every start;
# with `all` one says how everything stands.
#
# What needs root is not done here: the login screen has login.sh, which
# asks for the password (LoginScreen.qml); this only says how that stands.
#
# Parts that are a matter of taste can be switched off in
# ~/.config/kde-quickshell/setup.json: { "lockscreen": false } leaves KDE's
# own lock screen, "autostart": false does not put the shell among the
# programs started at login, "vscode": false installs no extensions.

# as the shell was started: the name `qs ipc -p` has to be given too
given=${1%/}
shell=$(readlink -f "$given")
root=$(dirname "$shell")
telling=${2:-}
config="${XDG_CONFIG_HOME:-$HOME/.config}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/kde-quickshell"
settings="$config/kde-quickshell/setup.json"
mkdir -p "$state"
report=$(mktemp)
trap 'rm -f "$report"' EXIT

# paths as one writes them
short() {
    printf '%s' "$1" | sed "s|$HOME/|~/|g"
}

say() {
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(short "$4")" | tee -a "$report"
}

have() {
    command -v "$1" > /dev/null 2>&1
}

# on unless setup.json says false
wanted() {
    have jq || return 0
    [ "$(jq -r --arg part "$1" 'if type == "object" and has($part) then .[$part] else true end' "$settings" 2> /dev/null)" != false ]
}

# ---- what has to be installed ---------------------------------------------

missing=
for tool in jq busctl flock kpackagetool6 kreadconfig6 kwriteconfig6 plasma-apply-colorscheme systemd-run pkexec ffmpeg notify-send; do
    have "$tool" || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    say problem programs "Programs the shell uses" "not installed:$missing"
else
    say ok programs "Programs the shell uses" "all there"
fi

# ---- the right to see the windows -----------------------------------------

# KWin gives the window list only to a program whose desktop entry asks for it
entry="$data/applications/kde-quickshell.desktop"
if cmp -s "$root/packaging/kde-quickshell.desktop" "$entry"; then
    say ok entry "Desktop entry (for the window list)" "in place"
elif mkdir -p "$(dirname "$entry")" && cp "$root/packaging/kde-quickshell.desktop" "$entry"; then
    # KDE's list of the installed programs, which is where KWin looks
    kbuildsycoca6 > /dev/null 2>&1
    say fixed entry "Desktop entry (for the window list)" "installed; the task list has its windows from the shell's next start"
else
    say problem entry "Desktop entry (for the window list)" "could not be written to $entry"
fi

# ---- started at login ------------------------------------------------------

# Made once. If it is gone after that, someone took it away (System Settings,
# Autostart), and it is not put back.
autostart="$config/autostart/kde-quickshell-shell.desktop"
if ! wanted autostart; then
    say note autostart "Started at login" "switched off in setup.json"
elif [ -e "$autostart" ]; then
    started=$(sed -n 's/^Exec=.* -p //p' "$autostart" | head -1)
    if [ "$(readlink -f "$started")" = "$shell" ]; then
        if grep -qs '^Hidden=true' "$autostart"; then
            say note autostart "Started at login" "switched off in System Settings"
        else
            say ok autostart "Started at login" "yes"
        fi
    else
        sed -i "s|^Exec=.*|Exec=$(command -v qs) -n -p $given|" "$autostart"
        say fixed autostart "Started at login" "started something else (${started:-nothing}); now this shell, $given"
    fi
elif [ -e "$state/autostart-made" ]; then
    say note autostart "Started at login" "no: the entry was removed, and is not put back (delete $state/autostart-made to have it again)"
else
    mkdir -p "$(dirname "$autostart")"
    cat > "$autostart" << EOF
[Desktop Entry]
Type=Application
Name=Quickshell shell
Comment=Frame, bar, dock, launcher and command palette (kde-quickshell)
Icon=preferences-desktop-theme-global
# -n: a start while it already runs does nothing. The path is the one
# \`qs ipc -p\` is called with; it must be exactly this.
Exec=$(command -v qs) -n -p $given
OnlyShowIn=KDE;
X-KDE-autostart-phase=2
EOF
    : > "$state/autostart-made"
    say fixed autostart "Started at login" "entry made in $autostart"
fi
[ -e "$autostart" ] && : > "$state/autostart-made"

# ---- what Plasma loads of ours ---------------------------------------------

# Plasma refuses a package whose files are links to somewhere else (as a
# dotfiles manager makes them): the wallpaper was black for that once.
package() {
    id=$1 title=$2 dir=$3 source=$4
    if [ ! -d "$dir" ]; then
        say note "$id" "$title" "not installed yet; the shell installs it when it is first used"
    elif [ -n "$(find "$dir" -type l 2> /dev/null | head -1)" ] || [ "$(readlink -f "$dir")" != "$dir" ]; then
        say problem "$id" "$title" "its files in $dir are links; Plasma does not load those. Remove the directory (and what it links to), the shell installs it again"
    elif diff -rq "$source" "$dir" > /dev/null 2>&1; then
        say ok "$id" "$title" "installed"
    else
        say note "$id" "$title" "differs from the shell's; it is brought up to date when next used"
    fi
}
package wallpaper "Wallpaper for the theme's background" "$data/plasma/wallpapers/io.github.mak1a4.kde-quickshell.background" "$root/plasma/background"
package handover "Notification helper in Plasma" "$data/plasma/plasmoids/io.github.mak1a4.kde-quickshell.handover" "$root/plasma/handover"

# ---- lock screen -----------------------------------------------------------

# KDE's locker takes its interface from the "shell package" Plasma runs with,
# which may be named in the environment: for KWin alone, which starts the
# locker, in a drop-in of the user's systemd. (See "Lock screen" in
# docs/decisions.md.)
lock=io.github.mak1a4.kde-quickshell.lock
lockdir="$data/plasma/shells/$lock"
dropin="$config/systemd/user/plasma-kwin_wayland.service.d/kde-quickshell-lock.conf"
if ! wanted lockscreen; then
    if [ -e "$dropin" ] || [ -d "$lockdir" ]; then
        rm -rf "$lockdir"
        rm -f "$dropin"
        rmdir "$(dirname "$dropin")" 2> /dev/null
        systemctl --user daemon-reload 2> /dev/null
        say fixed lockscreen "Lock screen" "switched off in setup.json: removed, KDE's own from the next login"
    else
        say note lockscreen "Lock screen" "switched off in setup.json: KDE's own"
    fi
else
    did=
    if ! diff -rq -x frame.frag.qsb "$root/plasma/lockscreen" "$lockdir" > /dev/null 2>&1 ||
        ! cmp -s "$shell/shaders/frame.frag.qsb" "$lockdir/contents/lockscreen/frame.frag.qsb" ||
        [ -n "$(find "$lockdir" -type l 2> /dev/null | head -1)" ]; then
        rm -rf "$lockdir"
        mkdir -p "$(dirname "$lockdir")"
        cp -r "$root/plasma/lockscreen" "$lockdir" && cp "$shell/shaders/frame.frag.qsb" "$lockdir/contents/lockscreen/" && did="interface installed"
    fi
    if ! grep -qsF "PLASMA_DEFAULT_SHELL=$lock" "$dropin"; then
        mkdir -p "$(dirname "$dropin")"
        printf '# the lock screen of the Quickshell shell (kde-quickshell, shell/setup.sh)\n[Service]\nEnvironment=PLASMA_DEFAULT_SHELL=%s\n' "$lock" > "$dropin"
        systemctl --user daemon-reload 2> /dev/null
        did="${did:+$did, }named for KWin"
    fi
    # KWin has its environment from its start: a drop-in written after that
    # counts from the next login
    started=$(systemctl --user show plasma-kwin_wayland.service -p ActiveEnterTimestamp --value 2> /dev/null)
    since=$(date -d "$started" +%s 2> /dev/null || echo 0)
    written=$(stat -c %Y "$dropin" 2> /dev/null || echo 0)
    if [ -n "$(kreadconfig6 --file plasmashellrc --group Shell --key ShellPackage 2> /dev/null)" ]; then
        say problem lockscreen "Lock screen" "plasmashellrc names a shell package, and KDE's locker takes its interface from that one"
    elif [ "$written" -gt "$since" ]; then
        how=note
        [ -n "$did" ] && how=fixed
        say "$how" lockscreen "Lock screen" "${did:+$did; }the shell's from the next login"
    elif [ -n "$did" ]; then
        say fixed lockscreen "Lock screen" "$did; the next lock shows it"
    else
        say ok lockscreen "Lock screen" "the shell's"
    fi
fi

# ---- login screen ----------------------------------------------------------

# Root's part: the login screen, and the helper that colours the browsers.
# Where there is no Plasma Login Manager, only the helper.
if [ "$("$shell/login.sh" greeter 2> /dev/null)" = yes ]; then
    title="Login screen"
    good="has the theme's background and your display settings"
    behind="behind your session"
else
    title="Browser colour helper"
    good="installed (no Plasma Login Manager here: the login screen is left alone)"
    behind="not installed"
fi
case "$("$shell/login.sh" check "$config" 2> /dev/null)" in
    ok) say ok login "$title" "$good" ;;
    declined) say note login "$title" "$behind; the question for the password was closed (\"Update the login screen\" among the > actions asks again)" ;;
    needed*) say note login "$title" "$behind; the shell asks for the password" ;;
    *) say problem login "$title" "login.sh gave no answer" ;;
esac

# ---- what is put away of Plasma --------------------------------------------

# Both are the work of keepers, small processes the shell starts and which
# outlive it to put things back (PlasmaPanels.qml, Hotkeys.qml).
running=$(ps -eo args)
keeper() {
    if printf '%s\n' "$running" | grep -qF "/$2 keep"; then
        say ok "$1" "$3" "$4"
    else
        say problem "$1" "$3" "its keeper ($2) is not running; restart the shell"
    fi
}
keeper plasma panels.sh "Plasma's panels and desktop icons" "put away while the shell runs"
keeper hotkeys hotkeys.sh "Global shortcuts" "the shell's while it runs"

# ---- the theme outside the shell -------------------------------------------

values="$state/theme/colors.json"
if [ ! -s "$values" ]; then
    say note theme "Theme for KDE and applications" "not written yet"
else
    scheme=$(jq -r '.scheme // ""' "$values" 2> /dev/null)
    current=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2> /dev/null)
    if [ "$scheme" = "$current" ]; then
        say ok theme "KDE's colours" "the theme's ($scheme)"
    else
        say note theme "KDE's colours" "$current, not the theme's ($scheme): changed elsewhere, or about to be applied"
    fi
fi

# A program reads the theme's colours from its file only if its own
# configuration names that file. That is the user's to write: said, not done.
# (-R: such a configuration is often a link into a dotfiles directory.)
connected() {
    id=$1 title=$2 file=$3 how=$4
    shift 4
    have "$id" || return 0
    if grep -RqsF "kde-quickshell/theme/$file" "$@" 2> /dev/null; then
        say ok "$id" "$title" "takes the theme's colours"
    else
        say note "$id" "$title" "not connected to the theme: $how"
    fi
}
connected ghostty "Ghostty" ghostty.conf "add to its config: config-file = ?\"~/.local/state/kde-quickshell/theme/ghostty.conf\"" "$config/ghostty"
connected wezterm "WezTerm" wezterm.lua "have wezterm.lua take config.colors from dofile(~/.local/state/kde-quickshell/theme/wezterm.lua)" "$config/wezterm"
connected tmux "tmux" tmux.conf "add to tmux.conf: source-file ~/.local/state/kde-quickshell/theme/tmux.conf" "$config/tmux" "$HOME/.tmux.conf"
connected nvim "Neovim" nvim.lua "have its config run ~/.local/state/kde-quickshell/theme/nvim.lua (dofile) after the plugins" "$config/nvim"

# VS Code has the themes' colour themes from extensions. Looked at once, and
# again when the list here changes: asking VS Code takes a second or two.
extensions="catppuccin.catppuccin-vsc enkia.tokyo-night jdinhlife.gruvbox arcticicestudio.nord-visual-studio-code sainnhe.everforest qufiwefefwoyn.kanagawa mvllow.rose-pine dracula-theme.theme-dracula"
if have code; then
    if ! wanted vscode; then
        say note code "VS Code" "extensions for the themes are switched off in setup.json"
    elif [ "$(cat "$state/vscode-extensions" 2> /dev/null)" = "$extensions" ]; then
        say ok code "VS Code" "has the themes' extensions"
    else
        there=$(code --list-extensions 2> /dev/null | tr '[:upper:]' '[:lower:]')
        added= failed=
        for extension in $extensions; do
            printf '%s\n' "$there" | grep -qx "$extension" && continue
            if code --install-extension "$extension" > /dev/null 2>&1; then
                added="$added $extension"
            else
                failed="$failed $extension"
            fi
        done
        if [ -n "$failed" ]; then
            say problem code "VS Code" "could not install:$failed"
        else
            echo "$extensions" > "$state/vscode-extensions"
            if [ -n "$added" ]; then
                say fixed code "VS Code" "installed the themes' extensions:$added"
            else
                say ok code "VS Code" "has the themes' extensions"
            fi
        fi
    fi
fi

# ---- backgrounds -----------------------------------------------------------

count=$(find "$config/kde-quickshell/themes/backgrounds" -mindepth 2 -maxdepth 2 -type f 2> /dev/null | wc -l)
if [ "$count" -gt 0 ]; then
    say ok backgrounds "Backgrounds" "$count, in $config/kde-quickshell/themes/backgrounds"
else
    say note backgrounds "Backgrounds" "none: put pictures or videos in $config/kde-quickshell/themes/backgrounds/<theme>/ (tools/qylock.sh fetches a set)"
fi

# ---- saying it -------------------------------------------------------------

[ -n "$telling" ] && have notify-send || exit 0

lines() {
    awk -F '\t' -v state="$1" '$1 == state { print $3 ": " $4 }' "$report"
}
tell() {
    notify-send -a "Quickshell shell" -i "$1" "$2" "$3"
}

fixed=$(lines fixed)
problems=$(lines problem)
notes=$(lines note)
told="$state/setup-told"
if [ "$telling" = all ]; then
    if [ -z "$fixed$problems$notes" ]; then
        tell emblem-ok-symbolic "Shell setup" "Everything is in place ($(wc -l < "$report") things looked at)."
    else
        icon=dialog-information-symbolic
        [ -n "$problems" ] && icon=dialog-warning-symbolic
        tell "$icon" "Shell setup" "$(printf '%s\n' "$problems" "$fixed" "$notes" | sed '/^$/d')"
    fi
else
    [ -n "$fixed" ] && tell emblem-ok-symbolic "Shell setup: put right" "$fixed"
    # a wrong thing is said when it is new, not at every start
    if [ -n "$problems" ] && [ "$problems" != "$(cat "$told" 2> /dev/null)" ]; then
        tell dialog-warning-symbolic "Shell setup: needs a look" "$problems"
    fi
fi
if [ -n "$problems" ]; then
    printf '%s\n' "$problems" > "$told"
else
    rm -f "$told"
fi
