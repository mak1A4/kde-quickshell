import QtQuick
import QtQuick.Layouts
import org.kde.plasma.private.battery as Battery
import qs
import qs.widgets

// Port of Plasma's Power & Battery applet. The backend objects are owned by
// modules/Power.qml and stay alive while the popup is closed.
Item {
    id: root

    required property var profiles // PowerProfilesControl
    required property var inhibition // InhibitionControl
    required property var batteries // BatteryControlModel

    readonly property var profileNames: ({
            "power-saver": "Power Save",
            "balanced": "Balanced",
            "performance": "Performance"
        })
    readonly property var deviceIcons: ({
            "Mouse": "input-mouse-symbolic",
            "Keyboard": "input-keyboard-symbolic",
            "Headset": "audio-headset-symbolic",
            "Headphones": "audio-headphones-symbolic",
            "Phone": "phone-symbolic",
            "Tablet": "input-tablet-symbolic",
            "Touchpad": "input-touchpad-symbolic"
        })

    implicitWidth: Theme.popupWidth
    implicitHeight: 390

    function blockedThings(behaviors) {
        const sleep = behaviors.includes("sleep");
        const idle = behaviors.includes("idle");
        if (sleep && idle)
            return "sleep and screen locking";
        return sleep ? "sleep" : "screen locking";
    }

    component Hint: RowLayout {
        property alias text: hintText.text
        property color tint: Theme.fgDim

        spacing: Theme.spacing

        Icon {
            Layout.alignment: Qt.AlignTop
            source: "data-warning"
            color: parent.tint
        }

        Label {
            id: hintText

            Layout.fillWidth: true
            color: parent.tint
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Theme.padding
        }
        spacing: Theme.spacing

        PopupHeader {
            title: "Power & Battery"
            settingsModule: "kcm_powerdevilprofilesconfig"
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1.5
            color: Theme.surface
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
                spacing: Theme.spacing * 2

                // power profile
                ColumnLayout {
                    visible: root.profiles.isPowerProfileDaemonInstalled && root.profiles.profiles.length > 0
                    spacing: 3

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            text: "Power Profile"
                        }

                        Label {
                            color: Theme.fgDim
                            text: root.profileNames[root.profiles.activeProfile] ?? root.profiles.activeProfile
                        }
                    }

                    Slider {
                        Layout.fillWidth: true
                        discrete: true
                        step: 1
                        to: Math.max(1, root.profiles.profiles.length - 1)
                        value: Math.max(0, root.profiles.profiles.indexOf(root.profiles.activeProfile))
                        onMoved: value => root.profiles.setProfile(root.profiles.profiles[value])
                    }

                    RowLayout {
                        Icon {
                            source: "battery-profile-powersave-symbolic"
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Icon {
                            source: "battery-profile-performance-symbolic"
                        }
                    }

                    Hint {
                        visible: root.profiles.profileError !== ""
                        tint: Theme.error
                        text: root.profiles.profileError
                    }

                    Hint {
                        visible: root.profiles.inhibitionReason !== ""
                        text: "Performance mode is unavailable: " + root.profiles.inhibitionReason
                    }

                    Hint {
                        visible: root.profiles.degradationReason !== ""
                        tint: Theme.warning
                        text: "Performance may be reduced: " + root.profiles.degradationReason
                    }
                }

                Hint {
                    visible: !root.profiles.isPowerProfileDaemonInstalled
                    text: "Power profiles unavailable (power-profiles-daemon is not running)"
                }

                // batteries, including peripherals
                Repeater {
                    model: root.batteries

                    RowLayout {
                        id: battery

                        required property var model
                        readonly property bool charging: model.ChargeState === Battery.BatteryControlModel.Charging

                        // PluggedIn means the battery itself is present
                        visible: model.PluggedIn
                        spacing: Theme.padding

                        Icon {
                            source: root.deviceIcons[battery.model.Type] ?? "battery-full-symbolic"
                        }

                        ColumnLayout {
                            spacing: 3

                            RowLayout {
                                spacing: Theme.spacing

                                Label {
                                    Layout.fillWidth: true
                                    text: battery.model.PrettyName
                                }

                                Label {
                                    color: Theme.fgDim
                                    text: {
                                        switch (battery.model.ChargeState) {
                                        case Battery.BatteryControlModel.Charging:
                                            return "Charging";
                                        case Battery.BatteryControlModel.Discharging:
                                            return "Discharging";
                                        case Battery.BatteryControlModel.FullyCharged:
                                            return "Fully Charged";
                                        default:
                                            return "";
                                        }
                                    }
                                }

                                Label {
                                    text: battery.model.Percent + "%"
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: Theme.surface

                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(100, battery.model.Percent)) / 100
                                    height: parent.height
                                    radius: 3
                                    color: battery.model.Percent <= 15 && !battery.charging ? Theme.error : Theme.accent
                                }
                            }
                        }
                    }
                }

                // sleep and screen lock blocking
                ColumnLayout {
                    spacing: Theme.spacing

                    RowLayout {
                        spacing: Theme.spacing

                        Toggle {
                            checked: root.inhibition.isManuallyInhibited
                            onToggled: {
                                if (root.inhibition.isManuallyInhibited)
                                    root.inhibition.uninhibit();
                                else
                                    root.inhibition.inhibit("Manually blocked from the bar");
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: "Manually Block Sleep and Screen Locking"
                        }
                    }

                    Hint {
                        visible: root.inhibition.isManuallyInhibitedError
                        tint: Theme.error
                        text: "Failed to block sleep and screen locking"
                    }

                    Hint {
                        visible: root.inhibition.isManuallyInhibited
                        text: "This will result in higher energy consumption."
                    }

                    Repeater {
                        model: root.inhibition.requestedInhibitions

                        RowLayout {
                            id: request

                            required property var modelData

                            visible: modelData.active || !modelData.allowed
                            spacing: Theme.spacing

                            Icon {
                                Layout.alignment: Qt.AlignTop
                                source: request.modelData.icon
                                fallback: "applications-other"
                                colorize: false
                            }

                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                                text: {
                                    const r = request.modelData;
                                    const what = root.blockedThings(r.behaviors);
                                    const reason = r.reason ? ` (${r.reason})` : "";
                                    if (!r.allowed)
                                        return `${r.prettyName} has been prevented from blocking ${what}.${reason}`;
                                    const also = root.inhibition.isManuallyInhibited ? "also" : "currently";
                                    return `${r.prettyName} is ${also} blocking ${what}.${reason}`;
                                }
                            }

                            Button {
                                Layout.alignment: Qt.AlignTop
                                text: request.modelData.allowed ? "Unblock" : "Block Again"
                                onClicked: root.inhibition.setInhibitionAllowed(request.modelData.appName, request.modelData.reason, !request.modelData.allowed)
                            }
                        }
                    }
                }
            }
        }
    }
}
