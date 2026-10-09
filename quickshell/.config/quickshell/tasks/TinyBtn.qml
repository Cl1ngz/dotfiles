import QtQuick
import qs

// Borderless text button for row actions. Stays invisible until the
// row is hovered, so a list of tasks reads as text rather than as a
// wall of buttons.
Rectangle {
    id: btn
    property string label: ""
    property color tint: Colors.textFaint
    // No `enabled` property declared here: Item already has one, and
    // shadowing it would break the built-in behaviour of refusing
    // input when false. Setting btn.enabled from outside just works.
    signal clicked()

    implicitWidth: tbText.implicitWidth + 16
    implicitHeight: 22
    radius: 6
    opacity: enabled ? 1 : 0.35
    color: tbMouse.containsMouse && enabled ? Colors.surface1 : "transparent"
    Behavior on color { ColorAnimation { duration: 110 } }

    Text {
        id: tbText
        anchors.centerIn: parent
        text: btn.label
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
        color: tbMouse.containsMouse && btn.enabled ? btn.tint : Colors.textFaint
    }
    MouseArea {
        id: tbMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (btn.enabled) btn.clicked()
    }
}
