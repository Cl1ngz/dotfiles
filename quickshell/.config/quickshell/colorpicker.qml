import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Colour picker. Standalone, bind a key to:
//   quickshell -p ~/.config/quickshell/colorpicker.qml
//
// Eyedropper plus an editing surface: pick a pixel off the screen, then
// nudge it, read it in hex/rgb/hsl, and copy whichever you need. Picked
// colours are kept in a history that survives restarts.
//
// The screen grab itself is hyprpicker, because the compositor is the
// only thing that can read a pixel of another window and hyprpicker is
// already the Hyprland-native way to ask. Everything after that -- the
// saturation field, the hue bar, the conversions, the history -- is
// here, so the round trip is one keypress rather than a CLI call and a
// clipboard paste.
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-colorpicker"

    color: "transparent"

    // ---- colour state ------------------------------------------------
    //
    // HSV is the source of truth, not the hex string. Round-tripping
    // through RGB on every drag loses hue whenever saturation or value
    // hits zero -- black would forget which hue you were on and the bar
    // would jump back to red.

    property real hue: 0.58      // 0..1
    property real sat: 0.62
    property real val: 0.92

    readonly property color current: Qt.hsva(hue, sat, val, 1)

    property string status: ""

    function byte(x) {
        const v = Math.round(Math.max(0, Math.min(1, x)) * 255);
        return (v < 16 ? "0" : "") + v.toString(16);
    }
    function hexOf(c) { return "#" + byte(c.r) + byte(c.g) + byte(c.b); }

    readonly property string hexText: hexOf(current)
    readonly property string rgbText:
        "rgb(" + Math.round(current.r * 255) + ", "
               + Math.round(current.g * 255) + ", "
               + Math.round(current.b * 255) + ")"

    readonly property string hslText: {
        const r = current.r, g = current.g, b = current.b;
        const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
        const l = (mx + mn) / 2;
        const d = mx - mn;
        let h = 0, s = 0;
        if (d > 0.00001) {
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
            if (mx === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
            else if (mx === g) h = ((b - r) / d + 2) / 6;
            else h = ((r - g) / d + 4) / 6;
        }
        return "hsl(" + Math.round(h * 360) + ", " + Math.round(s * 100)
             + "%, " + Math.round(l * 100) + "%)";
    }

    // Hex in, HSV out. Value and saturation of zero leave the hue
    // undefined mathematically, so the current hue is kept rather than
    // snapping the bar to red.
    function setHex(text) {
        let s = text.trim().replace(/^#/, "");
        if (s.length === 3)
            s = s[0] + s[0] + s[1] + s[1] + s[2] + s[2];
        if (!/^[0-9a-fA-F]{6}$/.test(s)) return false;

        const r = parseInt(s.slice(0, 2), 16) / 255;
        const g = parseInt(s.slice(2, 4), 16) / 255;
        const b = parseInt(s.slice(4, 6), 16) / 255;

        const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
        const d = mx - mn;
        root.val = mx;
        root.sat = mx === 0 ? 0 : d / mx;
        if (d > 0.00001) {
            if (mx === r) root.hue = ((g - b) / d + (g < b ? 6 : 0)) / 6;
            else if (mx === g) root.hue = ((b - r) / d + 2) / 6;
            else root.hue = ((r - g) / d + 4) / 6;
        }
        return true;
    }

    function copy(s) {
        Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "--", s]);
        root.status = "copied " + s;
        statusTimer.restart();
    }

    Timer { id: statusTimer; interval: 1600; onTriggered: root.status = "" }

    // ---- eyedropper ----------------------------------------------------

    property bool picking: false

    // The panel hides first. It is a layer-shell overlay with exclusive
    // keyboard focus, so leaving it up would put it between hyprpicker
    // and the pixel you are aiming at.
    function pickFromScreen() {
        if (picking) return;
        picking = true;
        root.status = "";
        hideForPick.restart();
    }

    Timer {
        id: hideForPick
        interval: 60          // one frame for the hide to reach the compositor
        onTriggered: picker.running = true
    }

    Process {
        id: picker
        command: ["sh", "-c",
            'command -v hyprpicker >/dev/null 2>&1 || { echo NOHYPRPICKER >&2; exit 127; }; ' +
            'hyprpicker -f hex -n']
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                if (v !== "" && root.setHex(v)) {
                    root.remember(root.hexText);
                    root.status = "picked " + root.hexText;
                    statusTimer.restart();
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.indexOf("NOHYPRPICKER") !== -1)
                    root.status = "hyprpicker is not installed — pacman -S hyprpicker";
            }
        }
        onExited: {
            root.picking = false;
            // Cancelling hyprpicker with Escape exits non-zero and
            // prints nothing; that is a cancel, not a failure.
        }
    }

    // ---- history --------------------------------------------------------

    property var history: []
    property bool historyLoaded: false
    readonly property string storeFile: Quickshell.statePath("colors.json")
    readonly property string storeDir: Quickshell.statePath("")

    function remember(hex) {
        const without = history.filter((h) => h.toLowerCase() !== hex.toLowerCase());
        history = [hex].concat(without).slice(0, 24);
        saveHistory();
    }

    Process {
        id: histLoad
        running: true
        command: ["sh", "-c", "cat '" + root.storeFile + "' 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const p = JSON.parse(text);
                    if (Array.isArray(p)) root.history = p;
                } catch (e) {
                    root.history = [];
                }
                root.historyLoaded = true;
            }
        }
    }

    Process {
        id: histSave
        property string pending: ""
        function write(json) {
            if (running) { pending = json; return; }
            command = ["sh", "-c",
                'mkdir -p "$1" && printf %s "$2" > "$3"', "sh",
                root.storeDir, json, root.storeFile];
            running = true;
        }
        onExited: {
            if (pending !== "") {
                const n = pending;
                pending = "";
                write(n);
            }
        }
    }

    function saveHistory() {
        if (!historyLoaded) return;   // never clobber before the load lands
        histSave.write(JSON.stringify(history));
    }

    // ---- window ----------------------------------------------------------

    Shortcut {
        sequences: ["Escape"]
        context: Qt.ApplicationShortcut
        onActivated: Qt.quit()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Qt.quit()
    }

    // ---- small shared bits ------------------------------------------------

    component Btn: Rectangle {
        id: btn
        property string label: ""
        property color tint: Colors.textDim
        signal clicked()
        implicitWidth: btnText.implicitWidth + 20
        implicitHeight: 26
        radius: 7
        color: bh.hovered ? Colors.surface1 : Colors.surface0
        Behavior on color { ColorAnimation { duration: 110 } }
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: btn.tint
        }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: btn.clicked() }
    }

    // One row: a read-only value and a copy button. Hex is editable.
    component ValueRow: Item {
        id: vrow
        property string caption: ""
        property string value: ""
        property bool editable: false
        signal committed(string text)

        height: 30

        Text {
            id: cap
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            text: vrow.caption
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            font.letterSpacing: 1
            color: Colors.textFaint
        }

        Rectangle {
            anchors.left: cap.right
            anchors.leftMargin: 6
            anchors.right: copyBtn.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            height: 26
            radius: 7
            color: Colors.mantle
            border.width: 1
            border.color: ti.activeFocus ? Qt.alpha(Colors.accent, 0.7) : Colors.outline

            TextInput {
                id: ti
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                verticalAlignment: TextInput.AlignVCenter
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                color: Colors.textMain
                readOnly: !vrow.editable
                selectByMouse: true
                selectionColor: Qt.alpha(Colors.accent, 0.35)
                // Assigned, never bound. `text: activeFocus ? text :
                // vrow.value` reads itself and loops; and a plain
                // binding would be broken by the first keystroke
                // anyway, so later external changes would stop
                // arriving. Pushing the value in explicitly handles
                // both: the field follows the colour while you drag,
                // and leaves your typing alone while you type.
                Component.onCompleted: text = vrow.value
                onAccepted: vrow.committed(text)
                onActiveFocusChanged: if (!activeFocus) text = vrow.value
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: (mouse) => {
                    if (vrow.editable) ti.forceActiveFocus();
                    mouse.accepted = false;
                }
            }

            Connections {
                target: vrow
                function onValueChanged() {
                    if (!ti.activeFocus) ti.text = vrow.value;
                }
            }
        }

        Btn {
            id: copyBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: "copy"
            onClicked: root.copy(vrow.value)
        }
    }

    // ---- card ---------------------------------------------------------------

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((root.height - height) / 2)
        implicitWidth: 460
        implicitHeight: col.implicitHeight + 32
        radius: 16
        color: Colors.base
        border.width: 1
        border.color: Colors.outline

        // Hidden while hyprpicker owns the screen.
        opacity: root.picking ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 90 } }

        MouseArea { anchors.fill: parent }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 12

            // header: swatch + hex
            Item {
                width: parent.width
                height: 44

                Rectangle {
                    id: swatch
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: 10
                    color: root.current
                    border.width: 1
                    border.color: Colors.outline
                    Behavior on color { ColorAnimation { duration: 90 } }
                }

                Column {
                    anchors.left: swatch.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: root.hexText
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: Colors.textMain
                    }
                    Text {
                        text: root.rgbText
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        color: Colors.textFaint
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Btn {
                        label: "⌖ pick"
                        tint: Colors.accent
                        onClicked: root.pickFromScreen()
                    }
                    Btn { label: "esc"; onClicked: Qt.quit() }
                }
            }

            // saturation / value field
            Rectangle {
                id: svArea
                width: parent.width
                height: 150
                radius: 8
                color: Qt.hsva(root.hue, 1, 1, 1)
                clip: true

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#ffffffff" }
                        GradientStop { position: 1; color: "#00ffffff" }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: "#00000000" }
                        GradientStop { position: 1; color: "#ff000000" }
                    }
                }

                // Ring rather than a filled dot, so the colour under it
                // stays visible while you are choosing it.
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    color: "transparent"
                    border.width: 2
                    border.color: root.val > 0.55 && root.sat < 0.6 ? "#202020" : "#ffffff"
                    x: root.sat * svArea.width - width / 2
                    y: (1 - root.val) * svArea.height - height / 2
                }

                MouseArea {
                    anchors.fill: parent
                    function apply(mx, my) {
                        root.sat = Math.max(0, Math.min(1, mx / width));
                        root.val = Math.max(0, Math.min(1, 1 - my / height));
                    }
                    onPressed: (m) => apply(m.x, m.y)
                    onPositionChanged: (m) => { if (pressed) apply(m.x, m.y); }
                }
            }

            // hue bar
            Rectangle {
                id: hueBar
                width: parent.width
                height: 20
                radius: 10
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.000; color: "#ff0000" }
                    GradientStop { position: 0.167; color: "#ffff00" }
                    GradientStop { position: 0.333; color: "#00ff00" }
                    GradientStop { position: 0.500; color: "#00ffff" }
                    GradientStop { position: 0.667; color: "#0000ff" }
                    GradientStop { position: 0.833; color: "#ff00ff" }
                    GradientStop { position: 1.000; color: "#ff0000" }
                }

                Rectangle {
                    width: 6
                    height: parent.height + 6
                    radius: 3
                    color: "transparent"
                    border.width: 2
                    border.color: "#ffffff"
                    y: -3
                    x: Math.max(0, Math.min(hueBar.width - width,
                                            root.hue * hueBar.width - width / 2))
                }

                MouseArea {
                    anchors.fill: parent
                    function apply(mx) { root.hue = Math.max(0, Math.min(1, mx / width)); }
                    onPressed: (m) => apply(m.x)
                    onPositionChanged: (m) => { if (pressed) apply(m.x); }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Colors.outline }

            ValueRow {
                width: parent.width
                caption: "HEX"
                value: root.hexText
                editable: true
                onCommitted: (t) => {
                    if (!root.setHex(t)) {
                        root.status = "not a hex colour";
                        statusTimer.restart();
                    }
                }
            }
            ValueRow { width: parent.width; caption: "RGB"; value: root.rgbText }
            ValueRow { width: parent.width; caption: "HSL"; value: root.hslText }

            Item {
                width: parent.width
                height: 26
                Btn {
                    anchors.left: parent.left
                    label: "save to history"
                    onClicked: root.remember(root.hexText)
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.status
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    color: root.status.indexOf("not ") === 0
                           || root.status.indexOf("hyprpicker") !== -1
                        ? Colors.danger : Colors.textFaint
                }
            }

            Rectangle {
                visible: root.history.length > 0
                width: parent.width
                height: 1
                color: Colors.outline
            }

            Text {
                visible: root.history.length > 0
                text: "HISTORY  ·  click to load, right-click to copy"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.letterSpacing: 1
                color: Colors.textFaint
            }

            Flow {
                visible: root.history.length > 0
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.history
                    Rectangle {
                        id: hsw
                        required property var modelData
                        width: 28
                        height: 28
                        radius: 7
                        color: modelData
                        border.width: hsw.modelData.toLowerCase() === root.hexText.toLowerCase()
                            ? 2 : 1
                        border.color: hsw.modelData.toLowerCase() === root.hexText.toLowerCase()
                            ? Colors.accent : Colors.outline
                        scale: swh.hovered ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 110 } }

                        HoverHandler { id: swh; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: root.setHex(hsw.modelData)
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: root.copy(hsw.modelData)
                        }
                    }
                }
            }

            Item {
                visible: root.history.length > 0
                width: parent.width
                height: 24
                Btn {
                    anchors.right: parent.right
                    label: "clear history"
                    tint: Colors.danger
                    onClicked: { root.history = []; root.saveHistory(); }
                }
            }
        }
    }
}
