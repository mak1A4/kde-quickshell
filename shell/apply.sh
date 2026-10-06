#!/bin/sh
# Gives the shell's theme to everything that is not the shell.
#
#   apply.sh <colors.json> <templates directory>
#
# colors.json is the theme as ThemeExport.qml writes it down: names and
# values. Each template is filled in with them ("{{ name }}") and put where
# its program reads it; a program is only told to read again if its file has
# changed, so this can run at every start of the shell.
#
#   kde.colors    a KDE colour scheme, made the current one: Qt and KDE
#                 applications, window borders, GTK through KDE's own
#                 settings daemon, and what the desktop says when an
#                 application asks whether it is dark or light. The icon
#                 theme follows if it comes as a -Dark and -Light pair.
#   Look.qml      the shell's lock screen
#   ghostty.conf  \
#   wezterm.lua    | in the directory of colors.json: the terminals, tmux and
#   tmux.conf      | Neovim, each of which is pointed at its file once, in
#   nvim.lua      /  its own configuration
#   mode          "dark" or "light", for anything else that wants to know
#   btop          ~/.config/btop/themes/kde-quickshell.theme: the theme btop
#                 ships of the same name where it has one, else a template
#   VS Code       the theme's own colour theme, by name, in settings.json;
#                 its extension has to be installed (tools/vscode-themes.sh)
#   browsers      Chromium and the ones made from it take the theme's colour
#                 from machine policy, written by a helper of root's that
#                 login.sh installs (browser-color.sh)
#
# APPLY_ONLY_FILES=1 writes the files and tells nobody (for trying it out).

set -e

values=$1
templates=$2
out=$(dirname "$values")
data="${XDG_DATA_HOME:-$HOME/.local/share}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/kde-quickshell"
quiet=${APPLY_ONLY_FILES:-}

value() {
    jq -r --arg name "$1" '.[$name] // ""' "$values"
}

substitutions=$(mktemp)
trap 'rm -f "$substitutions"' EXIT
jq -r 'to_entries[] | "s|{{ \(.key) }}|\(.value)|g"' "$values" > "$substitutions"

# Fills template `$1` in as file `$2`. True if that changed the file.
render() {
    mkdir -p "$(dirname "$2")"
    sed -f "$substitutions" "$templates/$1" > "$2.new"
    if cmp -s "$2.new" "$2"; then
        rm -f "$2.new"
        return 1
    fi
    mv "$2.new" "$2"
}

scheme=$(value scheme)
mode=$(value mode)

render Look.qml.tpl "$data/kde-quickshell/lock/Look.qml" || true

# ---- KDE ------------------------------------------------------------------

recoloured=
render kde.colors.tpl "$data/color-schemes/$scheme.colors" && recoloured=1
current=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)
if [ -z "$quiet" ] && { [ -n "$recoloured" ] || [ "$current" != "$scheme" ]; }; then
    # what KDE had before the shell's first theme, to go back to by hand
    case "$current" in
        Quickshell* | "") ;;
        *) [ -e "$state/colorscheme-before" ] || { mkdir -p "$state"; echo "$current" > "$state/colorscheme-before"; } ;;
    esac
    # It will not take the scheme it already has, also not after its file
    # has changed: by way of another one, then.
    if [ "$current" = "$scheme" ]; then
        [ "$mode" = dark ] && plasma-apply-colorscheme BreezeDark > /dev/null 2>&1 || plasma-apply-colorscheme BreezeLight > /dev/null 2>&1 || true
    fi
    plasma-apply-colorscheme "$scheme" > /dev/null 2>&1 || echo "apply.sh: plasma-apply-colorscheme $scheme failed" >&2
fi

# an icon theme that comes as a pair goes with the mode
if [ -z "$quiet" ]; then
    icons=$(kreadconfig6 --file kdeglobals --group Icons --key Theme)
    wanted=$icons
    case "$mode:$icons" in
        dark:*-Light) wanted="${icons%-Light}-Dark" ;;
        light:*-Dark) wanted="${icons%-Dark}-Light" ;;
    esac
    if [ "$wanted" != "$icons" ] && { [ -d "/usr/share/icons/$wanted" ] || [ -d "$data/icons/$wanted" ]; }; then
        /usr/lib/plasma-changeicons "$wanted" > /dev/null 2>&1 || true
    fi
fi

# ---- terminals and what runs in them --------------------------------------

if render ghostty.conf.tpl "$out/ghostty.conf" && [ -z "$quiet" ]; then
    # Ghostty reads its configuration again at this signal
    pkill -USR2 -x ghostty || true
