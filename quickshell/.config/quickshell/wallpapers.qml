import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Wallpaper picker. Standalone like the powermenu: bind a key to
//   quickshell -p ~/.config/quickshell/wallpapers.qml
// Folders under ~/Pictures/Wallpapers are categories (tabs). Selecting
// an image runs ~/.local/bin/swall.sh <path> and quits -- the matugen
// pipeline downstream of swall.sh is untouched.
//
// No thumbnail cache: Image.sourceSize makes Qt decode each file at
// thumbnail size directly, lazily, per visible cell.
PanelWindow {
    id: pickerWindow

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-wallpapers"

    color: "transparent"

    // ---- data --------------------------------------------------------

    property var entries: []        // [{ cat, path, name }]
    property var categories: []     // unique folder names, sorted
    property int catIndex: 0

    readonly property string currentCategory:
        categories.length > 0 ? categories[catIndex] : ""
    readonly property var currentList:
        entries.filter((e) => e.cat === currentCategory)

    function cycleCategory(delta) {
        if (categories.length === 0) return;
        catIndex = (catIndex + delta + categories.length) % categories.length;
        grid.currentIndex = 0;
    }

    function applySelected() {
        if (grid.currentIndex < 0 || grid.currentIndex >= currentList.length) return;
        const path = currentList[grid.currentIndex].path;
        // Path passed as an argument, not spliced into the command
        // string, so spaces and quotes in filenames are safe.
        Quickshell.execDetached(["sh", "-c", 'exec "$HOME/.local/bin/swall.sh" "$1"', "--", path]);
        Qt.quit();
    }

    Process {
        id: listProcess
        running: true
        command: ["sh", "-c",
            'find "$HOME/Pictures/Wallpapers" -mindepth 2 -maxdepth 2 -type f ' +
            '\\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) | sort']
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                const cats = {};
                for (const line of text.split('\n')) {
                    if (line.trim() === "") continue;
                    const parts = line.split('/');
                    const cat = parts[parts.length - 2];
                    found.push({ cat: cat, path: line, name: parts[parts.length - 1] });
                    cats[cat] = true;
                }
                pickerWindow.entries = found;
                pickerWindow.categories = Object.keys(cats).sort();
                pickerWindow.catIndex = 0;
            }
        }
    }

    // ---- UI ----------------------------------------------------------

    FocusScope {
        anchors.fill: parent
        focus: true
        Component.onCompleted: forceActiveFocus()

        Keys.onPressed: (event) => {
            switch (event.key) {
            case Qt.Key_Escape:
                Qt.quit();
                event.accepted = true;
                return;
            case Qt.Key_Tab:
                pickerWindow.cycleCategory(1);
                event.accepted = true;
                return;
            case Qt.Key_Backtab:
                pickerWindow.cycleCategory(-1);
                event.accepted = true;
                return;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                pickerWindow.applySelected();
                event.accepted = true;
                return;
            case Qt.Key_Left:
                grid.moveCurrentIndexLeft();
                event.accepted = true;
                return;
            case Qt.Key_Right:
                grid.moveCurrentIndexRight();
                event.accepted = true;
                return;
            case Qt.Key_Up:
                grid.moveCurrentIndexUp();
                event.accepted = true;
                return;
            case Qt.Key_Down:
                grid.moveCurrentIndexDown();
                event.accepted = true;
                return;
            }
        }

        // Click outside the card closes.
        MouseArea {
            anchors.fill: parent
            onClicked: Qt.quit()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            implicitWidth: 960
            implicitHeight: 640
            radius: 16
            color: Colors.base
            border.width: 1
            border.color: Colors.outline

            opacity: 0
            scale: 0.975
            Component.onCompleted: { opacity = 1; scale = 1; }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }

            // Swallow clicks so they don't reach the dismiss backdrop.
            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                // ---- header: title + category tabs ----
                Item {
                    width: parent.width
                    height: 30

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰸉  Wallpapers"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: Colors.textMain
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Repeater {
                            model: pickerWindow.categories

                            Rectangle {
                                id: tab
                                required property string modelData
                                required property int index
                                readonly property bool active: pickerWindow.catIndex === index

                                width: tabLabel.implicitWidth + 22
                                height: 26
                                radius: 13
                                color: tab.active ? Colors.accent
                                     : tabMouse.containsMouse ? Colors.surface1
                                     : Qt.alpha(Colors.textMain, 0.08)
                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                Text {
                                    id: tabLabel
                                    anchors.centerIn: parent
                                    text: tab.modelData
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.weight: tab.active ? Font.DemiBold : Font.Normal
                                    color: tab.active ? Colors.accentFg : Colors.textDim
                                }

                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        pickerWindow.catIndex = tab.index;
                                        grid.currentIndex = 0;
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- thumbnail grid ----
                GridView {
                    id: grid
                    width: parent.width
                    height: parent.height - 30 - 20 - 2 * 14
                    clip: true

                    cellWidth: Math.floor(width / 3)
                    cellHeight: Math.floor(cellWidth * 9 / 16) + 8
                    model: pickerWindow.currentList
                    currentIndex: 0
                    keyNavigationWraps: true

                    Text {
                        visible: grid.count === 0
                        anchors.centerIn: parent
                        text: "No wallpapers found in ~/Pictures/Wallpapers/<category>/"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        color: Colors.textFaint
                    }

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property bool selected: grid.currentIndex === index

                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            id: frame
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 10
                            color: Colors.mantle
                            border.width: 2
                            border.color: cell.selected ? Colors.accent : "transparent"
                            scale: cell.selected ? 1.0 : 0.97
                            clip: true

                            Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: "file://" + cell.modelData.path
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                // Decode at ~2x cell size for sharpness on
                                // hidpi; this is what replaces the magick
                                // thumbnail cache.
                                sourceSize.width: 640
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            }

                            // Name strip on hover/selection.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 22
                                color: Qt.alpha(Colors.base, 0.85)
                                opacity: cell.selected || cellMouse.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    text: cell.modelData.name
                                    elide: Text.ElideMiddle
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    color: Colors.textDim
                                }
                            }
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: grid.currentIndex = cell.index
                            onClicked: pickerWindow.applySelected()
                        }
                    }
                }

                // ---- footer hints ----
                Row {
                    spacing: 14

                    Repeater {
                        model: [
                            { k: "↑↓←→", d: "navigate" },
                            { k: "⇥", d: "next category" },
                            { k: "⏎", d: "apply" },
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
                }
            }
        }
    }
}
