import QtQuick
import Quickshell
import qs

Pill {
    id: clockPill

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    interactive: false
    label: Qt.formatDateTime(clock.date, "HH:mm")
    tint: Colors.accent
}
