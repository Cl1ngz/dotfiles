import QtQuick
import Quickshell.Wayland
import qs

// waybar's idle_inhibitor, via the same wayland idle-inhibit protocol
// (no external tools). The inhibitor is attached to the bar window
// itself, which is always visible, so it holds while toggled on.
Pill {
    id: stayAwake

    // The bar window; set by Bar.qml.
    required property var barWindow

    property bool active: false

    icon: active ? "󱎴" : "󰷛"
    tint: active ? Colors.accent : Colors.textFaint

    onClicked: active = !active

    IdleInhibitor {
        window: stayAwake.barWindow
        enabled: stayAwake.active
    }
}
