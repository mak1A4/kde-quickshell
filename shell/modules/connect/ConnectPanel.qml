import Quickshell
import QtQuick
import QtQuick.Layouts
import org.kde.kdeconnect as KDEConnect
import qs
import qs.widgets

// Port of Plasma's KDE Connect applet: one card per connected device with
// mobile signal, battery and the device actions. An action is offered only
// when the device has that plugin loaded.
Item {
    id: root

    required property var devices // KDEConnect.DevicesModel

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
            visible: root.devices.count === 0
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

                required property var model
                readonly property string deviceId: model.deviceId
                readonly property var battery: KDEConnect.DeviceBatteryDbusInterfaceFactory.create(deviceId)
                readonly property var connectivity: KDEConnect.DeviceConnectivityReportDbusInterfaceFactory.create(deviceId)

                Layout.fillWidth: true
                implicitHeight: card.implicitHeight + Theme.padding * 2
                radius: 12
                color: Theme.surface

                KDEConnect.PluginChecker {
                    id: canShare

                    device: device.model.device
                    pluginName: "share"
                }

                KDEConnect.PluginChecker {
                    id: canRing

                    device: device.model.device
                    pluginName: "findmyphone"
                }

                KDEConnect.PluginChecker {
                    id: canBrowse

                    device: device.model.device
                    pluginName: "sftp"
                }

                KDEConnect.PluginChecker {
                    id: canSms

                    device: device.model.device
                    pluginName: "sms"
                }

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
                                switch (device.model.device.type) {
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
                            text: device.model.name
                        }

                        // mobile signal, as reported by the phone
                        Icon {
                            visible: (device.connectivity?.iconName ?? "") !== ""
                            source: device.connectivity?.iconName ?? ""
                            color: Theme.fgDim
                        }

                        Label {
                            visible: text !== ""
                            color: Theme.fgDim
                            text: device.connectivity?.cellularNetworkType ?? ""
                        }

                        Icon {
                            visible: device.battery?.hasBattery ?? false
                            source: device.battery?.iconName || "battery-symbolic"
                            color: (device.battery?.charge ?? 100) <= 15 && !device.battery?.isCharging ? Theme.error : Theme.fg
                        }

                        Label {
                            visible: device.battery?.hasBattery ?? false
                            text: (device.battery?.charge ?? 0) + "%"
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        uniformCellWidths: true
                        columnSpacing: Theme.spacing
                        rowSpacing: Theme.spacing
                        visible: canShare.available || canRing.available || canBrowse.available || canSms.available

                        Action {
                            visible: canShare.available
                            icon: "document-share-symbolic"
                            text: "Share file"
                            onClicked: {
                                // pick with KDE's file dialog, then hand each file to the device
                                Quickshell.execDetached(["sh", "-c", 'kdialog --title "Share with $2" --getopenfilename "$HOME" --multiple --separate-output | while IFS= read -r file; do kdeconnect-cli -d "$1" --share "$file"; done', "sh", device.deviceId, device.model.name]);
                                Popouts.close();
                            }
                        }

                        Action {
                            visible: canRing.available
                            icon: "audio-volume-high-symbolic"
                            text: "Ring my phone"
                            onClicked: KDEConnect.FindMyPhoneDbusInterfaceFactory.create(device.deviceId).ring()
                        }

                        Action {
                            visible: canBrowse.available
                            icon: "folder-symbolic"
                            text: "Browse this device"
                            onClicked: {
                                KDEConnect.SftpDbusInterfaceFactory.create(device.deviceId).startBrowsing();
                                Popouts.close();
                            }
                        }

                        Action {
                            visible: canSms.available
                            icon: "mail-message-symbolic"
                            text: "SMS Messages"
                            onClicked: {
                                Quickshell.execDetached(["kdeconnect-sms", "--device", device.deviceId]);
                                Popouts.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
