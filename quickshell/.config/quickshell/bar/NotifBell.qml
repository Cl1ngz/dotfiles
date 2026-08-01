import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs

// Bell pill + notification center. Left click opens the center under
// the pill (proven overlay pattern); right click clears everything.
Pill {
    id: bellPill

    readonly property int count: Notifs.records.length

    icon: count > 0 ? "󰂚" : "󰂜"
    label: count > 0 ? String(count) : ""
    tint: count > 0 ? Colors.accent : Colors.textFaint

    onClicked: (button) => {
        if (button === Qt.RightButton) {
            Notifs.forgetAll();
            return;
        }
        overlay.visible = !overlay.visible;
    }

    PanelWindow {
        id: overlay

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-notif-center"
        color: "transparent"
        visible: false
        exclusiveZone: 0

        MouseArea {
            anchors.fill: parent
            onClicked: overlay.visible = false
        }

        Rectangle {
            id: panelCard

            x: Math.max(8, Math.min(
                bellPill.mapToItem(null, 0, 0).x + bellPill.width / 2 - width / 2,
                overlay.width - width - 8))
            // Overlay top edge is already the bottom of the bar.
            y: 6
            width: 380
            implicitHeight: Math.min(centerColumn.implicitHeight + 28, overlay.height - 40)

            radius: 14
            color: Colors.base
            border.width: 1
            border.color: Colors.outline
            clip: true

            opacity: overlay.visible ? 1 : 0
            scale: overlay.visible ? 1 : 0.97
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            Column {
                id: centerColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 8

                // ---- header ----
                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notifications"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Colors.textMain
                    }

                    Rectangle {
                        visible: bellPill.count > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: clearLabel.implicitWidth + 18
                        implicitHeight: 22
                        radius: 7
                        color: clearMouse.containsMouse ? Qt.alpha(Colors.danger, 0.2) : Colors.surface0
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: clearLabel
                            anchors.centerIn: parent
                            text: "Clear all"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            color: clearMouse.containsMouse ? Colors.danger : Colors.textDim
                        }

                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Notifs.forgetAll()
                        }
                    }
                }

                Text {
                    visible: bellPill.count === 0
                    text: "All caught up."
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    color: Colors.textFaint
                }

                // ---- the list, newest first ----
                ListView {
                    id: centerList
                    width: parent.width
                    height: Math.min(contentHeight, overlay.height - 140)
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: Notifs.records.slice().reverse()

                    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    delegate: Rectangle {
                        id: item
                        required property var modelData
                        readonly property bool critical: modelData.urgency === "critical"
                        // Only notifications still held by the server can
                        // have their actions invoked; older ones are text.
                        readonly property var liveObj: Notifs.liveFor(modelData)

                        width: centerList.width
                        implicitHeight: itemContent.implicitHeight + 20
                        radius: 10
                        color: Colors.mantle
                        border.width: 1
                        border.color: item.critical ? Qt.alpha(Colors.danger, 0.5) : Colors.outline

                        Column {
                            id: itemContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            spacing: 4

                            Item {
                                width: parent.width
                                height: 15

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    IconImage {
                                        visible: item.modelData.appIcon !== ""
                                        width: 13
                                        height: 13
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: Quickshell.iconPath(item.modelData.appIcon, true)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: item.modelData.appName
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        color: item.critical ? Colors.danger : Colors.textFaint
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Notifs.timeAgo(item.modelData.time)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        color: Colors.textFaint
                                    }
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "✕"
                                    font.pixelSize: 11
                                    color: delMouse.containsMouse ? Colors.danger : Colors.textFaint
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    MouseArea {
                                        id: delMouse
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        onClicked: Notifs.forget(item.modelData)
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: item.modelData.summary
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: Colors.textMain
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: item.modelData.body
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: Colors.textDim
                            }

                            Row {
                                visible: item.liveObj !== null && item.liveObj.actions.length > 0
                                spacing: 6

                                Repeater {
                                    model: item.liveObj !== null ? item.liveObj.actions : []

                                    Rectangle {
                                        required property var modelData
                                        implicitWidth: caLabel.implicitWidth + 18
                                        implicitHeight: 22
                                        radius: 6
                                        color: caMouse.containsMouse ? Colors.surface1 : Colors.surface0
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Text {
                                            id: caLabel
                                            anchors.centerIn: parent
                                            text: parent.modelData.text
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            color: Colors.textMain
                                        }

                                        MouseArea {
                                            id: caMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                parent.modelData.invoke();
                                                Notifs.forget(item.modelData);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
