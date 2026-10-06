#!/bin/sh
# Installs the VS Code extensions that hold the colour themes of the shell's
# themes (shell/themes/*.json, "apps": { "vscode": ... }), so that VS Code has
# each when the shell names it (shell/apply.sh). Solarized and the default
# themes, for Breeze, come with VS Code. For `code` the shell does this itself
# at its start (shell/setup.sh, which has the same list); this is for another
# build of VS Code.
#
#   tools/vscode-themes.sh [code|codium|...]

set -e

code=${1:-code}
command -v "$code" > /dev/null || { echo "no $code" >&2; exit 1; }

have=$("$code" --list-extensions | tr '[:upper:]' '[:lower:]')
for extension in catppuccin.catppuccin-vsc enkia.tokyo-night jdinhlife.gruvbox arcticicestudio.nord-visual-studio-code \
    sainnhe.everforest qufiwefefwoyn.kanagawa mvllow.rose-pine dracula-theme.theme-dracula; do
    if echo "$have" | grep -qx "$extension"; then
        echo "$extension: there"
    else
        "$code" --install-extension "$extension" > /dev/null && echo "$extension: installed" || echo "$extension: FAILED"
    fi
done
