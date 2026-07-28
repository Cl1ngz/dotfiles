import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs

// Toast popups, top-right under the bar.
//
// The Repeater runs over the server's ObjectModel, which updates
// incrementally -- delegates persist across changes. Whether a toast is
// *shown* is a per-delegate binding on Notifs.popupIds, and its height,
// opacity and slide are all Behaviors on that binding. That is what
// makes appearing, dismissing, and the stack collapsing all animate
// instead of snapping: nothing is ever rebuilt, only re-bound.
PanelWindow {
    id: popupWindow

    anchors {
        top: true
        right: true
    }
    margins.right: 8
    margins.top: 6
    implicitWidth: 380
    implicitHeight: Math.max(1, popupColumn.implicitHeight)
    exclusiveZone: 0
    // Map on DATA (popups pending) -- content doesn't lay out until the
    // window maps, so gating visibility on implicitHeight alone was a
    // deadlock: height stayed 0 because the window never mapped. The
    // height term only keeps it mapped while a collapse animation is
    // still playing out after the last popup is removed.
    visible: Notifs.popupList.length > 0 || popupColumn.implicitHeight > 1

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notif-popups"
    color: "transparent"

    Column {
        id: popupColumn
        width: parent.width
        // Spacing lives inside each delegate's height so collapsed
        // toasts contribute zero, not ghost gaps.
        spacing: 0

        Repeater {
            model: Notifs.server.trackedNotifications

            Item {
                id: slot
                required property var modelData

                readonly property bool critical:
                    modelData.urgency === NotificationUrgency.Critical
                readonly property bool shown:
                    entered && Notifs.popupIds.indexOf(modelData.id) !== -1
                // False for one tick after creation so the entrance
                // animates up from zero instead of starting at full size.
                property bool entered: false
                property real progress: 1

                Component.onCompleted: entered = true

                width: popupColumn.width
                implicitHeight: shown ? toast.implicitHeight + 8 : 0
                clip: true

                Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // Auto-hide countdown; critical toasts never start it,
                // and hovering pauses it.
                NumberAnimation {
                    target: slot
                    property: "progress"
                    from: 1
                    to: 0
                    duration: 6000
                    running: slot.shown && !slot.critical
                    paused: running && hoverMouse.containsMouse
                    onStopped: if (slot.progress <= 0.01) Notifs.hidePopup(slot.modelData.id)
                }

                Rectangle {
                    id: toast
                    width: parent.width
                    implicitHeight: toastContent.implicitHeight + 24
                    radius: 12
                    color: Colors.base
                    border.width: 1
                    border.color: slot.critical ? Qt.alpha(Colors.danger, 0.6) : Colors.outline

                    opacity: slot.shown ? 1 : 0
                    x: slot.shown ? 0 : 36
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    // Urgency stripe, same language as the list rows.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: parent.height - 20
                        radius: 2
                        color: slot.critical ? Colors.danger : Colors.accent
                    }

                    MouseArea {
                        id: hoverMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        // Click tucks it away; it stays in the center.
                        onClicked: Notifs.hidePopup(slot.modelData.id)
                    }

                    Column {
                        id: toastContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        anchors.leftMargin: 16
                        spacing: 5

                        Item {
                            width: parent.width
                            height: 15

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                IconImage {
                                    visible: slot.modelData.appIcon !== ""
                                    width: 13
                                    height: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: Quickshell.iconPath(slot.modelData.appIcon, true)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: slot.modelData.appName
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    color: slot.critical ? Colors.danger : Colors.textFaint
                                }
                            }

                            // Full dismiss; only offered while hovering.
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "✕"
                                font.pixelSize: 11
                                opacity: hoverMouse.containsMouse || closeMouse.containsMouse ? 1 : 0
                                color: closeMouse.containsMouse ? Colors.danger : Colors.textFaint
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                                Behavior on color { ColorAnimation { duration: 120 } }

                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    onClicked: Notifs.dismiss(slot.modelData)
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: slot.modelData.summary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Colors.textMain
                        }

                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: slot.modelData.body
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            color: Colors.textDim
                        }

                        Row {
                            visible: slot.modelData.actions.length > 0
                            spacing: 6

                            Repeater {
                                model: slot.modelData.actions

                                Rectangle {
                                    required property var modelData
                                    implicitWidth: actionLabel.implicitWidth + 20
                                    implicitHeight: 24
                                    radius: 7
                                    color: actionMouse.containsMouse ? Colors.surface1 : Colors.surface0
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: parent.modelData.text
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        color: Colors.textMain
                                    }

                                    MouseArea {
                                        id: actionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            parent.modelData.invoke();
                                            Notifs.dismiss(slot.modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Remaining-time bar along the bottom; freezes with
                    // the countdown while hovered.
                    Rectangle {
                        visible: !slot.critical
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: (parent.width - 24) * slot.progress
                        height: 2
                        radius: 1
                        color: Qt.alpha(Colors.accent, 0.5)
                    }
                }
            }
        }
    }
}
