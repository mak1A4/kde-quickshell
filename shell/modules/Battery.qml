import Quickshell.Services.UPower
import QtQuick
import qs
import qs.widgets

// UPower's aggregate display device. Hidden on machines without a battery.
Pill {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property int percent: Math.round(device.percentage * 100)
    readonly property bool low: UPower.onBattery && percent <= 15

    visible: device.ready && device.isPresent
    interactive: false

    Icon {
        color: root.low ? Theme.error : Theme.fg
        source: root.device.iconName || "battery-symbolic"
    }

    Label {
        color: root.low ? Theme.error : Theme.fg
        text: root.percent + "%"
    }
}
