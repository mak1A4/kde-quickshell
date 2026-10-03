import QtQuick
import QtQuick.Layouts
import org.kde.plasma.private.volume as PA
import qs
import qs.widgets

// One device or application stream: name line, then mute + slider + percent.
// `pulseObject` is a PulseAudioQt device or stream from plasma-pa's models.
ColumnLayout {
    id: root

    required property var pulseObject
    required property string label
    // input devices and recording streams use microphone icons
    property bool input: false
    // devices: radio button that makes this the default device
    property bool selectable: false
    // streams: application icon in front of the name
    property string appIcon: ""
    property bool showAppIcon: false
    property real maxVolume: 1
    property int volumeStep: 5
    property bool metering: true

    readonly property real volume: pulseObject.volume / PA.PulseAudio.NormalVolume
    readonly property bool muted: pulseObject.muted
    readonly property bool isDefault: selectable && pulseObject.default

    spacing: 3

    PA.VolumeMonitor {
        id: meter

        target: root.metering ? root.pulseObject : null
    }

    RowLayout {
        spacing: Theme.spacing

        Rectangle {
            visible: root.selectable
            implicitWidth: 18
            implicitHeight: 18
            radius: 9
            color: "transparent"
            border.width: 1.5
            border.color: root.isDefault ? Theme.accent : Theme.fgDim

            Rectangle {
                anchors.centerIn: parent
                // the 4.5 px offset is exact in device pixels at scale 1.333;
                // the default snaps it to a whole logical pixel, off-centre
                anchors.alignWhenCentered: false
                visible: root.isDefault
                width: 9
                height: 9
                radius: 4.5
                color: Theme.accent
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.pulseObject.default = true
            }
        }

        Icon {
            visible: root.showAppIcon
            source: root.appIcon
            fallback: "audio-volume-high-symbolic"
            colorize: false
        }

        Label {
            Layout.fillWidth: true
            text: root.label
        }
    }

    RowLayout {
        spacing: Theme.spacing

        IconButton {
            checked: root.muted
            iconColor: root.muted ? Theme.fgDim : Theme.fg
            source: {
                const prefix = root.input ? "microphone-sensitivity" : "audio-volume";
                if (root.muted || root.volume === 0)
                    return prefix + "-muted-symbolic";
                if (root.volume < 0.34)
                    return prefix + "-low-symbolic";
                if (root.volume < 0.67)
                    return prefix + "-medium-symbolic";
                return prefix + "-high-symbolic";
            }
            onClicked: root.pulseObject.muted = !root.muted
        }

        Slider {
            Layout.fillWidth: true
            enabled: root.pulseObject.volumeWritable
            value: root.volume
            to: Math.max(root.maxVolume, root.volume)
            step: root.volumeStep / 100
            metered: true
            level: meter.available ? meter.volume : 0
            dimmed: root.muted
            onMoved: value => root.pulseObject.volume = Math.round(value * PA.PulseAudio.NormalVolume)
        }

        Label {
            Layout.preferredWidth: 42
            horizontalAlignment: Text.AlignRight
            color: root.muted ? Theme.fgDim : Theme.fg
            text: Math.round(root.volume * 100) + "%"
        }
    }
}
