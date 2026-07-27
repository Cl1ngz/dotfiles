import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// RAM and CPU as ONE grouped pill. Left click opens the monitor panel
// (graphs + temps for CPU / RAM / GPU), middle click opens btop,
// right click toggles the inline percentages.
Rectangle {
    id: sysStats

    // ---- data ----
    property int cpuPercent: 0
    property int memPercent: 0
    property string memDetail: ""
    property int cpuTemp: -1
    property int gpuPercent: -1
    property int gpuTemp: -1
    property string gpuVram: ""
    property int igpuPercent: -1
    property int igpuTemp: -1
    property bool showLabels: false

    // Rolling usage histories for the sparklines (last 40 samples).
    property var cpuHistory: []
    property var memHistory: []
    property var gpuHistory: []
    property var igpuHistory: []

    // Previous /proc/stat sample for the usage delta.
    property real prevTotal: 0
    property real prevIdle: 0

    function statTint(percent) {
        if (percent >= 80) return Colors.danger;
        if (percent >= 50) return Colors.warn;
        return Colors.textMain;
    }

    function pushHistory(list, value) {
        const next = list.slice(-39);
        next.push(value);
        return next;
    }

    // ---- the grouped pill (same look as Pill.qml, two stats inside) ----
    anchors.verticalCenter: parent.verticalCenter
    implicitHeight: 28
    implicitWidth: statsRow.implicitWidth + 20
    radius: 12
    color: pillMouse.containsMouse ? Colors.base : Qt.alpha(Colors.textMain, 0.10)
    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Row {
        id: statsRow
        anchors.centerIn: parent
        spacing: 8

        component StatPair: Row {
            property string icon: ""
            property int value: 0
            spacing: 5
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.icon
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 15
                color: sysStats.statTint(parent.value)
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                visible: sysStats.showLabels
                anchors.verticalCenter: parent.verticalCenter
                text: parent.value + "%"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                font.weight: Font.Bold
                color: sysStats.statTint(parent.value)
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        StatPair { icon: "󰍛"; value: sysStats.memPercent }

        Rectangle {
            width: 1
            height: 14
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.alpha(Colors.textMain, 0.15)
        }

        StatPair { icon: "󰻠"; value: sysStats.cpuPercent }
    }

    // Hover underline, same as Pill.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: pillMouse.containsMouse ? parent.width - 10 : 0
        height: 2
        radius: 1
        color: Colors.accent
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: pillMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: (event) => {
            if (event.button === Qt.MiddleButton) {
                monitorProcess.running = false;
                monitorProcess.running = true;
            } else if (event.button === Qt.RightButton) {
                sysStats.showLabels = !sysStats.showLabels;
            } else {
                overlay.visible = !overlay.visible;
            }
        }
    }

    Process {
        id: monitorProcess
        command: ["kitty", "--start-as=fullscreen", "--title", "btop", "sh", "-c", "btop"]
    }

    // ---- polling ----
    // One process gathers everything, section-separated. GPU and temp
    // probes only run while the panel is open; the pill itself only
    // needs cpu/mem. nvidia-smi missing or failing just yields an empty
    // section and the GPU block hides.
    Process {
        id: pollProcess
        running: true
        command: ["sh", "-c",
            "head -n1 /proc/stat; " +
            "grep -E '^(MemTotal|MemAvailable)' /proc/meminfo; " +
            "echo @@@; " +
            (overlay.visible
                ? "for h in /sys/class/hwmon/*; do " +
                  "case \"$(cat $h/name 2>/dev/null)\" in coretemp|k10temp|zenpower) " +
                  "head -c-1 $h/temp1_input 2>/dev/null; break;; esac; done; " +
                  "echo; echo @@@; " +
                  "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null; " +
                  "echo @@@; " +
                  "for c in /sys/class/drm/card?; do " +
                  "[ \"$(cat $c/device/vendor 2>/dev/null)\" = 0x1002 ] || continue; " +
                  "cat $c/device/gpu_busy_percent 2>/dev/null; break; done; " +
                  "for h in /sys/class/hwmon/*; do " +
                  "[ \"$(cat $h/name 2>/dev/null)\" = amdgpu ] || continue; " +
                  "cat $h/temp1_input 2>/dev/null; break; done"
                : "echo; echo @@@")
        ]
        stdout: StdioCollector {
            onStreamFinished: sysStats.parsePoll(text)
        }
        function refresh() { running = false; running = true; }
    }

    function parsePoll(text) {
        const sections = text.split('@@@');
        const lines = sections[0].trim().split('\n');

        // cpu  user nice system idle iowait irq softirq ...
        const cpu = lines[0].trim().split(/\s+/).slice(1).map(Number);
        const idle = cpu[3] + (cpu[4] ?? 0);
        const total = cpu.reduce((a, b) => a + b, 0);
        const dTotal = total - prevTotal;
        const dIdle = idle - prevIdle;
        if (prevTotal > 0 && dTotal > 0)
            cpuPercent = Math.round(100 * (dTotal - dIdle) / dTotal);
        prevTotal = total;
        prevIdle = idle;

        let memTotal = 0, memAvail = 0;
        for (let i = 1; i < lines.length; i++) {
            const kb = parseInt(lines[i].split(/\s+/)[1]);
            if (lines[i].startsWith("MemTotal")) memTotal = kb;
            else if (lines[i].startsWith("MemAvailable")) memAvail = kb;
        }
        if (memTotal > 0) {
            memPercent = Math.round(100 * (memTotal - memAvail) / memTotal);
            memDetail = ((memTotal - memAvail) / 1048576).toFixed(1)
                + " / " + (memTotal / 1048576).toFixed(1) + " GB";
        }

        // temp section (millidegrees) and gpu section ("util, temp")
        const tempRaw = parseInt((sections[1] ?? "").trim());
        cpuTemp = isNaN(tempRaw) ? -1 : Math.round(tempRaw / 1000);

        const gpuLine = (sections[2] ?? "").trim();
        const gpuParts = gpuLine.split(',').map((s) => parseInt(s));
        if (gpuParts.length >= 2 && !isNaN(gpuParts[0])) {
            gpuPercent = gpuParts[0];
            gpuTemp = isNaN(gpuParts[1]) ? -1 : gpuParts[1];
            // memory.used / memory.total arrive in MiB
            gpuVram = (gpuParts.length >= 4 && !isNaN(gpuParts[2]) && !isNaN(gpuParts[3]))
                ? (gpuParts[2] / 1024).toFixed(1) + " / " + (gpuParts[3] / 1024).toFixed(1) + " GB"
                : "";
        } else {
            gpuPercent = -1;
            gpuTemp = -1;
            gpuVram = "";
        }

        // AMD iGPU: line 0 = busy %, line 1 = temp in millidegrees.
        const igpuLines = (sections[3] ?? "").trim().split('\n');
        const igpuBusy = parseInt(igpuLines[0]);
        const igpuTempRaw = parseInt(igpuLines[1]);
        igpuPercent = isNaN(igpuBusy) ? -1 : igpuBusy;
        igpuTemp = isNaN(igpuTempRaw) ? -1 : Math.round(igpuTempRaw / 1000);

        if (overlay.visible) {
            cpuHistory = pushHistory(cpuHistory, cpuPercent);
            memHistory = pushHistory(memHistory, memPercent);
            if (gpuPercent >= 0) gpuHistory = pushHistory(gpuHistory, gpuPercent);
            if (igpuPercent >= 0) igpuHistory = pushHistory(igpuHistory, igpuPercent);
        }
    }

    Timer {
        // 1s while the panel is open, lazy 5s for just the pill.
        interval: overlay.visible ? 1000 : 5000
        repeat: true
        running: true
        onTriggered: pollProcess.refresh()
    }

    // ==================================================================
    // Monitor panel (same overlay pattern as the bluetooth panel)
    // ==================================================================

    // A bar-graph sparkline: newest sample on the right.
    component Sparkline: Item {
        id: spark
        property var values: []
        property color barColor: Colors.accent

        height: 36
        clip: true

        Row {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            spacing: 1

            Repeater {
                model: spark.values

                Rectangle {
                    required property int modelData
                    anchors.bottom: parent.bottom
                    width: Math.max(2, (spark.width - 39) / 40)
                    height: Math.max(2, spark.height * modelData / 100)
                    radius: 1
                    color: spark.barColor
                    opacity: 0.9
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    component StatBlock: Column {
        property string title: ""
        property int percent: 0
        property int temp: -1
        property string detail: ""
        property var history: []

        width: parent.width
        spacing: 4

        Item {
            width: parent.width
            height: 16

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.title
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.letterSpacing: 1
                color: Colors.textFaint
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    visible: parent.parent.parent.detail !== ""
                    text: parent.parent.parent.detail
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    color: Colors.textFaint
                }
                Text {
                    visible: parent.parent.parent.temp >= 0
                    text: parent.parent.parent.temp + "°C"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    color: parent.parent.parent.temp >= 80 ? Colors.danger
                         : parent.parent.parent.temp >= 65 ? Colors.warn
                         : Colors.textDim
                }
                Text {
                    text: parent.parent.parent.percent + "%"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: sysStats.statTint(parent.parent.parent.percent)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 40
            radius: 8
            color: Qt.alpha(Colors.textMain, 0.05)
            border.width: 1
            border.color: Colors.outline

            Sparkline {
                anchors.fill: parent
                anchors.margins: 3
                values: parent.parent.history
                barColor: sysStats.statTint(parent.parent.percent)
            }
        }
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
        WlrLayershell.namespace: "quickshell-sysmon"
        color: "transparent"
        visible: false
        exclusiveZone: 0

        onVisibleChanged: {
            if (visible) pollProcess.refresh();
        }

        MouseArea {
            anchors.fill: parent
            onClicked: overlay.visible = false
        }

        Rectangle {
            id: panelCard

            x: Math.max(8, Math.min(
                sysStats.mapToItem(null, 0, 0).x + sysStats.width / 2 - width / 2,
                overlay.width - width - 8))
            // The overlay respects the bar's exclusive zone; its top edge
            // is already the bottom of the bar.
            y: 6
            width: 330
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

            MouseArea { anchors.fill: parent }

            Column {
                id: panelColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                Text {
                    text: "System"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Colors.textMain
                }

                StatBlock {
                    title: "CPU"
                    percent: sysStats.cpuPercent
                    temp: sysStats.cpuTemp
                    history: sysStats.cpuHistory
                }

                StatBlock {
                    title: "MEMORY"
                    percent: sysStats.memPercent
                    detail: sysStats.memDetail
                    history: sysStats.memHistory
                }

                StatBlock {
                    visible: sysStats.gpuPercent >= 0
                    title: "GPU · NVIDIA"
                    percent: sysStats.gpuPercent
                    temp: sysStats.gpuTemp
                    detail: sysStats.gpuVram
                    history: sysStats.gpuHistory
                }

                StatBlock {
                    visible: sysStats.igpuPercent >= 0
                    title: "GPU · AMD (INTEGRATED)"
                    percent: sysStats.igpuPercent
                    temp: sysStats.igpuTemp
                    history: sysStats.igpuHistory
                }

                Text {
                    text: "middle click the pill for btop"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    color: Colors.textFaint
                }
            }
        }
    }
}
