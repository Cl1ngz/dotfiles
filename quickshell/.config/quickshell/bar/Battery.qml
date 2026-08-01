import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs

// Battery pill + panel. Native UPower for state/percentage/time; the
// charge limit is a sysfs threshold, which needs root, so writes go
// through pkexec (a polkit agent must be running).
Pill {
    id: batteryPill

    readonly property var device: UPower.displayDevice
    readonly property bool present: device.ready && device.isLaptopBattery
    readonly property int percent: Math.round(device.percentage * 100)

    // chargingNow = actively filling; pluggedIn also covers full / held at a
    // threshold while plugged in.
    readonly property bool chargingNow: device.state === UPowerDeviceState.Charging
    readonly property bool pluggedIn: chargingNow
        || device.state === UPowerDeviceState.PendingCharge
        || device.state === UPowerDeviceState.FullyCharged

    // Seconds. Guarded with ?? so a build lacking these just hides them.
    readonly property int secsToEmpty: device.timeToEmpty ?? 0
    readonly property int secsToFull: device.timeToFull ?? 0
    readonly property real rateW: device.changeRate ?? 0
    readonly property real healthPct: (device.healthPercentage ?? 0)

    function fmtTime(sec) {
        if (!sec || sec <= 0) return "";
        const h = Math.floor(sec / 3600);
        const m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    readonly property string timeText: {
        if (!present) return "";
        if (chargingNow) {
            // timeToFull extrapolates to 100% and knows nothing about the
            // charge threshold, so scale it to the limit we will actually
            // stop at: remaining-to-limit / remaining-to-full.
            const lim = (limitValue > 0 && limitValue < 100) ? limitValue : 100;
            if (percent >= lim) return "at charge limit";
            const scale = (lim - percent) / Math.max(1, 100 - percent);
            const t = fmtTime(Math.round(secsToFull * scale));
            if (t === "") return "";
            return lim < 100 ? t + " until " + lim + "%" : t + " until full";
        }
        if (pluggedIn) return "on AC power";
        const t = fmtTime(secsToEmpty);
        return t === "" ? "" : t + " remaining";
    }

    visible: present
    toggleableLabel: true

    icon: {
        if (pluggedIn) return chargingNow ? "󰂄" : "󰚥";
        if (percent >= 90) return "󰁹";
        if (percent >= 70) return "󰂁";
        if (percent >= 45) return "󰁾";
        if (percent >= 20) return "󰁼";
        return "󰁺";
    }
    label: percent + "%"
    tint: pluggedIn ? Colors.accent
        : percent <= 15 ? Colors.danger
        : percent <= 30 ? Colors.warn
        : Colors.textMain

    onClicked: (button) => {
        if (button === Qt.LeftButton) overlay.visible = !overlay.visible;
    }

    SequentialAnimation on opacity {
        running: batteryPill.present && !batteryPill.pluggedIn && batteryPill.percent <= 15
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
    }

    // ---- charge threshold (sysfs) ------------------------------------

    property string limitPath: ""
    property int limitValue: -1
    property string lastError: ""

    property bool limitWritable: false

    Process {
        id: limitRead
        running: true
        // Vendor drivers disagree on the filename; take the first that exists.
        command: ["sh", "-c",
            'for f in /sys/class/power_supply/BAT*/charge_control_end_threshold ' +
            '/sys/class/power_supply/BAT*/charge_stop_threshold; do ' +
            '[ -f "$f" ] || continue; echo "$f"; cat "$f"; ' +
            '[ -w "$f" ] && echo writable || echo readonly; break; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');
                if (lines.length >= 2) {
                    batteryPill.limitPath = lines[0];
                    batteryPill.limitValue = parseInt(lines[1]);
                    batteryPill.limitWritable = (lines[2] ?? "") === "writable";
                } else {
                    batteryPill.limitPath = "";
                    batteryPill.limitValue = -1;
                    batteryPill.limitWritable = false;
                }
            }
        }
        function refresh() { running = false; running = true; }
    }

    property bool limitBusy: false

    Process {
        id: limitWrite

        // Prefer a plain write: with the udev rule installed the file is
        // group-writable and no authentication happens at all.
        //
        // Otherwise fall back to pkexec with --disable-internal-agent.
        // That flag matters: without it, when no graphical polkit agent
        // is running, pkexec silently prompts for a password on the
        // TERMINAL that launched quickshell. Unanswered prompts pile up
        // and pam_faillock locks the account. With the flag it fails
        // immediately and the error is shown in this panel instead.
        function apply(v) {
            if (batteryPill.limitPath === "" || batteryPill.limitBusy) return;
            batteryPill.lastError = "";
            batteryPill.limitBusy = true;
            running = false;
            // Also record the choice for battery-charge-limit.service,
            // which re-applies it at boot (the kernel resets the sysfs
            // value every time).
            // echo, not printf %s: the sysfs write needs its trailing
            // newline. Without it the driver returns EINVAL and the
            // write silently does nothing.
            command = ["sh", "-c",
                'echo "$1" > "$HOME/.config/battery-charge-limit"; ' +
                'if [ -w "$2" ]; then echo "$1" > "$2"; ' +
                'else pkexec --disable-internal-agent /bin/sh -c ' +
                '\'echo "$1" > "$2"\' sh "$1" "$2"; fi',
                "sh", String(v), batteryPill.limitPath];
            running = true;
        }

        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "")
                batteryPill.lastError = text.trim().split('\n')[0]
        }

        onExited: (code) => {
            batteryPill.limitBusy = false;
            if (code !== 0 && batteryPill.lastError === "")
                batteryPill.lastError = code === 127
                    ? "no polkit agent -- install the udev rule (see notes)"
                    : "failed (exit " + code + ")";
            limitRead.refresh();
        }
    }

    // ---- panel -------------------------------------------------------

    component StatLine: Item {
        property string k: ""
        property string v: ""
        property color tone: Colors.textMain
        width: parent.width
        height: 17
        visible: v !== ""
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.k
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            color: Colors.textFaint
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.v
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: parent.tone
        }
    }

    PanelWindow {
        id: overlay
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-battery"
        color: "transparent"
        visible: false
        exclusiveZone: 0

        onVisibleChanged: if (visible) limitRead.refresh()

        MouseArea { anchors.fill: parent; onClicked: overlay.visible = false }

        Rectangle {
            id: panelCard
            x: Math.max(8, Math.min(
                batteryPill.mapToItem(null, 0, 0).x + batteryPill.width / 2 - width / 2,
                overlay.width - width - 8))
            y: 6
            width: 300
            implicitHeight: col.implicitHeight + 28
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
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 9

                // ---- headline ----
                Row {
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: batteryPill.icon
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 22
                        color: batteryPill.tint
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: batteryPill.percent + "%"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            color: Colors.textMain
                        }
                        Text {
                            visible: batteryPill.timeText !== ""
                            text: batteryPill.timeText
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            color: batteryPill.pluggedIn ? Colors.accent : Colors.textDim
                        }
                    }
                }

                // ---- charge bar ----
                Rectangle {
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Colors.surface0

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * batteryPill.percent / 100
                        height: parent.height
                        radius: 3
                        color: batteryPill.tint
                        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }

                    // Marker showing where charging will stop.
                    Rectangle {
                        visible: batteryPill.limitValue > 0 && batteryPill.limitValue < 100
                        x: parent.width * batteryPill.limitValue / 100 - 1
                        width: 2
                        height: 12
                        radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        color: Colors.warn
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Colors.outline }

                StatLine {
                    k: "state"
                    v: batteryPill.chargingNow ? "charging"
                     : batteryPill.pluggedIn ? "plugged in" : "on battery"
                    tone: batteryPill.pluggedIn ? Colors.accent : Colors.textMain
                }
                StatLine {
                    k: batteryPill.chargingNow ? "power in" : "power draw"
                    v: batteryPill.rateW > 0 ? batteryPill.rateW.toFixed(1) + " W" : ""
                }
                StatLine {
                    k: "health"
                    v: batteryPill.healthPct > 0 ? Math.round(batteryPill.healthPct) + "%" : ""
                    tone: batteryPill.healthPct > 0 && batteryPill.healthPct < 70
                        ? Colors.warn : Colors.textMain
                }

                Rectangle { width: parent.width; height: 1; color: Colors.outline }

                // ---- charge limit ----
                Text {
                    text: "CHARGE LIMIT"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.letterSpacing: 1
                    color: Colors.textFaint
                }

                Text {
                    visible: batteryPill.limitPath === ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "This machine exposes no charge threshold in sysfs."
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    color: Colors.textFaint
                }

                Row {
                    visible: batteryPill.limitPath !== ""
                    spacing: 5
                    opacity: batteryPill.limitBusy ? 0.5 : 1
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    Repeater {
                        model: [60, 70, 80, 90, 100]

                        Rectangle {
                            required property int modelData
                            readonly property bool current: batteryPill.limitValue === modelData

                            implicitWidth: 44
                            implicitHeight: 24
                            radius: 7
                            color: current ? Colors.accent
                                 : lmMouse.containsMouse ? Colors.surface1
                                 : Colors.surface0
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData + "%"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.weight: parent.current ? Font.DemiBold : Font.Normal
                                color: parent.current ? Colors.accentFg : Colors.textDim
                            }

                            MouseArea {
                                id: lmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !batteryPill.limitBusy
                                onClicked: limitWrite.apply(parent.modelData)
                            }
                        }
                    }
                }

                Text {
                    visible: batteryPill.limitPath !== "" && batteryPill.limitValue > 0
                    text: "charging stops at " + batteryPill.limitValue + "%"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    color: Colors.textDim
                }

                Text {
                    visible: batteryPill.lastError !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: batteryPill.lastError
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    color: Colors.danger
                }

                Text {
                    visible: batteryPill.limitPath !== "" && !batteryPill.limitWritable
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "read-only: install the udev rule for passwordless writes"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    color: Colors.textFaint
                }
            }
        }
    }
}
