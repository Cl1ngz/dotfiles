import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import qs

// Native BlueZ where the installed Quickshell supports it, bluetoothctl
// where it doesn't (adapter.discovering only exists in qs >= 0.3.0).
//
// The panel is a fullscreen transparent overlay PanelWindow -- the same
// pattern as the powermenu -- rather than a PopupWindow + focus grab,
// which closed on clicks inside the panel on this system. The overlay
// owns all input while open: clicks on the card work, clicks anywhere
// else close it.
Pill {
    id: btPill

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btEnabled: adapter !== null && adapter.enabled
    readonly property int connectedCount:
        Bluetooth.devices.values.filter((d) => d.connected).length

    icon: !btEnabled ? "󰂲" : connectedCount > 0 ? "󰂱" : "󰂯"
    label: btEnabled && connectedCount > 0 ? String(connectedCount) : ""
    tint: !btEnabled ? Colors.textFaint
        : connectedCount > 0 ? Colors.accent
        : Colors.textMain

    onClicked: (button) => {
        if (button === Qt.RightButton) {
            if (adapter !== null) adapter.enabled = !adapter.enabled;
            return;
        }
        overlay.visible = !overlay.visible;
    }

    // ---- version-safe device actions ---------------------------------
    // Prefer the native API; fall back to bluetoothctl when a method is
    // missing on older Quickshell builds.
    // Address of the device a pairing chain is currently running for.
    property string pairingAddress: ""

    function devicePair(d) {
        // Pairing needs an agent registered with BlueZ to answer the
        // handshake; quickshell doesn't register one, so a native pair()
        // can silently fail. bluetoothctl brings its own agent, so the
        // whole chain goes through it: pair, trust, connect.
        const addr = d.address;
        if (!/^[0-9A-Fa-f:]+$/.test(addr)) return;
        pairingAddress = addr;
        btctl.run(["sh", "-c",
            "bluetoothctl -- pair " + addr +
            " && bluetoothctl -- trust " + addr +
            " && bluetoothctl -- connect " + addr]);
    }
    function deviceForget(d) {
        try { d.forget(); }
        catch (e) { btctl.run(["bluetoothctl", "remove", d.address]); }
    }

    // Trust is what lets the DEVICE start the connection: an untrusted
    // device can only be connected while it is in pairing mode, which is
    // why headphones seemed to need re-pairing after every reboot.
    // Trusting once makes BlueZ accept its reconnect attempts forever.
    function deviceSetTrusted(d, want) {
        const addr = d.address;
        if (!/^[0-9A-Fa-f:]+$/.test(addr)) return;
        // Set via the native property when present, and always mirror it
        // through bluetoothctl so it lands in BlueZ's stored config.
        try { d.trusted = want; } catch (e) { /* fall through to cli */ }
        btctl.run(["bluetoothctl", want ? "trust" : "untrust", addr]);
    }

    // One-shot repair for devices paired before trust was being set.
    function trustAllPaired() {
        const addrs = Bluetooth.devices.values
            .filter((d) => d.paired && /^[0-9A-Fa-f:]+$/.test(d.address))
            .map((d) => d.address);
        if (addrs.length === 0) return;
        btctl.run(["sh", "-c",
            'for a in "$@"; do bluetoothctl -- trust "$a"; done', "sh"].concat(addrs));
    }

    // Real trust state, read from BlueZ rather than the QML property:
    // the property reported true for every device on this build, which
    // made the toggle show "untrust" always and hid the trust action.
    // address -> true/false
    property var trustMap: ({})

    function isTrusted(d) {
        const v = trustMap[(d.address ?? "").toUpperCase()];
        return v === undefined ? (d.trusted === true) : v;
    }

    Process {
        id: trustProbe
        command: ["sh", "-c",
            'for a in $(bluetoothctl devices Paired | awk \'{print $2}\'); do ' +
            'printf "%s=%s\n" "$a" ' +
            '"$(bluetoothctl info "$a" | awk -F": " \'/Trusted:/{print $2; exit}\')"; ' +
            'done']
        stdout: StdioCollector {
            onStreamFinished: {
                const m = ({});
                for (const line of text.trim().split('\n')) {
                    if (line === "") continue;
                    const eq = line.lastIndexOf('=');
                    if (eq === -1) continue;
                    m[line.substring(0, eq).toUpperCase()] =
                        line.substring(eq + 1).trim() === "yes";
                }
                btPill.trustMap = m;
            }
        }
        function refresh() { running = false; running = true; }
    }

    // Refresh trust state whenever the panel opens or an action finishes.
    Timer {
        id: trustSettle
        interval: 400
        onTriggered: trustProbe.refresh()
    }

    Process {
        id: btctl
        function run(cmd) { running = false; command = cmd; running = true; }
        onExited: {
            btPill.pairingAddress = "";
            trustSettle.restart();
        }
    }

    function deviceSetConnected(d, want) {
        // The connected property is the documented equivalent of
        // connect()/disconnect(); fall back to bluetoothctl if a build
        // doesn't expose it.
        if (typeof d.connected === "boolean") d.connected = want;
        else btctl.run(["bluetoothctl", want ? "connect" : "disconnect", d.address]);
    }

    // One row, used by both the paired and available sections.
    // Click: paired -> connect/disconnect toggle, unpaired -> pair.
    // Right click on a paired device forgets it.
    component DeviceRow: Rectangle {
        id: deviceRow
        required property var modelData

        width: parent.width
        height: 40
        radius: 9
        color: rowMouse.containsMouse ? Colors.surface1 : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                text: deviceRow.modelData.name
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                font.weight: deviceRow.modelData.connected ? Font.DemiBold : Font.Normal
                color: deviceRow.modelData.connected ? Colors.accent : Colors.textMain
            }
            Text {
                text: {
                    const d = deviceRow.modelData;
                    if (d.pairing || d.address === btPill.pairingAddress) return "pairing…";
                    if (d.connected) {
                        const batt = d.batteryAvailable
                            ? "  ·  " + Math.round(d.battery * 100) + "%" : "";
                        const tr = btPill.isTrusted(d) ? "" : "  ·  NOT trusted";
                        return "connected" + batt + tr;
                    }
                    if (d.paired)
                        return btPill.isTrusted(d) ? "disconnected  ·  trusted"
                                                   : "disconnected  ·  NOT trusted";
                    return "available";
                }
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                color: deviceRow.modelData.paired && !btPill.isTrusted(deviceRow.modelData)
                     ? Colors.warn
                     : deviceRow.modelData.connected ? Colors.accent : Colors.textFaint
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Trust toggle: the fix for "needs pairing mode every time".
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: deviceRow.modelData.paired
                    && (rowMouse.containsMouse || !btPill.isTrusted(deviceRow.modelData))
                implicitWidth: trustLabel.implicitWidth + 14
                implicitHeight: 20
                radius: 6
                color: trustMouse.containsMouse ? Colors.surface1
                     : btPill.isTrusted(deviceRow.modelData) ? "transparent"
                     : Qt.alpha(Colors.warn, 0.18)
                border.width: 1
                border.color: btPill.isTrusted(deviceRow.modelData)
                    ? Colors.outline : Qt.alpha(Colors.warn, 0.5)
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    id: trustLabel
                    anchors.centerIn: parent
                    text: btPill.isTrusted(deviceRow.modelData) ? "untrust" : "trust"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    color: btPill.isTrusted(deviceRow.modelData) ? Colors.textFaint : Colors.warn
                }

                MouseArea {
                    id: trustMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: btPill.deviceSetTrusted(deviceRow.modelData,
                        !btPill.isTrusted(deviceRow.modelData))
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: rowMouse.containsMouse
                text: {
                    const d = deviceRow.modelData;
                    if (d.connected) return "disconnect";
                    if (d.paired) return "connect";
                    return "pair";
                }
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                color: Colors.textDim
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (event) => {
                const d = deviceRow.modelData;
                if (event.button === Qt.RightButton) {
                    if (d.paired) btPill.deviceForget(d);
                    return;
                }
                if (d.paired) btPill.deviceSetConnected(d, !d.connected);
                else btPill.devicePair(d);
            }
        }
    }

    // Scanning: bluetoothctl with a timeout works on every Quickshell
    // version; discovered devices surface through BlueZ into
    // Bluetooth.devices either way. Auto-stops after 30s.
    Process {
        id: scanProcess
        command: ["bluetoothctl", "--timeout", "30", "scan", "on"]
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
        WlrLayershell.namespace: "quickshell-bt-panel"
        color: "transparent"
        visible: false
        exclusiveZone: 0

        onVisibleChanged: {
            if (visible) trustProbe.refresh();
            else scanProcess.running = false;
        }

        // Click anywhere outside the card closes the panel.
        MouseArea {
            anchors.fill: parent
            onClicked: overlay.visible = false
        }

        Rectangle {
            id: panelCard

            // Under the bluetooth pill: the bar spans the full screen
            // width at the top, so the pill's window coords are screen
            // coords. Clamped to the screen edge.
            x: Math.max(8, Math.min(
                btPill.mapToItem(null, 0, 0).x + btPill.width / 2 - width / 2,
                overlay.width - width - 8))
            // The overlay respects the bar's exclusive zone, so its top
            // edge is already the bottom of the bar -- only a small gap
            // is needed here, not the bar height.
            y: 6
            width: 300
            implicitHeight: panelColumn.implicitHeight + 28

            radius: 14
            color: Colors.base
            border.width: 1
            border.color: Colors.outline

            opacity: overlay.visible ? 1 : 0
            scale: overlay.visible ? 1 : 0.97
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            // Swallow clicks so they don't reach the close-on-click backdrop.
            MouseArea { anchors.fill: parent }

            Column {
                id: panelColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 10

                // ---- header: title + power switch ----
                Item {
                    width: parent.width
                    height: 26

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bluetooth"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Colors.textMain
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 20
                        radius: 10
                        color: btPill.btEnabled ? Colors.accent : Colors.surface1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 14
                            height: 14
                            radius: 7
                            anchors.verticalCenter: parent.verticalCenter
                            x: btPill.btEnabled ? parent.width - width - 3 : 3
                            color: btPill.btEnabled ? Colors.accentFg : Colors.textFaint
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (btPill.adapter !== null)
                                    btPill.adapter.enabled = !btPill.adapter.enabled;
                            }
                        }
                    }
                }

                // ---- scan row ----
                Rectangle {
                    visible: btPill.btEnabled
                    width: parent.width
                    height: 30
                    radius: 9
                    color: scanProcess.running ? Qt.alpha(Colors.accent, 0.18) : Colors.surface1
                    border.width: 1
                    border.color: scanProcess.running ? Qt.alpha(Colors.accent, 0.5) : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: scanProcess.running ? "Scanning… (click to stop)" : "Scan for devices"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        color: scanProcess.running ? Colors.accent : Colors.textMain
                    }

                    SequentialAnimation on opacity {
                        running: scanProcess.running
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: scanProcess.running = !scanProcess.running
                    }
                }

                // ---- device list: paired above the line, available below ----
                Column {
                    id: deviceColumn
                    width: parent.width
                    spacing: 4

                    // Nameless beacons (name falls back to the MAC) are hidden.
                    readonly property var named: Bluetooth.devices.values
                        .filter((d) => d.name !== "" && !/^([0-9A-F]{2}-){5}[0-9A-F]{2}$/i.test(d.name))
                    readonly property var pairedList: named
                        .filter((d) => d.paired)
                        .slice()
                        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
                    readonly property var availableList: named
                        .filter((d) => !d.paired)
                        .slice()
                        .sort((a, b) => a.name.localeCompare(b.name))

                    Text {
                        visible: !btPill.btEnabled
                        text: "Bluetooth is off."
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        color: Colors.textFaint
                    }

                    Item {
                        visible: btPill.btEnabled && deviceColumn.pairedList.length > 0
                        width: parent.width
                        height: 16

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "PAIRED"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            color: Colors.textFaint
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: deviceColumn.pairedList.some((d) => !btPill.isTrusted(d))
                            implicitWidth: taLabel.implicitWidth + 14
                            implicitHeight: 18
                            radius: 6
                            color: taMouse.containsMouse ? Qt.alpha(Colors.warn, 0.28)
                                                         : Qt.alpha(Colors.warn, 0.15)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: taLabel
                                anchors.centerIn: parent
                                text: "trust all"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                color: Colors.warn
                            }
                            MouseArea {
                                id: taMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: btPill.trustAllPaired()
                            }
                        }
                    }

                    Repeater {
                        model: btPill.btEnabled ? deviceColumn.pairedList : []
                        DeviceRow {}
                    }

                    // Divider between the paired and available sections.
                    Rectangle {
                        visible: btPill.btEnabled
                            && deviceColumn.pairedList.length > 0
                            && deviceColumn.availableList.length > 0
                        width: parent.width
                        height: 1
                        color: Colors.outline
                    }

                    Text {
                        visible: btPill.btEnabled && deviceColumn.availableList.length > 0
                        text: "AVAILABLE"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.letterSpacing: 1
                        color: Colors.textFaint
                    }

                    Repeater {
                        model: btPill.btEnabled ? deviceColumn.availableList : []
                        DeviceRow {}
                    }

                    Text {
                        visible: btPill.btEnabled
                            && deviceColumn.pairedList.length === 0
                            && deviceColumn.availableList.length === 0
                        text: "No devices. Try scanning."
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        color: Colors.textFaint
                    }
                }
            }
        }
    }
}
