import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// Connection state from Quickshell's NetworkManager backend. Wired wins over
// wifi when both are up. Red = no backend, yellow = no (full) internet.
BarButton {
    id: root

    tucked: BarItems.tucked("network")
    readonly property bool available: Networking.backend !== NetworkBackendType.None
    readonly property var devices: Networking.devices.values
    readonly property NetworkDevice wired: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property NetworkDevice wifi: devices.find(d => d.type === DeviceType.Wifi && d.connected) ?? null
    readonly property var wifiNetwork: wifi?.networks.values.find(n => n.connected) ?? null
    // connected to a network but NetworkManager's check says no (full) internet
    readonly property bool limited: (wired || wifi) && [NetworkConnectivity.None, NetworkConnectivity.Portal, NetworkConnectivity.Limited].includes(Networking.connectivity)

    interactive: false
    hintTitle: {
        if (!available)
            return "NetworkManager unavailable";
        if (wired)
            return "Wired";
        if (wifi)
            return wifiNetwork?.name ?? "Wi-Fi";
        return "Offline";
    }
    hintLines: {
        const lines = [];
        if (wired)
            lines.push(wired.name + (wired.linkSpeed ? ` · ${wired.linkSpeed} Mb/s` : ""));
        if (wifi)
            lines.push(`${wifi.name} · signal ${Math.round((wifiNetwork?.signalStrength ?? 0) * 100)}%`);
        if (wired && wifi)
            lines.push("Wi-Fi: " + (wifiNetwork?.name ?? "connected"));
        if (available && (wired || wifi))
            lines.push(limited ? "No internet access" : NetworkConnectivity.toString(Networking.connectivity));
        return lines;
    }

    Icon {
        Layout.alignment: Qt.AlignHCenter
        module: "network"
        color: !root.available ? Theme.error : (root.limited ? Theme.warning : Theme.fg)
        source: {
            if (!root.available)
                return "network-offline-symbolic";
            if (root.wired)
                return "network-wired-symbolic";
            if (root.wifi) {
                const strength = root.wifiNetwork?.signalStrength ?? 0;
                if (strength > 0.75)
                    return "network-wireless-signal-excellent-symbolic";
                if (strength > 0.5)
                    return "network-wireless-signal-good-symbolic";
                if (strength > 0.25)
                    return "network-wireless-signal-ok-symbolic";
                return "network-wireless-signal-weak-symbolic";
            }
            return "network-offline-symbolic";
        }
    }
}
