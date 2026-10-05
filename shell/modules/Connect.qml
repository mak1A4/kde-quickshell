import QtQuick
import QtQuick.Layouts
import org.kde.kdeconnect as KDEConnect
import qs
import qs.widgets
import qs.modules.connect

// KDE Connect, on the daemon's own QML module (the one Plasma's applet uses).
// The icon is dim while no paired device is reachable. Left click opens the
// panel (connect/ConnectPanel.qml).
BarButton {
    id: root

    tucked: BarItems.tucked("connect")
    readonly property bool anyConnected: deviceModel.count > 0
    // the per-device state objects below, for the panel
    property list<QtObject> states: []
    property list<string> summary: []

    function refresh() {
        const objects = [], lines = [];
        for (let i = 0; i < connected.count; i++) {
            const device = connected.objectAt(i);
            if (!device)
                continue;
            objects.push(device);
            lines.push(device.line);
        }
        states = objects;
        summary = lines;
    }

    active: Popouts.current === "connect"
    hintTitle: "KDE Connect"
    hintLines: anyConnected ? summary : ["No device connected"]
    onClicked: button => {
        if (button === Qt.LeftButton)
            Popouts.toggle("connect", root, panel);
    }

    // paired devices that are reachable right now, as in Plasma's applet
    KDEConnect.DevicesModel {
        id: deviceModel

        displayFilter: KDEConnect.DevicesModel.Paired | KDEConnect.DevicesModel.Reachable
    }

    // State of each connected device, kept for as long as it is connected:
    // the hint needs it, and the panel must find it complete when it opens.
    Instantiator {
        id: connected

        model: deviceModel
        onObjectAdded: root.refresh()
        onObjectRemoved: root.refresh()

        QtObject {
            id: state

            required property var model
            readonly property string deviceId: model.deviceId
            readonly property string name: model.name
            readonly property string type: model.device.type
            readonly property var battery: KDEConnect.DeviceBatteryDbusInterfaceFactory.create(deviceId)
            readonly property var connectivity: KDEConnect.DeviceConnectivityReportDbusInterfaceFactory.create(deviceId)
            readonly property var canShare: KDEConnect.PluginChecker {
                device: state.model.device
                pluginName: "share"
            }
            readonly property var canRing: KDEConnect.PluginChecker {
                device: state.model.device
                pluginName: "findmyphone"
            }
            readonly property var canBrowse: KDEConnect.PluginChecker {
                device: state.model.device
                pluginName: "sftp"
            }
            readonly property var canSms: KDEConnect.PluginChecker {
                device: state.model.device
                pluginName: "sms"
            }
            readonly property string line: {
                if (!battery?.hasBattery)
                    return name;
                return `${name} · ${battery.charge}%` + (battery.isCharging ? ", charging" : "");
            }

            onLineChanged: root.refresh()
        }
    }

    Component {
        id: panel

        ConnectPanel {
            devices: root.states
        }
    }

    Icon {
        Layout.alignment: Qt.AlignHCenter
        module: "connect"
        source: "smartphone-symbolic"
        color: root.anyConnected ? Theme.fg : Theme.fgDim
        opacity: root.anyConnected ? 1 : 0.6
    }
}
