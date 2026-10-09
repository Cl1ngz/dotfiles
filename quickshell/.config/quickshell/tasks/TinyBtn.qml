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
    color: hov.hovered && enabled ? Colors.surface1 : "transparent"
    Behavior on color { ColorAnimation { duration: 110 } }

    Text {
        id: tbText
        anchors.centerIn: parent
        text: btn.label
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
        color: hov.hovered && btn.enabled ? btn.tint : Colors.textFaint
    }
    // HoverHandler, not a hoverEnabled MouseArea.
    //
    // A MouseArea that accepts hover STEALS it from the one on the row
    // behind it. The row's hover drives whether these buttons are shown
    // at all, so entering a button hid the button, which put the cursor
    // back on the row, which showed it again -- a flicker loop you
    // could not click through. Handlers do not take hover from each
    // other: the row and the button can both be hovered at once.
    HoverHandler {
        id: hov
        enabled: btn.enabled
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        enabled: btn.enabled
        onTapped: btn.clicked()
    }
}
