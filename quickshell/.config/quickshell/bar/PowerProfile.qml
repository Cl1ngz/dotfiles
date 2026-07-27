import QtQuick
import Quickshell.Io
import qs

// power-profiles-daemon. Reads the current profile, click cycles
// power-saver -> balanced -> performance -> power-saver.
Pill {
    id: profilePill

    property string profile: ""

    readonly property var icons: ({
        "performance": "󰓅",
        "balanced": "󰾅",
        "power-saver": "󰾆"
    })

    icon: icons[profile] ?? "󰾅"
    tint: profile === "performance" ? Colors.accent
        : profile === "power-saver" ? Colors.warn
        : Colors.textMain

    onClicked: {
        const order = ["power-saver", "balanced", "performance"];
        const next = order[(order.indexOf(profile) + 1) % order.length];
        setProcess.command = ["powerprofilesctl", "set", next];
        setProcess.running = true;
    }

    Process {
        id: getProcess
        running: true
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: profilePill.profile = text.trim()
        }
        function refresh() { running = false; running = true; }
    }

    Process {
        id: setProcess
        onExited: getProcess.refresh()
    }

    // powerprofilesctl has no event stream worth subscribing to from
    // here; a slow poll keeps us honest if something else changes it.
    Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: getProcess.refresh()
    }
}
