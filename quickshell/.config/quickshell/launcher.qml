import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs

// App launcher. Standalone, bind a key to:
//   quickshell -p ~/.config/quickshell/launcher.qml
//
// Apps come from Quickshell's native DesktopEntries service (the parsed
// .desktop database) -- no rofi, no scanning, and entry.execute() spawns
// the app properly detached. Type to search, arrows to move, Enter to
// launch. Focus lives permanently in the search field; the list never
// takes it, so there is exactly one owner of the current row.
PanelWindow {
    id: launcherWindow

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-launcher"

    color: "transparent"

    // ---- search / filtering ------------------------------------------

    // Rank: name prefix beats name word-start beats name substring beats
    // description match. -1 filters out.
    function scoreEntry(entry, q) {
        const name = entry.name.toLowerCase();
        if (q === "") return 10;
        if (name.startsWith(q)) return 0;
        if (name.includes(" " + q)) return 1;
        if (name.includes(q)) return 2;
        const desc = (entry.comment ?? entry.genericName ?? "").toLowerCase();
        if (desc.includes(q)) return 3;
        return -1;
    }

    readonly property var results: {
        const q = searchField.text.toLowerCase().trim();
        return DesktopEntries.applications.values
            .filter((e) => !e.noDisplay)
            .map((e) => ({ entry: e, score: scoreEntry(e, q) }))
            .filter((r) => r.score >= 0)
            .sort((a, b) => a.score - b.score || a.entry.name.localeCompare(b.entry.name))
            .map((r) => r.entry);
    }

    function launchSelected() {
        if (appList.currentIndex < 0 || appList.currentIndex >= results.length) return;
        results[appList.currentIndex].execute();
        Qt.quit();
    }

    function moveSelection(delta) {
        if (results.length === 0) return;
        let next = appList.currentIndex + delta;
        if (next < 0) next = 0;
        if (next > results.length - 1) next = results.length - 1;
        appList.currentIndex = next;
        appList.positionViewAtIndex(next, ListView.Contain);
    }

    // ---- UI ----------------------------------------------------------

    // Click outside the card closes.
    MouseArea {
        anchors.fill: parent
        onClicked: Qt.quit()
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        // Upper third rather than dead center: the eye starts at the
        // search field, and results grow downward from it.
        y: Math.round(parent.height * 0.18)
        implicitWidth: 560
        implicitHeight: cardColumn.implicitHeight + 28
        radius: 16
        color: Colors.base
        border.width: 1
        border.color: Colors.outline

        opacity: 0
        scale: 0.975
        Component.onCompleted: { opacity = 1; scale = 1; searchField.forceActiveFocus(); }
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        // Swallow clicks so they don't reach the dismiss backdrop.
        MouseArea { anchors.fill: parent }

        Column {
            id: cardColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            // ---- search field ----
            Rectangle {
                width: parent.width
                height: 42
                radius: 10
                color: Colors.mantle
                border.width: 1
                border.color: Qt.alpha(Colors.accent, 0.7)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 9

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⌕"
                        font.pixelSize: 18
                        color: Colors.accent
                    }

                    TextInput {
                        id: searchField
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 30
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        color: Colors.textMain
                        clip: true
                        focus: true

                        onTextChanged: appList.currentIndex = results.length > 0 ? 0 : -1

                        Text {
                            visible: searchField.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search apps…"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            color: Colors.textFaint
                        }

                        Keys.onUpPressed: launcherWindow.moveSelection(-1)
                        Keys.onDownPressed: launcherWindow.moveSelection(1)
                        Keys.onPressed: (event) => {
                            switch (event.key) {
                            case Qt.Key_Escape:
                                if (searchField.text !== "") searchField.text = "";
                                else Qt.quit();
                                event.accepted = true;
                                break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                launcherWindow.launchSelected();
                                event.accepted = true;
                                break;
                            case Qt.Key_PageUp:
                                launcherWindow.moveSelection(-8);
                                event.accepted = true;
                                break;
                            case Qt.Key_PageDown:
                                launcherWindow.moveSelection(8);
                                event.accepted = true;
                                break;
                            }
                        }
                    }
                }
            }

            // ---- results ----
            ListView {
                id: appList
                width: parent.width
                height: Math.min(contentHeight, 8 * 52)
                clip: true
                spacing: 2
                model: launcherWindow.results
                currentIndex: 0
                // Focus stays in the search field; single selection owner.
                focus: false
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 120
                highlightMoveVelocity: -1

                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                Text {
                    visible: appList.count === 0
                    anchors.centerIn: parent
                    text: "No matches."
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    color: Colors.textFaint
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    // ListView.isCurrentItem only resolves on the delegate
                    // root; nested children reading it get undefined.
                    readonly property bool selected: ListView.isCurrentItem

                    width: ListView.view.width
                    height: 50
                    radius: 10
                    color: row.selected ? Colors.surface0
                         : rowMouse.containsMouse ? Qt.alpha(Colors.surface0, 0.5)
                         : "transparent"
                    Behavior on color { ColorAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: row.selected ? 26 : 0
                        radius: 2
                        color: Colors.accent
                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 13
                        anchors.rightMargin: 12
                        spacing: 11

                        Item {
                            width: 28
                            height: 28
                            anchors.verticalCenter: parent.verticalCenter

                            IconImage {
                                anchors.fill: parent
                                visible: row.modelData.icon !== ""
                                source: Quickshell.iconPath(row.modelData.icon, true)
                                asynchronous: true
                            }
                            // Fallback glyph for entries without an icon.
                            Text {
                                visible: row.modelData.icon === ""
                                anchors.centerIn: parent
                                text: "󰘔"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 18
                                color: Colors.textFaint
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28 - 11
                            spacing: 1

                            Text {
                                width: parent.width
                                text: row.modelData.name
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: row.selected ? Font.DemiBold : Font.Normal
                                color: row.selected ? Colors.textMain : Colors.textDim
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: row.modelData.comment ?? row.modelData.genericName ?? ""
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                color: Colors.textFaint
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: appList.currentIndex = row.index
                        onClicked: launcherWindow.launchSelected()
                    }
                }
            }

            // ---- footer ----
            Row {
                spacing: 14

                Repeater {
                    model: [
                        { k: "↑↓", d: "navigate" },
                        { k: "⏎", d: "launch" },
                        { k: "esc", d: "close" }
                    ]
                    delegate: Row {
                        required property var modelData
                        spacing: 5

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: hintKey.implicitWidth + 10
                            implicitHeight: 17
                            radius: 4
                            color: Colors.surface0
                            Text {
                                id: hintKey
                                anchors.centerIn: parent
                                text: parent.parent.modelData.k
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                color: Colors.textDim
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.d
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            color: Colors.textFaint
                        }
                    }
                }

                Item { width: 1; height: 1 }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: appList.count + " apps"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    color: Colors.textFaint
                }
            }
        }
    }
}
