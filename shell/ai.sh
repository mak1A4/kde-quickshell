#!/bin/sh
# T3 Code helpers for the AI panel (Ai.qml).
#
#   ai.sh pair-token
#       Mints a one-time pairing token with T3's own CLI and prints only the
#       token. Ai.qml exchanges it (as client "kde quickshell") for the
#       long-lived access token it stores; the one-time token is consumed by
#       that exchange, so each run of this creates no lasting client of its
#       own beyond the one named client the shell keeps reusing.
#
#   ai.sh notify <shell's pid> <thread> <normal|critical> <title> <text>
#       A notification about a thread, as T3 Code's. It stays until it is
#       closed; a click on it opens the panel on the thread. The shell has no
#       notifications of its own to send: it is the service that shows them.
#
# The CLI is the desktop app's bundled one (~/.local/share/t3/bin/t3, a
# wrapper written by T3 Code itself), or `t3` from PATH if there is one.

case "${1:-}" in
pair-token)
    t3=""
    for candidate in "${T3CODE_HOME:-$HOME/.local/share/t3}/bin/t3" "$HOME/.local/share/t3/bin/t3"; do
        if [ -x "$candidate" ]; then
            t3=$candidate
            break
        fi
    done
    if [ -z "$t3" ] && command -v t3 > /dev/null 2>&1; then
        t3=t3
    fi
    if [ -z "$t3" ]; then
        echo "ai.sh: no t3 CLI found" >&2
        exit 127
    fi
    # the CLI also prints a QR code and a pairing URL; only the token counts
    "$t3" pair 2> /dev/null | sed -n 's/^Token: //p' | head -n 1
    ;;
notify)
    answer=$(notify-send --app-name "T3 Code" --icon t3code --hint string:desktop-entry:t3code \
        --urgency "$4" --action default=Open --wait -- "$5" "$6") || exit 0
    if [ "$answer" = default ]; then
        qs ipc --pid "$2" call ai view "$3"
    fi
    ;;
*)
    echo "usage: ai.sh pair-token | notify <pid> <thread> <urgency> <title> <text>" >&2
    exit 2
    ;;
esac
