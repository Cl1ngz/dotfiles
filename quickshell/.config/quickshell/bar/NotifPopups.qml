// Toast popups, top-right under the bar.

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// The Repeater runs over the server's ObjectModel, which updates
// incrementally -- delegates persist across changes. Whether a toast is
// *shown* is a per-delegate binding on Notifs.popupIds, and its height,
// opacity and slide are all Behaviors on that binding. That is what
// makes appearing, dismissing, and the stack collapsing all animate
// instead of snapping: nothing is ever rebuilt, only re-bound.
//
// Hover is read with HoverHandlers. The old hoverEnabled MouseAreas
// took hover from each other: pointing at the close button or an
// action took it off the toast, so the countdown un-paused and the
// toast could vanish under the cursor while you were reaching for a
// button. Handlers share hover; clicks stay on plain MouseAreas.
PanelWindow {
    id: popupWindow

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

    anchors {
        top: true
        right: true
    }

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
                readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                // Repeats of this exact message while its toast was up.
                readonly property int repeats: Notifs.toastCount(modelData.id)
                readonly property bool shown: entered && Notifs.popupIds.indexOf(modelData.id) !== -1
                // False for one tick after creation so the entrance
                // animates up from zero instead of starting at full size.
                property bool entered: false
                property real progress: 1

                Component.onCompleted: entered = true
                width: popupColumn.width
                implicitHeight: shown ? toast.implicitHeight + 8 : 0
                clip: true

                // Auto-hide countdown; critical toasts never start it,
                // and hovering pauses it.
                NumberAnimation {
                    target: slot
                    property: "progress"
                    from: 1
                    to: 0
                    duration: 6000
                    running: slot.shown && !slot.critical
                    paused: running && toastHover.hovered
                    onStopped: {
                        if (slot.progress <= 0.01) {
                            Notifs.hidePopup(slot.modelData.id);
                        }
                    }
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

                    // Urgency stripe, same language as the list rows.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: parent.height - 20
                        radius: 2
                        color: slot.critical ? Colors.danger : Colors.accent
                    }

                    HoverHandler {
                        id: toastHover
                    }

                    MouseArea {
                        anchors.fill: parent
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
                                    // The sending script's name for plain
                                    // notify-send calls (see Notifs.appNameOf).
                                    text: Notifs.appNameOf(slot.modelData)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    color: slot.critical ? Colors.danger : Colors.textFaint
                                }

                                // Same message again: one toast that counts
                                // up instead of a column of copies.
                                Rectangle {
                                    visible: slot.repeats > 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: repeatLabel.implicitWidth + 10
                                    implicitHeight: 14
                                    radius: 7
                                    color: Qt.alpha(Colors.accent, 0.18)

                                    Text {
                                        id: repeatLabel

                                        anchors.centerIn: parent
                                        text: "\u00d7" + slot.repeats
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                        color: Colors.accent
                                    }

                                }

                            }

                            // Full dismiss; only offered while hovering.
                            Item {
                                anchors.right: parent.right
                                anchors.rightMargin: -6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                opacity: toastHover.hovered ? 1 : 0
                                enabled: toastHover.hovered

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    font.pixelSize: 11
                                    color: closeHover.hovered ? Colors.danger : Colors.textFaint

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 120
                                        }

                                    }

                                }

                                HoverHandler {
                                    id: closeHover

                                    cursorShape: Qt.PointingHandCursor
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Notifs.dismiss(slot.modelData)
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 130
                                    }

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
                                    color: actionHover.hovered ? Colors.surface1 : Colors.surface0

                                    Text {
                                        id: actionLabel

                                        anchors.centerIn: parent
                                        text: parent.modelData.text
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        color: Colors.textMain
                                    }

                                    HoverHandler {
                                        id: actionHover

                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            parent.modelData.invoke();
                                            Notifs.dismiss(slot.modelData);
                                        }
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 120
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

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on x {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                Behavior on implicitHeight {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

    }

}
