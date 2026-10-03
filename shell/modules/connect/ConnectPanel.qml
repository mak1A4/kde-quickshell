import Quickshell
import QtQuick
import QtQuick.Layouts
import org.kde.kdeconnect as KDEConnect
import qs
import qs.widgets

// Port of Plasma's KDE Connect applet: one card per connected device with
// mobile signal, battery and the device actions. An action is offered only
// when the device has that plugin loaded.
//
// All device state (battery, signal, which plugins are loaded) comes in ready
// from modules/Connect.qml. Asking for it here would mean the answers arrive
// after the panel has opened, and it would grow and shift on screen.
Item {
    id: root

    // list of the per-device state objects kept by modules/Connect.qml
    required property var devices

    implicitWidth: Theme.popupWidth
    implicitHeight: column.implicitHeight + Theme.padding * 2

    component Action: Button {
        Layout.fillWidth: true
        implicitHeight: 33
        raised: true
    }

    ColumnLayout {
        id: column

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: Theme.padding
        }
        spacing: Theme.spacing

        PopupHeader {
            title: "KDE Connect"
            settingsModule: "kcm_kdeconnect"
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1.5
            color: Theme.surface
        }

        ColumnLayout {
            visible: root.devices.length === 0
            Layout.fillWidth: true
            Layout.topMargin: Theme.padding
            Layout.bottomMargin: Theme.padding
            spacing: Theme.padding

            Icon {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 36
                implicitHeight: 36
                source: "smartphone-symbolic"
                color: Theme.fgDim
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                color: Theme.fgDim
                text: "No paired device is connected"
            }

            Button {
                Layout.alignment: Qt.AlignHCenter
                text: "Pair a device…"
                onClicked: {
                    Quickshell.execDetached(["kcmshell6", "kcm_kdeconnect"]);
                    Popouts.close();
                }
            }
        }

        Repeater {
            model: root.devices

            Rectangle {
                id: device

                required property var modelData
                readonly property var state: modelData

                Layout.fillWidth: true
                implicitHeight: card.implicitHeight + Theme.padding * 2
                radius: 12
                color: Theme.surface

                ColumnLayout {
                    id: card

                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: Theme.padding
                    }
                    spacing: Theme.padding

                    RowLayout {
                        spacing: Theme.spacing

                        Icon {
                            source: {
                                switch (device.state.type) {
                                case "tablet":
                                    return "tablet-symbolic";
                                case "laptop":
                                    return "computer-laptop-symbolic";
                                case "desktop":
                                    return "computer-symbolic";
                                case "tv":
                                    return "video-television-symbolic";
                                default:
                                    return "smartphone-symbolic";
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            font.bold: true
                            text: device.state.name
                        }

                        // mobile signal, as reported by the phone
                        Icon {
                            visible: (device.state.connectivity?.iconName ?? "") !== ""
                            source: device.state.connectivity?.iconName ?? ""
                            color: Theme.fgDim
                        }

                        Label {
                            visible: text !== ""
                            color: Theme.fgDim
                            text: device.state.connectivity?.cellularNetworkType ?? ""
                        }

                        Icon {
                            visible: device.state.battery?.hasBattery ?? false
                            source: device.state.battery?.iconName || "battery-symbolic"
                            color: (device.state.battery?.charge ?? 100) <= 15 && !device.state.battery?.isCharging ? Theme.error : Theme.fg
                        }

                        Label {
                            visible: device.state.battery?.hasBattery ?? false
                            text: (device.state.battery?.charge ?? 0) + "%"
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        uniformCellWidths: true
                        columnSpacing: Theme.spacing
                        rowSpacing: Theme.spacing
                        visible: device.state.canShare.available || device.state.canRing.available || device.state.canBrowse.available || device.state.canSms.available

                        Action {
                            visible: device.state.canShare.available
                            icon: "document-share-symbolic"
                            text: "Share file"
                            onClicked: {
                                // pick with KDE's file dialog, then hand each file to the device
                                Quickshell.execDetached(["sh", "-c", 'kdialog --title "Share with $2" --getopenfilename "$HOME" --multiple --separate-output | while IFS= read -r file; do kdeconnect-cli -d "$1" --share "$file"; done', "sh", device.state.deviceId, device.state.name]);
                                Popouts.close();
                            }
                        }

                        Action {
                            visible: device.state.canRing.available
                            icon: "audio-volume-high-symbolic"
                            text: "Ring my phone"
                            onClicked: KDEConnect.FindMyPhoneDbusInterfaceFactory.create(device.state.deviceId).ring()
                        }

                        Action {
                            visible: device.state.canBrowse.available
                            icon: "folder-symbolic"
                            text: "Browse this device"
                            onClicked: {
                                KDEConnect.SftpDbusInterfaceFactory.create(device.state.deviceId).startBrowsing();
                                Popouts.close();
                            }
                        }

                        Action {
                            visible: device.state.canSms.available
                            icon: "mail-message-symbolic"
                            text: "SMS Messages"
                            onClicked: {
                                Quickshell.execDetached(["kdeconnect-sms", "--device", device.state.deviceId]);
                                Popouts.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
