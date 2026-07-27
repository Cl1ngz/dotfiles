import QtQuick
import Quickshell.Services.UPower
import qs

// Native UPower. Hidden entirely on desktops with no battery.
Pill {
    id: batteryPill

    readonly property var device: UPower.displayDevice
    readonly property bool present: device.ready && device.isLaptopBattery
    readonly property int percent: Math.round(device.percentage * 100)
    // Wired vs battery: chargingNow = actively filling; onAc also covers
    // full/held-at-threshold while plugged in, which shows a plug icon so
    // "on wall power" is always visually distinct from "on battery".
    readonly property bool chargingNow: device.state === UPowerDeviceState.Charging
    readonly property bool onAc: chargingNow
        || device.state === UPowerDeviceState.PendingCharge
        || device.state === UPowerDeviceState.FullyCharged

    visible: present
    interactive: false
    toggleableLabel: true

    icon: {
        if (onAc) return chargingNow ? "󰂄" : "󰚥";
        if (percent >= 90) return "󰁹";
        if (percent >= 70) return "󰂁";
        if (percent >= 45) return "󰁾";
        if (percent >= 20) return "󰁼";
        return "󰁺";
    }
    label: percent + "%"
    tint: onAc ? Colors.accent
        : percent <= 15 ? Colors.danger
        : percent <= 30 ? Colors.warn
        : Colors.textMain

    // waybar blinked the critical battery; a soft pulse reads the same
    // without the strobe.
    SequentialAnimation on opacity {
        running: batteryPill.present && !batteryPill.onAc && batteryPill.percent <= 15
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
    }
}
