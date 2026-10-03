import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import qs
import qs.widgets
// not used directly: Quickshell only registers directories that something
// imports statically, and Mixer.qml (loaded by URL) needs its siblings
import qs.modules.audio

// Default sink volume. Left click opens the mixer, middle click toggles mute,
// wheel changes volume by 5%. The pill itself only needs Quickshell's PipeWire
// service; the mixer popup is a port of Plasma's applet (see audio/Mixer.qml).
Pill {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool available: Pipewire.ready && sink !== null && sink.audio !== null
    readonly property real volume: available ? sink.audio.volume : 0
    readonly property bool muted: available && sink.audio.muted

    active: popup.visible
    onClicked: button => {
        if (button === Qt.LeftButton)
            popup.visible = !popup.visible;
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

    PopupWindow {
        id: popup

        anchor.item: root
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        // clear the bar's bottom edge plus a small gap
        anchor.margins.bottom: -(Theme.barHeight - Theme.pillHeight) / 2 - Theme.spacing
        // closes on click outside
        grabFocus: true
        // must match Mixer.qml; fixed so the popup never resizes while mapped
        implicitWidth: 420
        implicitHeight: 450
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius * 2
            color: Theme.bg
            border.width: 1.5
            border.color: Theme.surface

            // loaded only while open, so level meters and the PulseAudio
            // connection don't run in the background
            Guarded {
                anchors.centerIn: parent
                name: "audio mixer"
                active: popup.visible
                source: Qt.resolvedUrl("audio/Mixer.qml")
                focus: true
                Keys.onEscapePressed: popup.visible = false
            }
        }
    }
}
