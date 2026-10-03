import QtQuick
import org.kde.plasma.private.batterymonitor as BatteryMonitor
import org.kde.plasma.private.battery as Battery
import qs
import qs.widgets
import qs.modules.power

// Power pill on PowerDevil's own QML modules (the ones Plasma's applet uses).
// Shows the laptop battery when there is one, the power profile otherwise.
// Left click opens the panel, middle click toggles the manual sleep block.
Pill {
    id: root

    readonly property bool hasBattery: batteryModel.hasInternalBatteries
    readonly property bool charging: batteryModel.state === Battery.BatteryControlModel.Charging

    active: popup.visible
    onClicked: button => {
        if (button === Qt.LeftButton)
            popup.visible = !popup.visible;
        else if (button === Qt.MiddleButton && inhibitionControl.isManuallyInhibited)
            inhibitionControl.uninhibit();
        else if (button === Qt.MiddleButton)
            inhibitionControl.inhibit("Manually blocked from the bar");
    }

    // These live here, not in the panel: the pill needs their state, and they
    // must outlive the popup.
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
        visible: root.hasBattery
        color: !root.charging && batteryModel.percent <= 15 ? Theme.error : Theme.fg
        text: batteryModel.percent + "%"
    }

    BarPopup {
        id: popup

        anchorItem: root
        implicitHeight: 390

        PowerPanel {
            anchors.fill: parent
            profiles: profilesControl
            inhibition: inhibitionControl
            batteries: batteryModel
        }
    }
}
