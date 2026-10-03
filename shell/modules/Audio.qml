import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets
// not used directly: Quickshell only registers directories that something
// imports statically, and Mixer.qml (loaded by URL) needs its siblings
import qs.modules.audio

// Default sink volume. Left click opens the mixer, middle click toggles mute,
// wheel changes volume by 5%. The button itself only needs Quickshell's
// PipeWire service; the mixer is a port of Plasma's applet (audio/Mixer.qml).
BarButton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool available: Pipewire.ready && sink !== null && sink.audio !== null
    readonly property real volume: available ? sink.audio.volume : 0
    readonly property bool muted: available && sink.audio.muted

    active: Popouts.current === "audio"
    hintTitle: available ? (sink.description || sink.name) : "No audio output"
    hintLines: available ? [muted ? "Muted" : `Volume ${Math.round(volume * 100)}%`] : []
    onClicked: button => {
        if (button === Qt.LeftButton)
            Popouts.toggle("audio", root, mixer);
        else if (button === Qt.MiddleButton && available)
            sink.audio.muted = !sink.audio.muted;
    }
    onScrolled: steps => {
        if (!available)
            return;
        // the wheel never pushes past 100%, but doesn't pull a raised volume down to it either
        sink.audio.volume = Math.max(0, Math.min(Math.max(1, volume), volume + steps * 0.05));
    }

    // node properties are only live while the node is tracked
    PwObjectTracker {
        objects: [root.sink]
    }

    // created only while the popout is open, so level meters and the
    // PulseAudio connection don't run in the background
    Component {
        id: mixer

        Guarded {
            name: "audio mixer"
            source: Qt.resolvedUrl("audio/Mixer.qml")
        }
    }

    Icon {
        Layout.alignment: Qt.AlignHCenter
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
}
