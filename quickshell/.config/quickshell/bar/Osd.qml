import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs

// On-screen display for volume and brightness, top-center under the bar.
//
// Volume needs no keybind changes: the sink is watched natively, so any
// change from any source (keys, headset buttons, the bar pill) shows
// the OSD. Brightness has no native watcher, so kernel uevents from the
// backlight class are streamed via `udevadm monitor` and the percent is
// read after each one.
PanelWindow {
    id: osd

    property string kind: "volume"      // "volume" | "brightness"
    property int value: 0
    property bool muted: false
    property bool active: false
    // Property-change signals fire once at startup while everything
    // initializes; don't show an OSD for those.
    property bool ready: false

    anchors.top: true
    margins.top: 8
    implicitWidth: 300
    implicitHeight: 52
    exclusiveZone: 0
    visible: active || card.opacity > 0.01

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    color: "transparent"

    function show(newKind, newValue, newMuted) {
        if (!ready) return;
        kind = newKind;
        value = Math.max(0, Math.min(100, newValue));
        muted = newMuted === true;
        active = true;
        hideTimer.restart();
    }

    Timer { interval: 1500; running: true; onTriggered: osd.ready = true }
    Timer { id: hideTimer; interval: 1200; onTriggered: osd.active = false }

    // ---- volume: native pipewire watch -------------------------------

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: osd.sink !== null ? [osd.sink] : [] }

    Connections {
        target: osd.sink !== null ? osd.sink.audio : null

        function onVolumeChanged() {
            osd.show("volume", Math.round(osd.sink.audio.volume * 100), osd.sink.audio.muted);
        }
        function onMutedChanged() {
            osd.show("volume", Math.round(osd.sink.audio.volume * 100), osd.sink.audio.muted);
        }
    }

    // ---- brightness: udev backlight events ---------------------------

    Process {
        id: backlightMonitor
        running: true
        command: ["udevadm", "monitor", "-u", "-s", "backlight"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("change") !== -1) brightnessDebounce.restart();
            }
        }
    }

    // Several uevents can land per keypress; read once after they settle.
    Timer {
        id: brightnessDebounce
        interval: 60
        onTriggered: brightnessRead.refresh()
    }

    Process {
        id: brightnessRead
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | head -n1 | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = parseInt(text.trim());
                if (!isNaN(p)) osd.show("brightness", p, false);
            }
        }
        function refresh() { running = false; running = true; }
    }

    // ---- the card ----------------------------------------------------

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 14
        color: Colors.base
        border.width: 1
        border.color: Colors.outline

        opacity: osd.active ? 1 : 0
        scale: osd.active ? 1 : 0.95
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        // Click hides early.
        MouseArea {
            anchors.fill: parent
            onClicked: osd.active = false
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                text: {
                    if (osd.kind === "brightness") {
                        if (osd.value >= 80) return "󰃠";
                        if (osd.value >= 40) return "󰃟";
                        return "󰃞";
                    }
                    if (osd.muted) return "󰝟";
                    if (osd.value >= 60) return "󰕾";
                    if (osd.value >= 25) return "󰖀";
                    return "󰕿";
                }
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 17
                color: osd.muted && osd.kind === "volume" ? Colors.textFaint : Colors.accent
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            // Track + fill
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 22 - 12 - 40 - 12
                height: 6
                radius: 3
                color: Colors.surface0

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * osd.value / 100
                    height: parent.height
                    radius: 3
                    color: osd.muted && osd.kind === "volume" ? Colors.textFaint : Colors.accent
                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                horizontalAlignment: Text.AlignRight
                text: osd.muted && osd.kind === "volume" ? "muted" : osd.value + "%"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                font.weight: Font.Bold
                color: osd.muted && osd.kind === "volume" ? Colors.textFaint : Colors.textMain
            }
        }
    }
}
