import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Brightness. brightnessctl is the one tool kept: sysfs writes need
// root, brightnessctl has the udev rules for it.
//
// Left click opens a slider, scroll adjusts in 5% steps, right click
// toggles the inline percent. Hidden when there is no backlight.
Pill {
    id: backlightPill

    property int percent: -1

    // While dragging the slider, percent is set optimistically and the
    // external poll is suppressed -- otherwise a 5s refresh landing
    // mid-drag would yank the handle back to a stale value.
    property bool dragging: false
    // Latest value the drag wants written; -1 when nothing is pending.
    property int pendingSet: -1

    // Never go to 0 from the slider: on many panels that is a black
    // screen with no way back except the keys.
    readonly property int minPercent: 1

    // ---- night light (hyprsunset) ------------------------------------
    //
    // 6500K is daylight, i.e. "off". Anything lower is a warmer screen.
    // hyprsunset holds the gamma control for as long as it runs, so
    // turning night light off means stopping it, not setting 6500.
    //
    // Which control path works depends on the hyprsunset version: newer
    // ones take live commands over hyprctl, older ones only read the
    // temperature from their own argv. Both are tried, IPC first, so a
    // version that supports it changes temperature without the brief
    // flash a restart causes.
    readonly property int dayTemp: 6500
    property int nightTemp: dayTemp
    readonly property bool nightOn: nightTemp < dayTemp
    readonly property string nightStateFile: Quickshell.statePath("hyprsunset-temp")

    // Warm tint on the pill itself, so night light is visible without
    // opening the panel.
    tint: nightOn ? Colors.warn : Colors.textMain

    function setNightTemp(k) {
        nightTemp = k;
        if (k >= dayTemp)
            nightOff.running = true;
        else
            nightApply.run(k);
    }

    Process {
        id: nightApply
        function run(k) {
            running = false;
            command = ["sh", "-c", 'k="$1"; f="$2"; ' + 'if hyprctl hyprsunset temperature "$k" >/dev/null 2>&1; then :; ' + 'else pkill -x hyprsunset; sleep 0.2; ' +
                // setsid: the daemon has to outlive this shell, and the
                // Process object that spawned it.
                'setsid hyprsunset -t "$k" >/dev/null 2>&1 & fi; ' + 'mkdir -p "$(dirname "$f")" && printf %s "$k" > "$f"', "sh", String(k), backlightPill.nightStateFile];
            running = true;
        }
    }

    Process {
        id: nightOff
        command: ["sh", "-c", 'hyprctl hyprsunset identity >/dev/null 2>&1; ' + 'pkill -x hyprsunset; rm -f "$1"', "sh", backlightPill.nightStateFile]
    }

    // On start, night light counts as on only if hyprsunset is actually
    // running AND we have a temperature recorded for it -- a hyprsunset
    // started by something else sitting at identity is not night light.
    Process {
        id: nightLoad
        running: true
        command: ["sh", "-c", 'if pgrep -x hyprsunset >/dev/null 2>&1 && [ -f "$1" ]; ' + 'then cat "$1"; else echo 6500; fi', "sh", backlightPill.nightStateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const k = parseInt(text.trim());
                backlightPill.nightTemp = isNaN(k) ? backlightPill.dayTemp : k;
            }
        }
    }

    function applyPercent(p) {
        const v = Math.max(minPercent, Math.min(100, Math.round(p)));
        percent = v;
        pendingSet = v;
        flushTimer.start();
    }

    // Dragging generates far more updates than brightnessctl can keep
    // up with, so writes are coalesced: the newest pending value is
    // flushed whenever no write is in flight.
    Timer {
        id: flushTimer
        interval: 40
        repeat: true
        running: false
        onTriggered: {
            if (backlightPill.pendingSet < 0) {
                if (!backlightPill.dragging)
                    stop();
                return;
            }
            if (setProcess.running)
                return;
            const v = backlightPill.pendingSet;
            backlightPill.pendingSet = -1;
            setProcess.runAbsolute(v);
        }
    }

    visible: percent >= 0
    toggleableLabel: true
    labelVisible: false
    label: percent + "%"
    icon: {
        if (percent >= 80)
            return "󰃠";
        if (percent >= 60)
            return "󰃟";
        if (percent >= 40)
            return "󰃞";
        if (percent >= 20)
            return "󰃝";
        return "󰃜";
    }

    onClicked: button => {
        if (button === Qt.LeftButton)
            overlay.visible = !overlay.visible;
    }

    onScrolled: steps => setProcess.run(steps > 0 ? "+5%" : "5%-")

    Process {
        id: getProcess
        running: true
        // -m: DEVICE,CLASS,CURRENT,PERCENT%,MAX -- field 4 is percent.
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | head -n1 | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                // A reply that arrives mid-drag is already stale.
                if (backlightPill.dragging)
                    return;
                const value = parseInt(text.trim());
                backlightPill.percent = isNaN(value) ? -1 : value;
            }
        }
        function refresh() {
            running = false;
            running = true;
        }
    }

    Process {
        id: setProcess
        // Relative step, used by scroll and the keys.
        function run(delta) {
            running = false;
            command = ["brightnessctl", "-q", "s", delta];
            running = true;
        }
        // Absolute percent, used by the slider.
        function runAbsolute(v) {
            running = false;
            command = ["brightnessctl", "-q", "s", v + "%"];
            running = true;
        }
        onExited: if (!backlightPill.dragging)
            getProcess.refresh()
    }

    // Catch changes made elsewhere (fn keys handled by the compositor).
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: if (!backlightPill.dragging)
            getProcess.refresh()
    }

    // ==================================================================
    // Slider popup
    //
    // Same overlay pattern as the bluetooth / audio / system panels: a
    // fullscreen transparent PanelWindow with the card drawn under the
    // pill. It owns input while open, so the slider gets its drags and
    // a click anywhere else closes it.
    // ==================================================================

    PanelWindow {
        id: overlay

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-backlight"
        color: "transparent"
        visible: false
        exclusiveZone: 0

        onVisibleChanged: if (visible)
            getProcess.refresh()

        MouseArea {
            anchors.fill: parent
            onClicked: overlay.visible = false
        }

        Rectangle {
            id: panelCard

            x: Math.max(8, Math.min(backlightPill.mapToItem(null, 0, 0).x + backlightPill.width / 2 - width / 2, overlay.width - width - 8))
            // The overlay respects the bar's exclusive zone, so its top
            // edge is already the bottom of the bar.
            y: 6
            width: 260
            implicitHeight: cardColumn.implicitHeight + 28

            radius: 14
            color: Colors.base
            border.width: 1
            border.color: Colors.outline

            opacity: overlay.visible ? 1 : 0
            scale: overlay.visible ? 1 : 0.97
            transformOrigin: Item.Top
            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: cardColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 10

                Item {
                    width: parent.width
                    height: 18

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Brightness"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Colors.textMain
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: backlightPill.percent + "%"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Colors.accent
                    }
                }

                // Track + fill + handle. Click or drag anywhere on it.
                Item {
                    width: parent.width
                    height: 18

                    Rectangle {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Colors.surface0

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * Math.max(0, backlightPill.percent) / 100
                            height: parent.height
                            radius: 3
                            color: Colors.accent
                            // No animation while dragging: the handle has
                            // to track the pointer exactly.
                            Behavior on width {
                                enabled: !backlightPill.dragging
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: track.width * Math.max(0, backlightPill.percent) / 100 - width / 2
                        width: 14
                        height: 14
                        radius: 7
                        color: Colors.accentFg
                        border.width: 2
                        border.color: Colors.accent
                        scale: sliderMouse.pressed ? 1.15 : 1.0
                        Behavior on scale {
                            NumberAnimation {
                                duration: 110
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on x {
                            enabled: !backlightPill.dragging
                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        id: sliderMouse
                        anchors.fill: parent
                        onPressed: m => {
                            backlightPill.dragging = true;
                            backlightPill.applyPercent(m.x / width * 100);
                        }
                        onPositionChanged: m => {
                            if (pressed)
                                backlightPill.applyPercent(m.x / width * 100);
                        }
                        onReleased: {
                            backlightPill.dragging = false;
                            // Let the queue drain, then resync from the
                            // hardware in case it clamped the value.
                            resyncTimer.restart();
                        }
                        onWheel: w => backlightPill.applyPercent(backlightPill.percent + (w.angleDelta.y > 0 ? 5 : -5))
                    }
                }

                // Quick presets: faster than aiming for a small target.
                Row {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: [10, 25, 50, 75, 100]

                        Rectangle {
                            required property int modelData
                            readonly property bool current: Math.abs(backlightPill.percent - modelData) <= 2

                            width: (cardColumn.width - 24) / 5
                            height: 22
                            radius: 6
                            color: current ? Colors.accent : presetMouse.containsMouse ? Colors.surface1 : Colors.surface0
                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.weight: parent.current ? Font.DemiBold : Font.Normal
                                color: parent.current ? Colors.accentFg : Colors.textDim
                            }

                            MouseArea {
                                id: presetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: backlightPill.applyPercent(parent.modelData)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Colors.outline
                }

                // ---- night light ----
                Item {
                    width: parent.width
                    height: 20

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "NIGHT LIGHT"
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
                            anchors.verticalCenter: parent.verticalCenter
                            text: backlightPill.nightOn ? backlightPill.nightTemp + "K" : "off"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            color: backlightPill.nightOn ? Colors.warn : Colors.textFaint
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 17
                            radius: 9
                            color: backlightPill.nightOn ? Colors.warn : Colors.surface1
                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }

                            Rectangle {
                                width: 11
                                height: 11
                                radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                x: backlightPill.nightOn ? parent.width - width - 3 : 3
                                color: backlightPill.nightOn ? Colors.base : Colors.textFaint
                                Behavior on x {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                // Toggling on returns to the last warm
                                // temperature, or 4500K the first time.
                                onClicked: backlightPill.setNightTemp(backlightPill.nightOn ? backlightPill.dayTemp : 4500)
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: [5000, 4500, 4000, 3400, 2700]

                        Rectangle {
                            required property int modelData
                            readonly property bool current: backlightPill.nightTemp === modelData

                            width: (cardColumn.width - 24) / 5
                            height: 22
                            radius: 6
                            color: current ? Colors.warn : tempMouse.containsMouse ? Colors.surface1 : Colors.surface0
                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.weight: parent.current ? Font.DemiBold : Font.Normal
                                color: parent.current ? Colors.base : Colors.textDim
                            }

                            MouseArea {
                                id: tempMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: backlightPill.setNightTemp(parent.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: resyncTimer
        interval: 300
        onTriggered: getProcess.refresh()
    }
}
