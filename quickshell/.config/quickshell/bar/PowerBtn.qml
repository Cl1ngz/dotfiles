import QtQuick
import Quickshell
import qs

Pill {
    icon: "⏻"
    iconSize: 22
    tint: Colors.accent
    onClicked: Quickshell.execDetached(["sh", "-c", "quickshell -p ~/.config/quickshell/powermenu.qml"])
}
