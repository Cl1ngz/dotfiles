import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs

// The audio panel, shared by the speaker and mic pills.
//
// Native pipewire: output/input device lists with draggable volume
// sliders and mute, and a per-application mixer (every live stream,
// individually adjustable and mutable). Subprocesses only where
// quickshell has no API: wpctl to change the default device, pactl for
// card profiles (A2DP vs headset duplex, codec-variant profiles).
PanelWindow {
    id: overlay

    // Set from Bar.qml: the pill the panel hangs under.
    property var anchorItem: null

    function toggle(startTab) {
        if (startTab !== undefined && !visible) tab = startTab;
        visible = !visible;
    }

    property int tab: 0
    readonly property var tabNames: ["OUTPUT", "INPUT", "MIXER", "PROFILES"]

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-audio"
    color: "transparent"
    visible: false
    exclusiveZone: 0

    onVisibleChanged: if (visible) cardsProcess.refresh()

    // ---- node sets ---------------------------------------------------
    readonly property var sinks: Pipewire.nodes.values.filter(
        (n) => n.isSink && !n.isStream && n.audio !== null)
    readonly property var sources: Pipewire.nodes.values.filter(
        (n) => !n.isSink && !n.isStream && n.audio !== null)
    readonly property var streams: Pipewire.nodes.values.filter(
        (n) => n.isStream && n.audio !== null)

    // Bind everything we render; audio props are only valid while bound.
    PwObjectTracker {
        objects: overlay.sinks.concat(overlay.sources).concat(overlay.streams)
    }

    function nodeLabel(n) {
        return n.properties?.["application.name"]
            ?? n.description ?? n.nickname ?? n.name;
    }

    // Second line for mixer rows. Two windows of the same browser share
    // application.name, so show media.name (tab / stream title) and, only
    // when another live stream carries the same label, a process id to
    // break the tie -- e.g. a normal vs a private window.
    function streamSub(n) {
        const p = n.properties ?? ({});
        const label = nodeLabel(n);
        const media = p["media.name"] ?? p["media.title"] ?? "";
        const parts = [];
        if (media !== "" && media !== label) parts.push(media);
        if (streams.filter((s) => nodeLabel(s) === label).length > 1) {
            const pid = p["application.process.id"] ?? "";
            parts.push(pid !== "" ? "pid " + pid : "#" + n.id);
        }
        return parts.join("  \u00b7  ");
    }

    // ---- default device + profiles via cli ---------------------------
    property string lastError: ""

    Process {
        id: audioAction
        function run(cmd) {
            overlay.lastError = "";
            running = false;
            command = cmd;
            running = true;
        }
        // Positional args: device names never get spliced into the script.
        function runSh(script, args) {
            run(["sh", "-c", script, "--"].concat(args));
        }
        // Failures used to vanish silently; surface them in the header.
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") overlay.lastError = text.trim().split('\n')[0]
        }
        onExited: cardsProcess.refresh()
    }

    // Switching the default does not by itself move audio that is already
    // playing -- that is why picking a device could look like it did
    // nothing. Set the default, then move every live stream across.
    function setDefaultSink(n) {
        audioAction.runSh(
            'wpctl set-default "$1" 2>/dev/null || pactl set-default-sink "$2"; ' +
            'for i in $(pactl list short sink-inputs | cut -f1); do ' +
            'pactl move-sink-input "$i" "$2" >/dev/null 2>&1; done',
            [String(n.id), n.name]);
    }

    function setDefaultSource(n) {
        audioAction.runSh(
            'wpctl set-default "$1" 2>/dev/null || pactl set-default-source "$2"; ' +
            'for i in $(pactl list short source-outputs | cut -f1); do ' +
            'pactl move-source-output "$i" "$2" >/dev/null 2>&1; done',
            [String(n.id), n.name]);
    }

    property var cards: []   // { name, description, active, profiles: [{name, desc, available}] }
    property string expandedCard: ""

    Process {
        id: cardsProcess
        command: ["pactl", "--format=json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const raw = JSON.parse(text);
                    const out = [];
                    for (const c of raw) {
                        const profs = [];
                        const p = c.profiles ?? {};
                        if (Array.isArray(p)) {
                            for (const pr of p)
                                profs.push({ name: pr.name, desc: pr.description ?? pr.name,
                                             available: pr.available !== false });
                        } else {
                            for (const key of Object.keys(p))
                                profs.push({ name: key, desc: p[key].description ?? key,
                                             available: p[key].available !== false });
                        }
                        out.push({
                            name: c.name,
                            description: c.properties?.["device.description"] ?? c.name,
                            active: c.active_profile ?? "",
                            profiles: profs.filter((x) => x.available && x.name !== "off")
                        });
                    }
                    overlay.cards = out;
                } catch (e) {
                    overlay.cards = [];
                }
            }
        }
        function refresh() { running = false; running = true; }
    }

    // ---- shared pieces -----------------------------------------------

    component SectionLabel: Text {
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        font.letterSpacing: 1
        color: Colors.textFaint
    }

    // Draggable volume bar + mute + percent for one pipewire node.
    component VolRow: Item {
        id: volRow
        property var node: null
        property string label: ""
        property bool isDefault: false
        property bool selectable: false     // click name to set default
        property string sublabel: ""
        signal makeDefault()

        readonly property bool ok: node !== null && node.ready && node.audio !== null
        readonly property real vol: ok ? node.audio.volume : 0
        readonly property bool muted: ok && node.audio.muted

        width: parent.width
        height: sublabel !== "" ? 56 : 44
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Column {
            anchors.fill: parent
            spacing: 4

            Item {
                width: parent.width
                height: 15

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        visible: volRow.isDefault
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u2713"
                        font.pixelSize: 10
                        color: Colors.accent
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: volRow.label
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.weight: volRow.isDefault ? Font.DemiBold : Font.Normal
                        color: volRow.muted ? Colors.textFaint
                             : volRow.isDefault ? Colors.accent
                             : pickMouse.containsMouse ? Colors.accent : Colors.textMain
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, volRow.width - 130)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pickMouse.containsMouse
                        text: "set default"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        color: Colors.textFaint
                    }
                }

                // The whole left half of the header row is the target --
                // clicking the few pixels of the name text was too fiddly.
                MouseArea {
                    id: pickMouse
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width - 90
                    enabled: volRow.selectable && !volRow.isDefault
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: volRow.makeDefault()
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: volRow.muted ? "muted" : Math.round(volRow.vol * 100) + "%"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: volRow.muted ? Colors.textFaint : Colors.textDim
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 16
                        radius: 5
                        color: muteMouse.containsMouse ? Colors.surface1
                             : volRow.muted ? Qt.alpha(Colors.danger, 0.2) : Colors.surface0
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "M"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: volRow.muted ? Colors.danger : Colors.textFaint
                        }
                        MouseArea {
                            id: muteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: if (volRow.ok) volRow.node.audio.muted = !volRow.node.audio.muted
                        }
                    }
                }
            }

            Text {
                visible: volRow.sublabel !== ""
                width: parent.width
                text: volRow.sublabel
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                color: Colors.textFaint
            }

            // The slider: click or drag anywhere on the track.
            Item {
                width: parent.width
                height: 14

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
                        width: parent.width * Math.min(1, volRow.vol)
                        height: parent.height
                        radius: 3
                        color: volRow.muted ? Colors.textFaint : Colors.accent
                        Behavior on width { NumberAnimation { duration: 80 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Rectangle {
                    visible: volRow.ok
                    anchors.verticalCenter: parent.verticalCenter
                    x: track.width * Math.min(1, volRow.vol) - width / 2
                    width: 12
                    height: 12
                    radius: 6
                    color: volRow.muted ? Colors.textFaint : Colors.accentFg
                    border.width: 2
                    border.color: volRow.muted ? Colors.surface1 : Colors.accent
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: (m) => apply(m.x)
                    onPositionChanged: (m) => { if (pressed) apply(m.x); }
                    onWheel: (w) => {
                        if (!volRow.ok) return;
                        const d = w.angleDelta.y > 0 ? 0.02 : -0.02;
                        volRow.node.audio.volume =
                            Math.max(0, Math.min(1, volRow.node.audio.volume + d));
                    }
                    function apply(px) {
                        if (!volRow.ok) return;
                        volRow.node.audio.muted = false;
                        volRow.node.audio.volume = Math.max(0, Math.min(1, px / width));
                    }
                }
            }
        }
    }

    MouseArea { anchors.fill: parent; onClicked: overlay.visible = false }

    Rectangle {
        id: panelCard
        x: {
            const ax = overlay.anchorItem !== null
                ? overlay.anchorItem.mapToItem(null, 0, 0).x + overlay.anchorItem.width / 2
                : overlay.width / 2;
            return Math.max(8, Math.min(ax - width / 2, overlay.width - width - 8));
        }
        y: 6
        width: 420
        implicitHeight: Math.min(flick.contentHeight + 28, overlay.height - 40)
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

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 14
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: flick.width
                spacing: 10

                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Audio"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Colors.textMain
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 70
                        horizontalAlignment: Text.AlignRight
                        visible: overlay.lastError !== ""
                        text: overlay.lastError
                        elide: Text.ElideRight
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        color: Colors.danger
                    }
                }

                // ---- tab bar ----
                Row {
                    spacing: 4
                    Repeater {
                        model: overlay.tabNames
                        Rectangle {
                            required property string modelData
                            required property int index
                            readonly property bool active: overlay.tab === index
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
                                text: parent.modelData
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.weight: parent.active ? Font.DemiBold : Font.Normal
                                color: parent.active ? Colors.accentFg : Colors.textDim
                            }
                            MouseArea {
                                id: tabM
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: overlay.tab = parent.index
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Colors.outline }

                // ---- OUTPUT ----
                Column {
                    visible: overlay.tab === 0
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: overlay.sinks
                        VolRow {
                            required property var modelData
                            node: modelData
                            label: overlay.nodeLabel(modelData)
                            isDefault: modelData === Pipewire.defaultAudioSink
                            selectable: true
                            onMakeDefault: overlay.setDefaultSink(modelData)
                        }
                    }
                }

                // ---- INPUT ----
                Column {
                    visible: overlay.tab === 1
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: overlay.sources
                        VolRow {
                            required property var modelData
                            node: modelData
                            label: overlay.nodeLabel(modelData)
                            isDefault: modelData === Pipewire.defaultAudioSource
                            selectable: true
                            onMakeDefault: overlay.setDefaultSource(modelData)
                        }
                    }
                }

                // ---- MIXER ----
                Column {
                    visible: overlay.tab === 2
                    width: parent.width
                    spacing: 10

                    Text {
                        visible: overlay.streams.length === 0
                        text: "Nothing is playing."
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        color: Colors.textFaint
                    }

                    Repeater {
                        model: overlay.streams
                        VolRow {
                            required property var modelData
                            node: modelData
                            label: overlay.nodeLabel(modelData)
                            sublabel: overlay.streamSub(modelData)
                        }
                    }
                }

                // ---- PROFILES ----

                Column {
                    visible: overlay.tab === 3
                    width: parent.width
                    spacing: 6

                Repeater {
                    model: overlay.cards

                    Rectangle {
                        id: cardRow
                        required property var modelData
                        readonly property bool expanded: overlay.expandedCard === modelData.name
                        readonly property var activeProf:
                            modelData.profiles.find((p) => p.name === modelData.active) ?? null

                        width: parent.width
                        implicitHeight: cardCol.implicitHeight + 16
                        radius: 9
                        color: Colors.mantle
                        border.width: 1
                        border.color: Colors.outline
                        Behavior on implicitHeight { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                        Column {
                            id: cardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 5

                            Item {
                                width: parent.width
                                height: 28

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 20
                                    spacing: 1
                                    Text {
                                        width: parent.width
                                        text: cardRow.modelData.description
                                        elide: Text.ElideRight
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: Colors.textMain
                                    }
                                    Text {
                                        width: parent.width
                                        text: cardRow.activeProf !== null ? cardRow.activeProf.desc : cardRow.modelData.active
                                        elide: Text.ElideRight
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        color: Colors.accent
                                    }
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: cardRow.expanded ? "\u25b4" : "\u25be"
                                    font.pixelSize: 11
                                    color: Colors.textFaint
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: overlay.expandedCard =
                                        cardRow.expanded ? "" : cardRow.modelData.name
                                }
                            }

                            Column {
                                visible: cardRow.expanded
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: cardRow.modelData.profiles

                                    Rectangle {
                                        id: profRow
                                        required property var modelData
                                        readonly property bool current:
                                            modelData.name === cardRow.modelData.active

                                        width: parent.width
                                        height: 24
                                        radius: 6
                                        color: profRow.current ? Qt.alpha(Colors.accent, 0.12)
                                             : profMouse.containsMouse ? Colors.surface0
                                             : "transparent"
                                        Behavior on color { ColorAnimation { duration: 110 } }

                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (profRow.current ? "\u2713 " : "") + profRow.modelData.desc
                                            elide: Text.ElideRight
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            color: profRow.current ? Colors.accent : Colors.textDim
                                        }

                                        MouseArea {
                                            id: profMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: audioAction.run(
                                                ["pactl", "set-card-profile",
                                                 cardRow.modelData.name, profRow.modelData.name])
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                }
            }
        }
    }
}
