import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// Play/pause for the current MPRIS player; hidden when there is none.
// Left click toggles, right click is next, middle click is previous.
// Browsers often show up twice (native + plasma-browser-integration); only
// one player is used, so that's harmless.
BarButton {
    id: root

    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? players[0] ?? null

    visible: player !== null
    hintTitle: player?.trackTitle || player?.identity || ""
    hintLines: [player?.trackArtist, player?.trackAlbum, player?.trackTitle ? player?.identity : ""].filter(line => line)
    onClicked: button => {
        if (button === Qt.LeftButton && player.canTogglePlaying)
            player.togglePlaying();
        else if (button === Qt.RightButton && player.canGoNext)
            player.next();
        else if (button === Qt.MiddleButton && player.canGoPrevious)
            player.previous();
    }

    Icon {
        Layout.alignment: Qt.AlignHCenter
        source: root.player?.isPlaying ? "media-playback-playing-symbolic" : "media-playback-paused-symbolic"
    }
}
