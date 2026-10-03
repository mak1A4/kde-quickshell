import QtQuick
import QtQuick.Layouts
import org.kde.plasma.private.volume as PA
import qs
import qs.widgets
import qs.modules.audio

// Port of Plasma's Audio Volume applet. Uses plasma-pa's own models rather
// than Quickshell's PipeWire service because only they know port
// availability, which is how Plasma hides unplugged outputs and inputs.
Item {
    id: root

    property int tab: 0
    readonly property real maxVolume: config.raiseMaximumVolume ? PA.PulseAudio.MaximalVolume / PA.PulseAudio.NormalVolume : 1

    // Fixed size, like Plasma's applet: resizing a mapped popup at fractional
    // scale leaves a stale, stretched frame (Quickshell 0.3.1 / Qt 6.11).
    implicitWidth: Theme.popupWidth
    implicitHeight: 450

    component SectionHeader: RowLayout {
        property alias text: title.text

        Layout.topMargin: Theme.spacing
        spacing: Theme.spacing

        Label {
            id: title

            color: Theme.fgDim
            font.bold: true
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1.5
            color: Theme.surface
        }
    }

    component Hint: Label {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing
        color: Theme.fgDim
        horizontalAlignment: Text.AlignHCenter
    }

    // same settings file as Plasma's applet, so the two stay in sync
    PA.GlobalConfig {
        id: config
    }

    PA.PulseObjectFilterModel {
        id: sinks

        filterOutInactiveDevices: true
        filterVirtualDevices: true
        sourceModel: PA.SinkModel {}
    }

    PA.PulseObjectFilterModel {
        id: sources

        filterOutInactiveDevices: true
        filterVirtualDevices: true
        sourceModel: PA.SourceModel {}
    }

    PA.PulseObjectFilterModel {
        id: playbackStreams

        filters: [{ role: "VirtualStream", value: false }]
        sourceModel: PA.SinkInputModel {}
    }

    PA.PulseObjectFilterModel {
        id: recordingStreams

        filters: [{ role: "VirtualStream", value: false }]
        sourceModel: PA.SourceOutputModel {}
    }

    ColumnLayout {
        id: column

        anchors {
            fill: parent
            margins: Theme.padding
        }
        spacing: Theme.spacing

        PopupHeader {
            title: "Audio Volume"
            settingsModule: "kcm_pulseaudio"
        }

        RowLayout {
            spacing: 0

            Repeater {
                model: ["Devices", "Applications"]

                Item {
                    id: tabButton

                    required property string modelData
                    required property int index
                    readonly property bool current: root.tab === index

                    Layout.fillWidth: true
                    implicitHeight: 30

                    Label {
                        anchors.centerIn: parent
                        color: tabButton.current ? Theme.fg : Theme.fgDim
                        text: tabButton.modelData
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 3
                        color: tabButton.current ? Theme.accent : Theme.surface
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.tab = tabButton.index
                    }
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body

                width: parent.width
                spacing: 0

                ColumnLayout {
                    visible: root.tab === 0
                    spacing: Theme.spacing

                    SectionHeader {
                        text: "Output Devices"
                    }

                    Hint {
                        visible: outputs.count === 0
                        text: "No output devices"
                    }

                    Repeater {
                        id: outputs

                        model: sinks

                        VolumeRow {
                            required property var model

                            pulseObject: model.PulseObject
                            // Plasma names a lone device by its port ("Microphone")
                            label: outputs.count === 1 && port ? port.description : pulseObject.description
                            selectable: outputs.count > 1
                            maxVolume: root.maxVolume
                            volumeStep: config.volumeStep

                            readonly property var port: pulseObject.ports[pulseObject.activePortIndex] ?? null
                        }
                    }

                    SectionHeader {
                        text: "Input Devices"
                    }

                    Hint {
                        visible: inputs.count === 0
                        text: "No input devices"
                    }

                    Repeater {
                        id: inputs

                        model: sources

                        VolumeRow {
                            required property var model

                            pulseObject: model.PulseObject
                            label: inputs.count === 1 && port ? port.description : pulseObject.description
                            input: true
                            selectable: inputs.count > 1
                            maxVolume: root.maxVolume
                            volumeStep: config.volumeStep

                            readonly property var port: pulseObject.ports[pulseObject.activePortIndex] ?? null
                        }
                    }
                }

                ColumnLayout {
                    visible: root.tab === 1
                    spacing: Theme.spacing

                    Hint {
                        visible: playback.count === 0 && recording.count === 0
                        Layout.bottomMargin: Theme.spacing
                        text: "No applications playing or recording audio"
                    }

                    SectionHeader {
                        visible: playback.count > 0
                        text: "Playback"
                    }

                    Repeater {
                        id: playback

                        model: playbackStreams

                        VolumeRow {
                            required property var model

                            pulseObject: model.PulseObject
                            label: pulseObject.client?.name || pulseObject.name
                            showAppIcon: true
                            appIcon: pulseObject.iconName || pulseObject.properties["application.icon_name"] || ""
                            maxVolume: root.maxVolume
                            volumeStep: config.volumeStep
                        }
                    }

                    SectionHeader {
                        visible: recording.count > 0
                        text: "Recording"
                    }

                    Repeater {
                        id: recording

                        model: recordingStreams

                        VolumeRow {
                            required property var model

                            pulseObject: model.PulseObject
                            label: pulseObject.client?.name || pulseObject.name
                            input: true
                            showAppIcon: true
                            appIcon: pulseObject.iconName || pulseObject.properties["application.icon_name"] || ""
                            maxVolume: root.maxVolume
                            volumeStep: config.volumeStep
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1.5
            color: Theme.surface
        }

        RowLayout {
            spacing: Theme.spacing

            Toggle {
                checked: config.raiseMaximumVolume
                onToggled: {
                    config.raiseMaximumVolume = !config.raiseMaximumVolume;
                    config.save();
                }
            }

            Label {
                Layout.fillWidth: true
                text: "Raise maximum volume"
            }
        }
    }
}
