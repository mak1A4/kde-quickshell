import QtQuick
import QtQuick.Layouts
import org.kde.plasma.private.batterymonitor as BatteryMonitor
import org.kde.plasma.private.battery as Battery
import qs
import qs.widgets
import qs.modules.power

// Power button on PowerDevil's own QML modules (the ones Plasma's applet uses).
// Shows the laptop battery when there is one, the power profile otherwise.
// Left click opens the panel, middle click toggles the manual sleep block.
BarButton {
    id: root

    readonly property bool hasBattery: batteryModel.hasInternalBatteries
    readonly property bool charging: batteryModel.state === Battery.BatteryControlModel.Charging

    tucked: BarItems.tucked("power")
    active: Popouts.current === "power"
    hintTitle: {
        if (hasBattery)
            return `Battery ${batteryModel.percent}%` + (charging ? ", charging" : "");
        return profilesControl.activeProfile ? "Power profile" : "Power";
    }
    hintLines: {
        const names = {
            "power-saver": "Power Save",
            "balanced": "Balanced",
            "performance": "Performance"
        };
        const lines = [];
        if (profilesControl.activeProfile)
            lines.push(names[profilesControl.activeProfile] ?? profilesControl.activeProfile);
        if (inhibitionControl.isManuallyInhibited)
            lines.push("Sleep and screen locking blocked manually");
        const apps = [...new Set(inhibitionControl.requestedInhibitions.filter(r => r.active && r.allowed).map(r => r.prettyName))];
        if (apps.length > 0)
            lines.push("Blocking sleep: " + apps.join(", "));
        return lines;
    }
    onClicked: button => {
        if (button === Qt.LeftButton)
            Popouts.toggle("power", root, panel);
        else if (button === Qt.MiddleButton && inhibitionControl.isManuallyInhibited)
            inhibitionControl.uninhibit();
        else if (button === Qt.MiddleButton)
            inhibitionControl.inhibit("Manually blocked from the bar");
    }

    // These live here, not in the panel: the button needs their state, and
    // they must outlive the popout.
    BatteryMonitor.PowerProfilesControl {
        id: profilesControl
    }

    BatteryMonitor.InhibitionControl {
        id: inhibitionControl
    }

    Battery.BatteryControlModel {
        id: batteryModel
    }

    Icon {
        Layout.alignment: Qt.AlignHCenter
        module: "power"
        // accent while sleep and screen locking are manually blocked
        color: inhibitionControl.isManuallyInhibited ? Theme.accent : Theme.fg
        source: {
            if (root.hasBattery) {
                const level = String(Math.round(batteryModel.percent / 10) * 10).padStart(3, "0");
                return `battery-${level}${root.charging ? "-charging" : ""}-symbolic`;
            }
            switch (profilesControl.activeProfile) {
            case "power-saver":
                return "battery-profile-powersave-symbolic";
            case "balanced":
                return "battery-profile-balanced-symbolic";
            case "performance":
                return "battery-profile-performance-symbolic";
            default:
                return "speedometer-symbolic";
            }
        }
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        visible: root.hasBattery
        color: !root.charging && batteryModel.percent <= 15 ? Theme.error : Theme.fg
        font.pixelSize: Theme.fontSizeSmall
        text: batteryModel.percent
    }

    Component {
        id: panel

        PowerPanel {
            profiles: profilesControl
            inhibition: inhibitionControl
            batteries: batteryModel
        }
    }
}
