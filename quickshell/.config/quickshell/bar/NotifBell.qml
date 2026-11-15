import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Bell pill + notification centre. Left click opens the centre under the
// pill; right click clears everything.
//
// The centre is grouped by app: one card per app, newest app first, its
// messages inside. Identical messages are already one entry with a
// count (Notifs.record stacks them), so a script that fires the same
// line ten times is one row saying x10, not ten rows.
//
// Every hover here is a HoverHandler, never a hoverEnabled MouseArea.
// A MouseArea that takes hover steals it from the one behind it; with
// buttons that only appear while their row is hovered, that turns into
// the show/hide flicker loop the task list had.
Pill {
    id: bellPill

    readonly property int count: Notifs.records.length

    // Which app groups are expanded past `perGroup` entries.
    property var expanded: ({})
    property bool showIgnored: false
    readonly property int perGroup: 3

    function toggleExpanded(key) {
        const e = {};
        for (const k in expanded)
            e[k] = expanded[k];
        e[key] = !e[key];
        expanded = e;
    }

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

    // ---- centre ----------------------------------------------------------

    PanelWindow {
        id: overlay

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-notif-center"
        // Keyboard only while open, so Escape reaches the Shortcut below.
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        visible: false
        exclusiveZone: 0

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Collapse expanded groups and the ignored list each time it
        // closes, so it reopens in its compact form.
        onVisibleChanged: if (!visible) {
            bellPill.expanded = ({});
            bellPill.showIgnored = false;
        }

        MouseArea {
            anchors.fill: parent
            onClicked: overlay.visible = false
        }

        // Keys handlers on a PanelWindow never fire; a Shortcut does.
        // Enabled only while open: two live Escape shortcuts in one
        // process are ambiguous and then neither fires.
        Shortcut {
            sequences: ["Escape"]
            context: Qt.ApplicationShortcut
            enabled: overlay.visible
            onActivated: overlay.visible = false
        }

        Rectangle {
            id: panelCard

            x: Math.max(8, Math.min(bellPill.mapToItem(null, 0, 0).x + bellPill.width / 2 - width / 2,
                                    overlay.width - width - 8))
            // Overlay top edge is already the bottom of the bar.
            y: 6
            width: 400
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

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Notifications"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Colors.textMain
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Notifs.groups.length > 1
                            text: Notifs.groups.length + " apps"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            color: Colors.textFaint
                        }
                    }

                    NotifButton {
                        visible: bellPill.count > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Clear all"
                        tint: Colors.textDim
                        hoverTint: Colors.danger
                        hoverFill: Qt.alpha(Colors.danger, 0.15)
                        onClicked: Notifs.forgetAll()
                    }
                }

                Text {
                    visible: bellPill.count === 0
                    text: "All caught up."
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    color: Colors.textFaint
                }

                // ---- one card per app, newest app first ----
                ListView {
                    id: centerList

                    width: parent.width
                    height: Math.min(contentHeight,
                                     overlay.height - 150 - ignoredBlock.height)
                    visible: Notifs.groups.length > 0
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    model: Notifs.groups

                    Behavior on height {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }

                    delegate: Rectangle {
                        id: grp

                        required property var modelData
                        readonly property bool open: bellPill.expanded[modelData.key] === true
                        readonly property var shown: open
                            ? modelData.items
                            : modelData.items.slice(0, bellPill.perGroup)
                        readonly property int hidden: modelData.items.length - shown.length

                        width: centerList.width
                        implicitHeight: grpCol.implicitHeight + 14
                        radius: 10
                        color: Colors.mantle
                        border.width: 1
                        border.color: modelData.critical ? Qt.alpha(Colors.danger, 0.5) : Colors.outline

                        Column {
                            id: grpCol

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 7
                            spacing: 2

                            // ---- app header ----
                            Item {
                                width: parent.width
                                height: 22

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    IconImage {
                                        visible: grp.modelData.appIcon !== ""
                                        width: 14
                                        height: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: Quickshell.iconPath(grp.modelData.appIcon, true)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: grp.modelData.appName
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: grp.modelData.critical ? Colors.danger : Colors.textMain
                                    }
                                    // With one entry its own x-badge already
                                    // says how many; a second number here
                                    // would just repeat it.
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: grp.modelData.items.length > 1
                                        text: grp.modelData.total
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        color: Colors.textFaint
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "· " + Notifs.timeAgo(grp.modelData.latest)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        color: Colors.textFaint
                                    }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    // Not offered for "unknown" or
                                    // "notify-send": neither names a sender,
                                    // so ignoring one would swallow every
                                    // script that falls under it.
                                    NotifButton {
                                        visible: Notifs.canIgnore(grp.modelData.key)
                                        label: "ignore"
                                        hoverTint: Colors.warn
                                        hoverFill: Qt.alpha(Colors.warn, 0.15)
                                        onClicked: Notifs.ignoreApp(grp.modelData.appName)
                                    }
                                    NotifButton {
                                        label: "✕"
                                        hoverTint: Colors.danger
                                        hoverFill: Qt.alpha(Colors.danger, 0.15)
                                        onClicked: Notifs.forgetApp(grp.modelData.key)
                                    }
                                }
                            }

                            // ---- entries ----
                            Repeater {
                                model: grp.shown

                                Rectangle {
                                    id: entry

                                    required property var modelData
                                    // Only notifications still held by the
                                    // server can run actions; older ones are
                                    // text.
                                    readonly property var liveObj: Notifs.liveFor(modelData)
                                    readonly property int n: modelData.count ?? 1

                                    width: grpCol.width
                                    implicitHeight: entryCol.implicitHeight + 12
                                    radius: 7
                                    color: entryHover.hovered ? Colors.surface0 : "transparent"
                                    Behavior on color { ColorAnimation { duration: 110 } }

                                    HoverHandler { id: entryHover }

                                    Column {
                                        id: entryCol

                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 6
                                        anchors.leftMargin: 8
                                        spacing: 3

                                        Item {
                                            width: parent.width
                                            height: 16

                                            Text {
                                                anchors.left: parent.left
                                                anchors.right: entryMeta.left
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: entry.modelData.summary
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                color: Colors.textMain
                                            }

                                            Row {
                                                id: entryMeta
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 6

                                                // The stack count. Pill-shaped so
                                                // it reads as "this happened N
                                                // times", not as part of the text.
                                                Rectangle {
                                                    visible: entry.n > 1
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    implicitWidth: stackLbl.implicitWidth + 10
                                                    implicitHeight: 15
                                                    radius: 7
                                                    color: Qt.alpha(Colors.accent, 0.18)
                                                    Text {
                                                        id: stackLbl
                                                        anchors.centerIn: parent
                                                        text: "×" + entry.n
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 9
                                                        font.weight: Font.DemiBold
                                                        color: Colors.accent
                                                    }
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: Notifs.timeAgo(entry.modelData.time)
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    color: Colors.textFaint
                                                }
                                                // Fades in with the row instead of
                                                // appearing and disappearing, so the
                                                // time beside it never shifts.
                                                NotifButton {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    label: "✕"
                                                    opacity: entryHover.hovered ? 1 : 0
                                                    enabled: entryHover.hovered
                                                    hoverTint: Colors.danger
                                                    hoverFill: Qt.alpha(Colors.danger, 0.15)
                                                    onClicked: Notifs.forget(entry.modelData)
                                                    Behavior on opacity { NumberAnimation { duration: 110 } }
                                                }
                                            }
                                        }

                                        Text {
                                            width: parent.width
                                            visible: text !== ""
                                            text: entry.modelData.body
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 3
                                            elide: Text.ElideRight
                                            textFormat: Text.StyledText
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            color: Colors.textDim
                                        }

                                        Row {
                                            visible: entry.liveObj !== null && entry.liveObj.actions.length > 0
                                            spacing: 6
                                            topPadding: 2

                                            Repeater {
                                                model: entry.liveObj !== null ? entry.liveObj.actions : []

                                                Rectangle {
                                                    id: act
                                                    required property var modelData
                                                    implicitWidth: actLbl.implicitWidth + 18
                                                    implicitHeight: 22
                                                    radius: 6
                                                    color: actHover.hovered ? Colors.surface1 : Colors.surface0
                                                    Behavior on color { ColorAnimation { duration: 110 } }
                                                    Text {
                                                        id: actLbl
                                                        anchors.centerIn: parent
                                                        text: act.modelData.text
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 10
                                                        color: Colors.textMain
                                                    }
                                                    HoverHandler {
                                                        id: actHover
                                                        cursorShape: Qt.PointingHandCursor
                                                    }
                                                    TapHandler {
                                                        onTapped: {
                                                            act.modelData.invoke();
                                                            Notifs.forget(entry.modelData);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // A noisy app gets three rows, not the whole card.
                            NotifButton {
                                visible: grp.modelData.items.length > bellPill.perGroup
                                x: 4
                                label: grp.open ? "show less"
                                                : "show " + grp.hidden + " more"
                                tint: Colors.accent
                                onClicked: bellPill.toggleExpanded(grp.modelData.key)
                            }
                        }
                    }
                }

                // ---- ignored apps ----
                //
                // Where an ignore is undone. Without this, an app ignored by
                // a stray click could only be restored by editing the JSON.
                Column {
                    id: ignoredBlock

                    visible: Notifs.ignored.length > 0
                    width: parent.width
                    spacing: 6

                    Rectangle { width: parent.width; height: 1; color: Colors.outline }

                    NotifButton {
                        label: (bellPill.showIgnored ? "▾ " : "▸ ")
                             + "Ignored apps · " + Notifs.ignored.length
                        tint: Colors.textFaint
                        onClicked: bellPill.showIgnored = !bellPill.showIgnored
                    }

                    Text {
                        visible: bellPill.showIgnored
                        width: parent.width
                        text: "Still shown as toasts, never kept here. Click one to start keeping it again."
                        wrapMode: Text.WordWrap
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        color: Colors.textFaint
                    }

                    Flow {
                        visible: bellPill.showIgnored
                        width: parent.width
                        spacing: 5

                        Repeater {
                            model: Notifs.ignored

                            Rectangle {
                                id: ign
                                required property var modelData
                                implicitWidth: ignLbl.implicitWidth + 16
                                implicitHeight: 22
                                radius: 11
                                color: ignHover.hovered ? Qt.alpha(Colors.accent, 0.18) : Colors.surface0
                                Behavior on color { ColorAnimation { duration: 110 } }
                                Text {
                                    id: ignLbl
                                    anchors.centerIn: parent
                                    text: ign.modelData + (ignHover.hovered ? "  ↺" : "")
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    color: ignHover.hovered ? Colors.accent : Colors.textDim
                                }
                                HoverHandler {
                                    id: ignHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler { onTapped: Notifs.unignoreApp(ign.modelData) }
                            }
                        }
                    }
                }
            }
        }
    }
}
