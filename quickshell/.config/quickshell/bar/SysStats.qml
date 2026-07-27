import QtQuick
import Quickshell.Io
import qs

// CPU and memory in one component with one shared poll -- they had the
// same interval, same click action, and same warning states in waybar,
// so splitting them into two files would just duplicate the plumbing.
Row {
    id: sysStats

    spacing: 4
    anchors.verticalCenter: parent.verticalCenter

    property int cpuPercent: 0
    property int memPercent: 0
    property string memDetail: ""

    // Previous /proc/stat sample for the usage delta.
    property real prevTotal: 0
    property real prevIdle: 0

    function statTint(percent) {
        if (percent >= 80) return Colors.danger;
        if (percent >= 50) return Colors.warn;
        return Colors.textMain;
    }

    Pill {
        toggleableLabel: true
        labelVisible: false
        icon: "󰍛"
        label: sysStats.memPercent + "%"
        tint: sysStats.statTint(sysStats.memPercent)
        onClicked: sysStats.openMonitor()
    }

    Pill {
        toggleableLabel: true
        labelVisible: false
        icon: "󰻠"
        label: sysStats.cpuPercent + "%"
        tint: sysStats.statTint(sysStats.cpuPercent)
        onClicked: sysStats.openMonitor()
    }

    function openMonitor() {
        monitorProcess.running = false;
        monitorProcess.running = true;
    }

    Process {
        id: monitorProcess
        command: ["kitty", "--start-as=fullscreen", "--title", "btop", "sh", "-c", "btop"]
    }

    Process {
        id: pollProcess
        running: true
        command: ["sh", "-c", "head -n1 /proc/stat; grep -E '^(MemTotal|MemAvailable)' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');

                // cpu  user nice system idle iowait irq softirq ...
                const cpu = lines[0].trim().split(/\s+/).slice(1).map(Number);
                const idle = cpu[3] + (cpu[4] ?? 0);
                const total = cpu.reduce((a, b) => a + b, 0);
                const dTotal = total - sysStats.prevTotal;
                const dIdle = idle - sysStats.prevIdle;
                if (sysStats.prevTotal > 0 && dTotal > 0)
                    sysStats.cpuPercent = Math.round(100 * (dTotal - dIdle) / dTotal);
                sysStats.prevTotal = total;
                sysStats.prevIdle = idle;

                // MemTotal / MemAvailable in kB
                let memTotal = 0, memAvail = 0;
                for (let i = 1; i < lines.length; i++) {
                    const kb = parseInt(lines[i].split(/\s+/)[1]);
                    if (lines[i].startsWith("MemTotal")) memTotal = kb;
                    else if (lines[i].startsWith("MemAvailable")) memAvail = kb;
                }
                if (memTotal > 0) {
                    sysStats.memPercent = Math.round(100 * (memTotal - memAvail) / memTotal);
                    sysStats.memDetail = ((memTotal - memAvail) / 1048576).toFixed(1)
                        + "GB/" + (memTotal / 1048576).toFixed(1) + "GB";
                }
            }
        }
        function refresh() { running = false; running = true; }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: pollProcess.refresh()
    }
}
