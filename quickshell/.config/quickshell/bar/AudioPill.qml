import QtQuick
import Quickshell.Services.Pipewire
import qs

// Native pipewire. One component serves both directions:
// AudioPill { isSink: true } is the speaker, isSink: false the mic.
// Left click opens the audio panel, right click mutes, middle click
// toggles the inline percent, scroll adjusts volume.
Pill {
    id: audioPill

    property bool isSink: true
    // Set from Bar.qml; both pills share one AudioPanel.
    property var panel: null
    labelVisible: false

    readonly property var node: isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
    readonly property bool bound: node !== null && node.ready && node.audio !== null
    readonly property bool muted: bound && node.audio.muted
    readonly property int percent: bound ? Math.round(node.audio.volume * 100) : 0

    // Nodes must be tracked or their audio properties are invalid.
    PwObjectTracker { objects: audioPill.node !== null ? [audioPill.node] : [] }

    icon: {
        if (!audioPill.bound || audioPill.muted) return isSink ? "󰝟" : "󰍭";
        if (!isSink) return "󰍬";
        if (audioPill.percent >= 60) return "󰕾";
        if (audioPill.percent >= 25) return "󰖀";
        return "󰕿";
    }
    label: bound && !muted ? percent + "%" : ""
    tint: !bound || muted ? Colors.textFaint : Colors.textMain

    onClicked: (button) => {
        if (button === Qt.MiddleButton) {
            labelVisible = !labelVisible;
            return;
        }
        if (button === Qt.RightButton) {
            if (bound) node.audio.muted = !node.audio.muted;
            return;
        }
        if (panel !== null) panel.toggle(isSink ? 0 : 1);
    }

    onScrolled: (steps) => {
        if (!bound) return;
        // 2% steps for output like the waybar config, 1% for the mic.
        const step = (isSink ? 0.02 : 0.01) * steps;
        node.audio.muted = false;
        node.audio.volume = Math.max(0, Math.min(1, node.audio.volume + step));
    }
}
