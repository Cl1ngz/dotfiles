import QtQuick
import Quickshell.Io
import qs

// mpd via mpc: "  artist - title" / paused / stopped, click toggles.
// Middle click clears the queue like the waybar config did.
Pill {
    id: mpdPill

    property string track: ""
    property string state: "" // "playing" | "paused" | ""

    visible: true
    interactive: track !== ""
    icon: state === "playing" ? "" : "󰝛"
    label: track === "" ? "" : (track.length > 48 ? track.substring(0, 47) + "…" : track)
    tint: state === "playing" ? Colors.textMain : Colors.textFaint

    onClicked: (button) => {
        if (button === Qt.MiddleButton) ctlProcess.run(["mpc", "clear"]);
        else ctlProcess.run(["mpc", "toggle"]);
    }

    Process {
        id: statusProcess
        running: true
        // Line 1: track (empty when stopped), line 2: "[playing] ..." etc.
        command: ["sh", "-c", "mpc status -f '%artist% - %title%' 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split('\n');
                if (lines.length >= 2 && lines[1].startsWith('[')) {
                    mpdPill.track = lines[0];
                    mpdPill.state = lines[1].startsWith('[playing]') ? "playing" : "paused";
                } else {
                    mpdPill.track = "";
                    mpdPill.state = "";
                }
            }
        }
        function refresh() { running = false; running = true; }
    }

    Process {
        id: ctlProcess
        function run(cmd) { running = false; command = cmd; running = true; }
        onExited: statusProcess.refresh()
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: statusProcess.refresh()
    }
}
