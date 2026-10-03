import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// Hidden when no MPRIS player exists. Browsers often show up twice (native +
// plasma-browser-integration); only one player is shown, so that's harmless.
Pill {
    id: root

    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? players[0] ?? null

    visible: player !== null
    onClicked: button => {
        if (button === Qt.LeftButton && player.canTogglePlaying)
            player.togglePlaying();
        else if (button === Qt.RightButton && player.canGoNext)
            player.next();
        else if (button === Qt.MiddleButton && player.canGoPrevious)
            player.previous();
    }

    Icon {
        source: root.player?.isPlaying ? "media-playback-playing-symbolic" : "media-playback-paused-symbolic"
    }

    Label {
        Layout.maximumWidth: Theme.maxTextWidth
        text: {
            const title = root.player?.trackTitle || root.player?.identity || "";
            const artist = root.player?.trackArtist ?? "";
            return artist ? `${title} · ${artist}` : title;
        }
    }
}
