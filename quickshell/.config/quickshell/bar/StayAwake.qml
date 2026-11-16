import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import qs

// Keep the screen on: hypridle's dim / screen-off / lock / suspend all
// wait while this is active.
//
// Two locks, because they fail in different ways:
//
//   IdleInhibitor   the Wayland idle-inhibit protocol, on the bar window.
//                   What waybar's idle_inhibitor does. Depends on the
//                   compositor counting a layer-shell surface's
//                   inhibitor, which is the part that stopped working.
//
//   systemd-inhibit a logind "idle" lock. hypridle honours it
//                   (ignore_systemd_inhibit defaults to false) and it
//                   has nothing to do with surfaces or the compositor.
//
// Either one alone is enough for hypridle; holding both means the toggle
// works whichever path the current Hyprland honours.
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

    // The lock lives exactly as long as this process. `cat` sits on
    // stdin, which is a pipe from Quickshell: if Quickshell dies or
    // reloads, the pipe closes, cat exits and the lock is released --
    // a crashed bar can never leave the laptop unable to sleep.
    // Toggling off stops the process the normal way.
    Process {
        running: stayAwake.active
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=idle", "--mode=block", "--who=quickshell", "--why=stay awake (bar toggle)", "cat"]
    }
}
