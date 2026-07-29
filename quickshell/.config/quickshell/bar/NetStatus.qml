import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Network pill + panel on NetworkManager (nmcli).
//
// Page 1: radio/networking switches, connected devices with IP info,
// wifi list (connect / disconnect / inline password), VPN toggles.
// Page 2: a full connection editor (GENERAL / WI-FI / SECURITY / IPV4 /
// IPV6) built on `nmcli con mod` -- loads current values, saves only
// what changed, and re-activates the connection to apply.
Pill {
    id: netPill

    // ---- state -------------------------------------------------------
    property bool wifiEnabled: true
    property bool networkingEnabled: true
    property var devices: []
    property var devInfo: ({})
    property var wifiNetworks: []
    property var savedNames: []
    property var vpns: []
    property string expandedSsid: ""
    property string busyText: ""

    // editor state
    property string editName: ""
    property string editType: ""       // wifi | ethernet | other
    property bool editWasActive: false
    property int editTab: 0
    property var origValues: ({})
    property var editValues: ({})
    property string pskShown: ""
    property string newPsk: ""

    readonly property var activeDevs: devices.filter(
        (d) => d.state === "connected" && (d.type === "wifi" || d.type === "ethernet"))
    readonly property var connectedWifi: wifiNetworks.find((n) => n.inUse) ?? null

    function terseSplit(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === '\\' && i + 1 < line.length) { cur += line[i + 1]; i++; continue; }
            if (c === ':') { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    function signalIcon(sig) {
        if (sig >= 75) return "󰤨";
        if (sig >= 50) return "󰤥";
        if (sig >= 25) return "󰤢";
        return "󰤟";
    }

    // ---- editor schema -----------------------------------------------
    // type: text | bool | choice. Bool values are nmcli yes/no strings.
    readonly property var editSchema: [
        { name: "GENERAL", fields: [
            { key: "connection.autoconnect", label: "autoconnect", type: "bool" },
            { key: "connection.autoconnect-priority", label: "priority", type: "text", hint: "0" },
            { key: "connection.metered", label: "metered", type: "choice", options: ["unknown", "yes", "no"] }
        ]},
        { name: "WI-FI", wifiOnly: true, fields: [
            { key: "802-11-wireless.bssid", label: "bssid pin", type: "text", hint: "AA:BB:CC:DD:EE:FF" },
            { key: "802-11-wireless.band", label: "band", type: "choice", options: ["", "a", "bg"] },
            { key: "802-11-wireless.cloned-mac-address", label: "cloned mac", type: "text", hint: "random | stable | MAC" },
            { key: "802-11-wireless.mtu", label: "mtu", type: "text", hint: "auto" },
            { key: "802-11-wireless.hidden", label: "hidden net", type: "bool" }
        ]},
        { name: "SECURITY", wifiOnly: true, fields: [] },
        { name: "IPV4", fields: [
            { key: "ipv4.method", label: "method", type: "choice", options: ["auto", "manual", "link-local", "shared"] },
            { key: "ipv4.addresses", label: "addresses", type: "text", hint: "192.168.1.50/24" },
            { key: "ipv4.gateway", label: "gateway", type: "text", hint: "192.168.1.1" },
            { key: "ipv4.dns", label: "dns", type: "text", hint: "1.1.1.1,9.9.9.9" },
            { key: "ipv4.ignore-auto-dns", label: "ignore auto dns", type: "bool" },
            { key: "ipv4.never-default", label: "never default rt", type: "bool" }
        ]},
        { name: "IPV6", fields: [
            { key: "ipv6.method", label: "method", type: "choice", options: ["auto", "dhcp", "manual", "disabled", "link-local"] },
            { key: "ipv6.addresses", label: "addresses", type: "text", hint: "2001:db8::5/64" },
            { key: "ipv6.gateway", label: "gateway", type: "text", hint: "" },
            { key: "ipv6.dns", label: "dns", type: "text", hint: "" }
        ]}
    ]
    readonly property var editTabs: editSchema.filter((t) => !t.wifiOnly || editType === "wifi")
    readonly property var editKeys: {
        const ks = [];
        for (const t of editSchema) for (const f of t.fields) ks.push(f.key);
        return ks;
    }

    function openEditor(name) {
        editName = name;
        editTab = 0;
        origValues = ({});
        editValues = ({});
        pskShown = "";
        newPsk = "";
        editLoad.load(name);
    }

    function setEditValue(key, value) {
        const v = Object.assign({}, editValues);
        v[key] = value;
        editValues = v;
    }

    function saveEdit() {
        const args = ["nmcli", "con", "mod", editName];
        for (const k of editKeys) {
            if (editValues[k] !== undefined && editValues[k] !== origValues[k])
                args.push(k, editValues[k]);
        }
        if (newPsk !== "")
            args.push("802-11-wireless-security.psk", newPsk);
        if (args.length === 4) { editName = ""; return; }   // nothing changed
        editSave.wasActive = editWasActive;
        editSave.conName = editName;
        busyText = "saving";
        editSave.command = args;
        editSave.running = true;
    }

    // ---- pill --------------------------------------------------------
    icon: {
        if (!networkingEnabled) return "󰖪";
        const eth = devices.find((d) => d.type === "ethernet" && d.state === "connected");
        if (eth !== undefined) return "󰈀";
        if (!wifiEnabled) return "󰖪";
        if (connectedWifi !== null) return signalIcon(connectedWifi.signal);
        return "󰖩";
    }
    label: connectedWifi !== null ? connectedWifi.ssid : ""
    toggleableLabel: true
    labelVisible: false
    tint: !networkingEnabled ? Colors.danger
        : activeDevs.length > 0 ? Colors.textMain
        : Colors.textFaint

    onClicked: (button) => {
        if (button === Qt.RightButton) {
            netAction.run(["nmcli", "radio", "wifi", wifiEnabled ? "off" : "on"], "wifi radio");
            return;
        }
        overlay.visible = !overlay.visible;
    }

    // ---- processes ---------------------------------------------------

    Process {
        id: refreshProcess
        command: ["sh", "-c",
            'nmcli radio wifi; nmcli networking; ' +
            'echo @@@; ' +
            'nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev; ' +
            'echo @@@; ' +
            'for d in $(nmcli -t -f DEVICE,TYPE,STATE dev | awk -F: \'$2~/^(ethernet|wifi)$/ && $3=="connected"{print $1}\'); do ' +
            'echo "DEV:$d"; nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS dev show "$d" 2>/dev/null; done; ' +
            'echo @@@; ' +
            'nmcli -t -f SIGNAL,IN-USE,SECURITY,SSID dev wifi list 2>/dev/null; ' +
            'echo @@@; ' +
            'nmcli -t -f NAME,TYPE,ACTIVE con show | grep -E \':(vpn|wireguard):\' ; ' +
            'echo @@@; ' +
            'nmcli -t -f NAME con show']
        stdout: StdioCollector {
            onStreamFinished: netPill.parseRefresh(text)
        }
        function refresh() { running = false; running = true; }
    }

    function parseRefresh(text) {
        const sec = text.split('@@@');

        const radios = sec[0].trim().split('\n');
        wifiEnabled = (radios[0] ?? "").trim() === "enabled";
        networkingEnabled = (radios[1] ?? "").trim() === "enabled";

        const devs = [];
        for (const line of (sec[1] ?? "").trim().split('\n')) {
            if (line === "") continue;
            const p = terseSplit(line);
            if (p.length < 3 || p[1] === "loopback") continue;
            devs.push({ dev: p[0], type: p[1], state: p[2], connection: p.slice(3).join(":") });
        }
        devices = devs;

        const info = {};
        let cur = "";
        for (const line of (sec[2] ?? "").trim().split('\n')) {
            if (line.startsWith("DEV:")) {
                cur = line.substring(4);
                info[cur] = { ips: [], gateway: "", dns: [] };
                continue;
            }
            if (cur === "") continue;
            const ci = line.indexOf(':');
            if (ci === -1) continue;
            const key = line.substring(0, ci);
            const val = line.substring(ci + 1);
            if (key.startsWith("IP4.ADDRESS")) info[cur].ips.push(val);
            else if (key.startsWith("IP4.GATEWAY") && val !== "") info[cur].gateway = val;
            else if (key.startsWith("IP4.DNS")) info[cur].dns.push(val);
        }
        devInfo = info;

        const bySsid = {};
        for (const line of (sec[3] ?? "").trim().split('\n')) {
            if (line === "") continue;
            const p = terseSplit(line);
            if (p.length < 4) continue;
            const ssid = p.slice(3).join(":");
            if (ssid === "") continue;
            const entry = { signal: parseInt(p[0]) || 0, inUse: p[1] === "*", security: p[2], ssid: ssid };
            const prev = bySsid[ssid];
            if (prev === undefined || entry.inUse || entry.signal > prev.signal)
                bySsid[ssid] = Object.assign(entry, { inUse: entry.inUse || (prev?.inUse ?? false) });
        }
        wifiNetworks = Object.values(bySsid).sort(
            (a, b) => (b.inUse - a.inUse) || (b.signal - a.signal));

        const vlist = [];
        for (const line of (sec[4] ?? "").trim().split('\n')) {
            if (line === "") continue;
            const p = terseSplit(line);
            if (p.length < 3) continue;
            vlist.push({ name: p[0], type: p[1], active: p[2] === "yes" });
        }
        vpns = vlist;

        savedNames = (sec[5] ?? "").trim().split('\n')
            .filter((l) => l !== "")
            .map((l) => terseSplit(l)[0]);
    }

    Process {
        id: netAction
        function run(cmd, label) {
            running = false;
            netPill.busyText = label;
            command = cmd;
            running = true;
        }
        function runSh(script, args, label) {
            run(["sh", "-c", script, "--"].concat(args), label);
        }
        onExited: {
            netPill.busyText = "";
            refreshProcess.refresh();
        }
    }

    // Load every property of one connection; keep only schema keys.
    Process {
        id: editLoad
        function load(name) {
            running = false;
            command = ["nmcli", "-t", "con", "show", name];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const vals = {};
                let ctype = "";
                let active = false;
                for (const line of text.split('\n')) {
                    const ci = line.indexOf(':');
                    if (ci === -1) continue;
                    const key = line.substring(0, ci);
                    const val = line.substring(ci + 1).replace(/\\:/g, ":");
                    if (key === "connection.type")
                        ctype = val === "802-11-wireless" ? "wifi"
                              : val === "802-3-ethernet" ? "ethernet" : val;
                    if (key === "GENERAL.STATE") active = val === "activated";
                    if (netPill.editKeys.indexOf(key) !== -1)
                        vals[key] = (val === "--" ? "" : val);
                }
                netPill.editType = ctype;
                netPill.editWasActive = active;
                netPill.origValues = vals;
                netPill.editValues = Object.assign({}, vals);
            }
        }
    }

    Process {
        id: pskLoad
        function load(name) {
            running = false;
            command = ["nmcli", "-s", "-g", "802-11-wireless-security.psk", "con", "show", name];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: netPill.pskShown = text.trim() === "" ? "(none)" : text.trim()
        }
    }

    Process {
        id: editSave
        property bool wasActive: false
        property string conName: ""
        onExited: (code) => {
            netPill.busyText = "";
            if (code === 0) {
                if (wasActive)
                    netAction.runSh('nmcli con up id "$1"', [conName], "re-applying");
                netPill.editName = "";
            }
            refreshProcess.refresh();
        }
    }

    Timer { id: rescanSettle; interval: 3000; onTriggered: refreshProcess.refresh() }
    Timer {
        interval: 10000
        repeat: true
        running: overlay.visible
        onTriggered: refreshProcess.refresh()
    }

    // ---- shared mini components --------------------------------------

    component SectionLabel: Text {
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        font.letterSpacing: 1
        color: Colors.textFaint
    }

    component MiniSwitch: Rectangle {
        property bool checked: false
        signal toggled()
        width: 36
        height: 18
        radius: 9
        color: checked ? Colors.accent : Colors.surface1
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: 12; height: 12; radius: 6
            anchors.verticalCenter: parent.verticalCenter
            x: parent.checked ? parent.width - width - 3 : 3
            color: parent.checked ? Colors.accentFg : Colors.textFaint
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: parent.toggled() }
    }

    component MiniButton: Rectangle {
        property string label: ""
        property color tint: Colors.textMain
        signal clicked()
        implicitWidth: mbLabel.implicitWidth + 16
        implicitHeight: 22
        radius: 6
        color: mbMouse.containsMouse ? Colors.surface1 : Colors.surface0
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: mbLabel
            anchors.centerIn: parent
            text: parent.label
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            color: parent.tint
        }
        MouseArea { id: mbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
    }

    component MiniInput: Rectangle {
        property alias text: mi.text
        property alias echoMode: mi.echoMode
        property string placeholder: ""
        signal submitted()
        signal edited()
        height: 26
        radius: 7
        color: Colors.mantle
        border.width: 1
        border.color: mi.activeFocus ? Qt.alpha(Colors.accent, 0.7) : Colors.outline
        Behavior on border.color { ColorAnimation { duration: 130 } }
        TextInput {
            id: mi
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: Colors.textMain
            clip: true
            onTextEdited: parent.edited()
            Keys.onReturnPressed: parent.submitted()
            Keys.onEnterPressed: parent.submitted()
            Text {
                visible: mi.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.placeholder
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                color: Colors.textFaint
            }
        }
    }

    // ---- panel -------------------------------------------------------

    PanelWindow {
        id: overlay
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-network"
        color: "transparent"
        visible: false
        exclusiveZone: 0

        onVisibleChanged: {
            if (visible) refreshProcess.refresh();
            else { netPill.expandedSsid = ""; netPill.editName = ""; }
        }

        MouseArea { anchors.fill: parent; onClicked: overlay.visible = false }

        Rectangle {
            id: panelCard
            x: Math.max(8, Math.min(
                netPill.mapToItem(null, 0, 0).x + netPill.width / 2 - width / 2,
                overlay.width - width - 8))
            y: 6
            width: netPill.editName !== "" ? 470 : 400
            implicitHeight: Math.min(panelFlick.contentHeight + 28, overlay.height - 40)
            radius: 14
            color: Colors.base
            border.width: 1
            border.color: Colors.outline
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            opacity: overlay.visible ? 1 : 0
            scale: overlay.visible ? 1 : 0.97
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            Flickable {
                id: panelFlick
                anchors.fill: parent
                anchors.margins: 14
                contentHeight: netPill.editName !== "" ? editorColumn.implicitHeight : panelColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // ==========================================================
                // PAGE 2: connection editor
                // ==========================================================
                Column {
                    id: editorColumn
                    visible: netPill.editName !== ""
                    width: panelFlick.width
                    spacing: 10

                    Item {
                        width: parent.width
                        height: 24
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            MiniButton { label: "< back"; onClicked: netPill.editName = "" }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: netPill.editName
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: Colors.textMain
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: netPill.busyText !== ""
                            text: netPill.busyText
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            color: Colors.warn
                        }
                    }

                    // tab bar
                    Row {
                        spacing: 4
                        Repeater {
                            model: netPill.editTabs
                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool active: netPill.editTab === index
                                implicitWidth: tabT.implicitWidth + 18
                                implicitHeight: 24
                                radius: 8
                                color: active ? Colors.accent
                                     : tabM.containsMouse ? Colors.surface1
                                     : Colors.surface0
                                Behavior on color { ColorAnimation { duration: 130 } }
                                Text {
                                    id: tabT
                                    anchors.centerIn: parent
                                    text: parent.modelData.name
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.weight: parent.active ? Font.DemiBold : Font.Normal
                                    color: parent.active ? Colors.accentFg : Colors.textDim
                                }
                                MouseArea {
                                    id: tabM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: netPill.editTab = parent.index
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Colors.outline }

                    // field rows for the active tab
                    Repeater {
                        model: (netPill.editTabs[netPill.editTab] ?? ({ fields: [] })).fields

                        Item {
                            id: fieldRow
                            required property var modelData
                            readonly property string fval: netPill.editValues[modelData.key] ?? ""
                            readonly property bool dirty: fval !== (netPill.origValues[modelData.key] ?? "")

                            width: editorColumn.width
                            height: 30

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 130
                                text: fieldRow.modelData.label + (fieldRow.dirty ? " *" : "")
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: fieldRow.dirty ? Colors.warn : Colors.textDim
                            }

                            // bool
                            MiniSwitch {
                                visible: fieldRow.modelData.type === "bool"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: fieldRow.fval === "yes"
                                onToggled: netPill.setEditValue(fieldRow.modelData.key,
                                    fieldRow.fval === "yes" ? "no" : "yes")
                            }

                            // choice (click cycles)
                            MiniButton {
                                visible: fieldRow.modelData.type === "choice"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                label: fieldRow.fval === "" ? "(default)" : fieldRow.fval
                                onClicked: {
                                    const opts = fieldRow.modelData.options;
                                    const idx = opts.indexOf(fieldRow.fval);
                                    netPill.setEditValue(fieldRow.modelData.key,
                                        opts[(idx + 1) % opts.length]);
                                }
                            }

                            // text
                            MiniInput {
                                visible: fieldRow.modelData.type === "text"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 138
                                placeholder: fieldRow.modelData.hint ?? ""
                                text: fieldRow.fval
                                onEdited: netPill.setEditValue(fieldRow.modelData.key, text)
                            }
                        }
                    }

                    // SECURITY tab body (psk)
                    Column {
                        visible: (netPill.editTabs[netPill.editTab] ?? ({})).name === "SECURITY"
                        width: parent.width
                        spacing: 8

                        Row {
                            spacing: 8
                            MiniButton {
                                label: "reveal current psk"
                                onClicked: pskLoad.load(netPill.editName)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: netPill.pskShown
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: Colors.textMain
                            }
                        }
                        SectionLabel { text: "NEW PSK (blank = keep current)" }
                        MiniInput {
                            width: parent.width
                            echoMode: TextInput.Password
                            placeholder: "new password"
                            text: netPill.newPsk
                            onEdited: netPill.newPsk = text
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Colors.outline }

                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        MiniButton { label: "cancel"; onClicked: netPill.editName = "" }
                        MiniButton {
                            label: netPill.editWasActive ? "save & re-apply" : "save"
                            tint: Colors.accent
                            onClicked: netPill.saveEdit()
                        }
                    }

                    Text {
                        text: "* modified -- changes persist in this connection profile"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        color: Colors.textFaint
                    }
                }

                // ==========================================================
                // PAGE 1: overview
                // ==========================================================
                Column {
                    id: panelColumn
                    visible: netPill.editName === ""
                    width: panelFlick.width
                    spacing: 10

                    Item {
                        width: parent.width
                        height: 24
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Network"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Colors.textMain
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: netPill.busyText !== ""
                                text: netPill.busyText
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                color: Colors.warn
                            }
                        }
                    }

                    Row {
                        spacing: 18
                        Row {
                            spacing: 7
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Wi-Fi"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: Colors.textDim
                            }
                            MiniSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: netPill.wifiEnabled
                                onToggled: netAction.run(
                                    ["nmcli", "radio", "wifi", netPill.wifiEnabled ? "off" : "on"], "wifi radio")
                            }
                        }
                        Row {
                            spacing: 7
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Networking"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: Colors.textDim
                            }
                            MiniSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: netPill.networkingEnabled
                                onToggled: netAction.run(
                                    ["nmcli", "networking", netPill.networkingEnabled ? "off" : "on"], "networking")
                            }
                        }
                    }

                    SectionLabel { visible: netPill.activeDevs.length > 0; text: "CONNECTED" }

                    Repeater {
                        model: netPill.activeDevs

                        Rectangle {
                            id: devRow
                            required property var modelData
                            readonly property var info: netPill.devInfo[modelData.dev]
                                ?? ({ ips: [], gateway: "", dns: [] })

                            width: panelColumn.width
                            implicitHeight: devCol.implicitHeight + 20
                            radius: 10
                            color: Colors.mantle
                            border.width: 1
                            border.color: Colors.outline

                            Column {
                                id: devCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 4

                                Item {
                                    width: parent.width
                                    height: 16
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 7
                                        Text {
                                            text: devRow.modelData.type === "ethernet" ? "󰈀" : "󰖩"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            color: Colors.accent
                                        }
                                        Text {
                                            text: devRow.modelData.connection + "  \u00b7  " + devRow.modelData.dev
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: Colors.textMain
                                        }
                                    }
                                    MiniButton {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: "edit"
                                        onClicked: netPill.openEditor(devRow.modelData.connection)
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: "ip  " + (devRow.info.ips.join(", ") || "\u2014")
                                        + "\ngw  " + (devRow.info.gateway || "\u2014")
                                        + "\ndns " + (devRow.info.dns.join(", ") || "\u2014")
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    lineHeight: 1.3
                                    color: Colors.textDim
                                }
                            }
                        }
                    }

                    Item {
                        visible: netPill.wifiEnabled
                        width: parent.width
                        height: 16
                        SectionLabel { anchors.verticalCenter: parent.verticalCenter; text: "WI-FI NETWORKS" }
                        MiniButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "rescan"
                            onClicked: {
                                netAction.run(["nmcli", "dev", "wifi", "rescan"], "scanning");
                                rescanSettle.restart();
                            }
                        }
                    }

                    Repeater {
                        model: netPill.wifiEnabled ? netPill.wifiNetworks : []

                        Rectangle {
                            id: wifiRow
                            required property var modelData
                            readonly property bool secured:
                                modelData.security !== "" && modelData.security !== "--"
                            readonly property bool known:
                                netPill.savedNames.indexOf(modelData.ssid) !== -1
                            readonly property bool askingPassword:
                                netPill.expandedSsid === modelData.ssid

                            width: panelColumn.width
                            implicitHeight: wifiCol.implicitHeight + 16
                            radius: 9
                            color: modelData.inUse ? Qt.alpha(Colors.accent, 0.10)
                                 : wifiMouse.containsMouse ? Colors.surface0
                                 : "transparent"
                            border.width: modelData.inUse ? 1 : 0
                            border.color: Qt.alpha(Colors.accent, 0.4)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on implicitHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Column {
                                id: wifiCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 6

                                Item {
                                    width: parent.width
                                    height: 18
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        Text {
                                            text: netPill.signalIcon(wifiRow.modelData.signal)
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 13
                                            color: wifiRow.modelData.inUse ? Colors.accent : Colors.textDim
                                        }
                                        Text {
                                            text: wifiRow.modelData.ssid
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            font.weight: wifiRow.modelData.inUse ? Font.DemiBold : Font.Normal
                                            color: wifiRow.modelData.inUse ? Colors.accent : Colors.textMain
                                        }
                                        Text {
                                            visible: wifiRow.secured
                                            text: "󰌾"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            color: Colors.textFaint
                                        }
                                    }
                                    Row {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        MiniButton {
                                            visible: wifiRow.known && wifiMouse.containsMouse
                                            label: "edit"
                                            onClicked: netPill.openEditor(wifiRow.modelData.ssid)
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: wifiMouse.containsMouse || wifiRow.modelData.inUse
                                            text: wifiRow.modelData.inUse ? "disconnect"
                                                : wifiRow.known ? "connect"
                                                : wifiRow.secured ? "pass\u2026" : "connect"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            color: Colors.textFaint
                                        }
                                    }
                                }

                                Row {
                                    visible: wifiRow.askingPassword
                                    width: parent.width
                                    spacing: 6
                                    MiniInput {
                                        id: passInput
                                        width: parent.width - 70
                                        echoMode: TextInput.Password
                                        placeholder: "password"
                                        onSubmitted: passGo.clicked()
                                    }
                                    MiniButton {
                                        id: passGo
                                        anchors.verticalCenter: passInput.verticalCenter
                                        label: "join"
                                        tint: Colors.accent
                                        onClicked: {
                                            if (passInput.text === "") return;
                                            netAction.runSh(
                                                'nmcli dev wifi connect "$1" password "$2"',
                                                [wifiRow.modelData.ssid, passInput.text], "connecting");
                                            passInput.text = "";
                                            netPill.expandedSsid = "";
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: wifiMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                z: -1
                                onClicked: {
                                    const m = wifiRow.modelData;
                                    if (m.inUse) {
                                        netAction.runSh('nmcli con down id "$1"', [m.ssid], "disconnecting");
                                    } else if (wifiRow.known || !wifiRow.secured) {
                                        netAction.runSh(
                                            'nmcli con up id "$1" 2>/dev/null || nmcli dev wifi connect "$1"',
                                            [m.ssid], "connecting");
                                    } else {
                                        netPill.expandedSsid = wifiRow.askingPassword ? "" : m.ssid;
                                    }
                                }
                            }
                        }
                    }

                    SectionLabel { text: "VPN" }

                    Text {
                        visible: netPill.vpns.length === 0
                        text: "No VPN profiles in NetworkManager.\nImport one: nmcli con import type wireguard file <conf>"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        lineHeight: 1.3
                        color: Colors.textFaint
                    }

                    Repeater {
                        model: netPill.vpns

                        Item {
                            required property var modelData
                            width: panelColumn.width
                            height: 26

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Text {
                                    text: parent.parent.modelData.name
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                    color: parent.parent.modelData.active ? Colors.accent : Colors.textMain
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.parent.modelData.type
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    color: Colors.textFaint
                                }
                            }

                            MiniSwitch {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: parent.modelData.active
                                onToggled: netAction.runSh(
                                    parent.modelData.active
                                        ? 'nmcli con down id "$1"'
                                        : 'nmcli con up id "$1"',
                                    [parent.modelData.name],
                                    parent.modelData.active ? "vpn down" : "vpn up")
                            }
                        }
                    }
                }
            }
        }
    }
}
