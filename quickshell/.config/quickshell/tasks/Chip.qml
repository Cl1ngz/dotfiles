import QtQuick
import qs

// Small pill used for category and importance pickers and filters.
Rectangle {
    id: chip
    property string label: ""
    property color tint: Colors.textDim
    property bool active: false
    signal clicked()

    implicitWidth: chipText.implicitWidth + 20
    implicitHeight: 24
    radius: 12
    color: active ? Qt.alpha(tint, 0.22)
         : chipHov.hovered ? Colors.surface1 : Colors.surface0
    border.width: active ? 1 : 0
    border.color: Qt.alpha(tint, 0.6)
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: chipText
        anchors.centerIn: parent
        text: chip.label
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
        font.weight: chip.active ? Font.DemiBold : Font.Normal
        color: chip.active ? chip.tint : Colors.textDim
    }
    // Handlers rather than a hoverEnabled MouseArea, so a chip sitting
    // on top of something hoverable does not steal the hover from it.
    HoverHandler {
        id: chipHov
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler { onTapped: chip.clicked() }
}
