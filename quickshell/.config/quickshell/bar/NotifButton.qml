import QtQuick
import qs

// Small text button for the notification centre (header "Clear all",
// per-app "ignore" and "x", "show N more", entry "x").
//
// Its own file rather than an inline component in NotifBell.qml: adding
// an inline component to a file that already existed failed on hot
// reload with "TextBtn is not a type". A separate file has no such
// problem.
Rectangle {
    id: tb

    property string label: ""
    property color tint: Colors.textFaint
    property color hoverTint: Colors.textMain
    property color hoverFill: Colors.surface1

    signal clicked()

    implicitWidth: tbLabel.implicitWidth + 14
    implicitHeight: 20
    radius: 6
    color: tbHover.hovered ? tb.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 110 } }

    Text {
        id: tbLabel
        anchors.centerIn: parent
        text: tb.label
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
        color: tbHover.hovered ? tb.hoverTint : tb.tint
    }

    HoverHandler {
        id: tbHover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler { onTapped: tb.clicked() }
}
