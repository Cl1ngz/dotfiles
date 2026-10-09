import QtQuick
import qs

// The trigger half of a picker. The list half is a single popup that
// lives at card level (see tasks.qml): one popup, positioned against
// whichever trigger is active.
//
// Splitting it this way is the whole point. When each picker carried
// its own expanding list, the list was a child of the add row, so
// opening it made the add row taller than the card and the options
// were drawn below the card's bottom edge, onto the desktop. A popup
// anchored inside the card cannot escape it.
Rectangle {
    id: btn

    property string placeholder: "none"
    property var current: null
    property color dotColor: Colors.textFaint
    property bool open: false

    signal toggled()

    height: 26
    radius: 7
    color: open ? Colors.surface1
         : mouse.containsMouse ? Colors.surface0 : "transparent"
    border.width: 1
    border.color: open ? Qt.alpha(Colors.accent, 0.6) : Colors.outline
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        visible: btn.current !== null
        width: 8
        height: 8
        radius: 4
        color: btn.dotColor
    }

    Text {
        anchors.left: btn.current !== null ? dot.right : parent.left
        anchors.leftMargin: btn.current !== null ? 7 : 9
        anchors.right: caret.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: btn.current === null ? btn.placeholder : ("" + btn.current)
        elide: Text.ElideRight
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
        color: btn.current === null ? Colors.textFaint : Colors.textMain
    }

    Text {
        id: caret
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: "▾"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        color: Colors.textFaint
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.toggled()
    }
}
