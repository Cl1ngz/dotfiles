import QtQuick
import Quickshell.Io
import qs

// Brightness. brightnessctl is the one tool kept: sysfs writes need
// root, brightnessctl has the udev rules for it. Scroll to adjust.
// Hidden when there is no backlight (desktop monitors).
Pill {
    id: backlightPill

    property int percent: -1

    visible: percent >= 0
    toggleableLabel: true
    labelVisible: false
    label: percent + "%"
    icon: {
        if (percent >= 80) return "󰃠";
        if (percent >= 60) return "󰃟";
        if (percent >= 40) return "󰃞";
        if (percent >= 20) return "󰃝";
        return "󰃜";
    }

    onScrolled: (steps) => setProcess.run(steps > 0 ? "+5%" : "5%-")

    Process {
        id: getProcess
        running: true
        // -m: DEVICE,CLASS,CURRENT,PERCENT%,MAX -- field 4 is percent.
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | head -n1 | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text.trim());
                backlightPill.percent = isNaN(value) ? -1 : value;
            }
        }
        function refresh() { running = false; running = true; }
    }

    Process {
        id: setProcess
        function run(delta) {
            running = false;
            command = ["brightnessctl", "-q", "s", delta];
            running = true;
        }
        onExited: getProcess.refresh()
    }

    // Catch changes made elsewhere (fn keys handled by the compositor).
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: getProcess.refresh()
    }
}
