import Quickshell.Services.Pipewire
import QtQuick
import qs
import qs.widgets

// Default sink volume. Click toggles mute, wheel changes volume by 5%.
Pill {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool available: Pipewire.ready && sink !== null && sink.audio !== null
    readonly property real volume: available ? sink.audio.volume : 0
    readonly property bool muted: available && sink.audio.muted

    interactive: available
    onClicked: button => {
        if (button === Qt.LeftButton)
            sink.audio.muted = !sink.audio.muted;
    }
    onScrolled: steps => sink.audio.volume = Math.max(0, Math.min(1, volume + steps * 0.05))

    // node properties are only live while the node is tracked
    PwObjectTracker {
        objects: [root.sink]
    }

    Icon {
        color: root.available ? Theme.fg : Theme.error
        source: {
            if (!root.available || root.muted || root.volume === 0)
                return "audio-volume-muted-symbolic";
            if (root.volume < 0.34)
                return "audio-volume-low-symbolic";
            if (root.volume < 0.67)
                return "audio-volume-medium-symbolic";
            return "audio-volume-high-symbolic";
        }
    }

    Label {
        color: root.available ? (root.muted ? Theme.fgDim : Theme.fg) : Theme.error
        text: root.available ? Math.round(root.volume * 100) + "%" : "no audio"
    }
}
