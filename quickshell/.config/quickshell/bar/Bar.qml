import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.bar

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 42
    exclusiveZone: implicitHeight

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"

    color: "transparent"

    // ---------------- LEFT ----------------
    Island {
        anchors.left: parent.left
        anchors.leftMargin: 5
        anchors.verticalCenter: parent.verticalCenter

        PowerBtn { anchors.verticalCenter: parent.verticalCenter }
        Sep {}
        Workspaces {}
        Sep {}
        StayAwake { barWindow: bar; anchors.verticalCenter: parent.verticalCenter }
        PowerProfile { anchors.verticalCenter: parent.verticalCenter }
        BtStatus { anchors.verticalCenter: parent.verticalCenter }
    }

    // ---------------- CENTER ----------------
    Island {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        // Hide the island when mpd has nothing, like waybar.empty.
        visible: mpd.track !== "" || mpd.state !== ""

        Mpd { id: mpd; anchors.verticalCenter: parent.verticalCenter }
    }

    // ---------------- RIGHT ----------------
    Island {
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter

        Battery { id: battery; anchors.verticalCenter: parent.verticalCenter }
        Sep { visible: battery.visible && backlight.visible }
        Backlight { id: backlight; anchors.verticalCenter: parent.verticalCenter }
        AudioPill { isSink: false; anchors.verticalCenter: parent.verticalCenter }
        AudioPill { isSink: true; anchors.verticalCenter: parent.verticalCenter }
        SysStats {}
        Sep {}
        ClockPill { anchors.verticalCenter: parent.verticalCenter }
        Sep { visible: trayWidget.visible }
        Tray { id: trayWidget }
    }
}
