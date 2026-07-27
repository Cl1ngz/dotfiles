import QtQuick
import qs

// The .modules-left / .modules-right island: bar bg, faint border,
// big radius. Children land in the inner Row.
Rectangle {
    id: island

    default property alias content: inner.children
    property int gap: 4

    visible: inner.children.length > 0
    implicitWidth: inner.implicitWidth + 16
    implicitHeight: 36
    radius: 18

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    color: Colors.base
    border.width: 1
    border.color: Qt.alpha(Colors.textMain, 0.2)

    Row {
        id: inner
        anchors.centerIn: parent
        spacing: island.gap
    }
}