fi

# WezTerm watches the file itself (wezterm.add_to_config_reload_watch_list)
render wezterm.lua.tpl "$out/wezterm.lua" || true

if render tmux.conf.tpl "$out/tmux.conf" && [ -z "$quiet" ]; then
    tmux source-file "$out/tmux.conf" 2> /dev/null || true
fi

if render nvim.lua.tpl "$out/nvim.lua" && [ -z "$quiet" ]; then
    for socket in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/nvim.*.0; do
        [ -S "$socket" ] || continue
        timeout 2 nvim --server "$socket" --remote-send "<Cmd>luafile $out/nvim.lua<CR>" > /dev/null 2>&1 || true
    done
fi

if [ "$(cat "$out/mode" 2> /dev/null)" != "$mode" ]; then
    echo "$mode" > "$out/mode"
fi

# ---- btop -----------------------------------------------------------------

if command -v btop > /dev/null; then
    own=$(value btop)
    theme="$config/btop/themes/kde-quickshell.theme"
    retinted=
    if [ -n "$own" ] && [ -r "/usr/share/btop/themes/$own.theme" ]; then
        mkdir -p "$(dirname "$theme")"
        if ! cmp -s "/usr/share/btop/themes/$own.theme" "$theme"; then
            cp "/usr/share/btop/themes/$own.theme" "$theme"
            retinted=1
        fi
    else
        render btop.theme.tpl "$theme" && retinted=1
    fi
    # btop is told once which theme is its own; it writes the rest of its
    # configuration itself
    if [ ! -e "$config/btop/btop.conf" ]; then
        echo 'color_theme = "kde-quickshell"' > "$config/btop/btop.conf"
    elif ! grep -q '^color_theme = "kde-quickshell"' "$config/btop/btop.conf"; then
        sed 's|^color_theme = .*|color_theme = "kde-quickshell"|' "$config/btop/btop.conf" > "$config/btop/btop.conf.new"
        cat "$config/btop/btop.conf.new" > "$config/btop/btop.conf"
        rm -f "$config/btop/btop.conf.new"
    fi
    if [ -n "$retinted" ] && [ -z "$quiet" ]; then
        pkill -USR2 -x btop || true
    fi
fi

# ---- VS Code --------------------------------------------------------------

# Its settings name the colour theme, and it reads them again when they
# change. All three names: with "follow the system" on, it takes the dark or
# the light one and not the first.
label=$(value vscode)
if [ -n "$label" ]; then
    for settings in "$config/Code/User/settings.json" "$config/Code - OSS/User/settings.json" "$config/VSCodium/User/settings.json"; do
        [ -f "$settings" ] || continue
        new=$(mktemp)
        cp "$settings" "$new"
        for key in workbench.colorTheme workbench.preferredDarkColorTheme workbench.preferredLightColorTheme; do
            if grep -q "\"$key\"" "$new"; then
                sed -i -E "s|(\"$key\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"|\\1\"$label\"|" "$new"
            else
                sed -i "0,/{/s|{|{\n    \"$key\": \"$label\",|" "$new"
            fi
        done
        # written into the file, which may be a link into somewhere else
        cmp -s "$new" "$settings" || cat "$new" > "$settings"
        rm -f "$new"
    done
fi

# ---- browsers -------------------------------------------------------------

# The colour, or "off": then the policy is taken away and the browsers are
# left to their own setting (Themes.browsers).
helper=/usr/local/libexec/kde-quickshell-browser-color
policy=/etc/chromium/policies/managed/kde-quickshell.json
colour=$(value browserColour)
stale=
if [ "$colour" = off ]; then
    [ -e "$policy" ] && stale=1
elif [ "$(cat "$policy" 2> /dev/null)" != "{\"BrowserThemeColor\": \"#$colour\", \"BrowserColorScheme\": \"device\"}" ]; then
    stale=1
fi
if [ -z "$quiet" ] && [ -x "$helper" ] && [ -n "$stale" ]; then
    if pkexec "$helper" "$colour"; then
        # a running browser reads its policy again when started with this
        for browser in chromium:chromium helium:helium-browser chrome:google-chrome-stable brave:brave msedge:microsoft-edge-stable; do
            if pgrep -x "${browser%%:*}" > /dev/null && command -v "${browser#*:}" > /dev/null; then
                "${browser#*:}" --refresh-platform-policy --no-startup-window > /dev/null 2>&1 &
            fi
        done
        wait
    else
        echo "apply.sh: the browsers' policy could not be written" >&2
    fi
fi
