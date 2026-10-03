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

    readonly property bool anyConnected: deviceModel.count > 0
    property list<string> summary: []

    function refreshSummary() {
        const lines = [];
        for (let i = 0; i < connected.count; i++) {
            const device = connected.objectAt(i);
            if (device)
                lines.push(device.line);
        }
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

    // one line per device for the hint: name and battery
    Instantiator {
        id: connected

        model: deviceModel
        onObjectAdded: root.refreshSummary()
        onObjectRemoved: root.refreshSummary()

        QtObject {
            required property var model
            readonly property var battery: KDEConnect.DeviceBatteryDbusInterfaceFactory.create(model.deviceId)
            readonly property string line: {
                if (!battery?.hasBattery)
                    return model.name;
                return `${model.name} · ${battery.charge}%` + (battery.isCharging ? ", charging" : "");
            }

            onLineChanged: root.refreshSummary()
        }
    }

    Component {
        id: panel

        ConnectPanel {
            devices: deviceModel
        }
    }

    Icon {
        Layout.alignment: Qt.AlignHCenter
        source: "smartphone-symbolic"
        color: root.anyConnected ? Theme.fg : Theme.fgDim
        opacity: root.anyConnected ? 1 : 0.6
    }
}
