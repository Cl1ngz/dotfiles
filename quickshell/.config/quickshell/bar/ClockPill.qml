import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Clock pill + tabbed panel: CLOCK (full localised date), STOPWATCH,
// TIMER (presets plus a typed duration).
//
// Timer and stopwatch state lives HERE, on the pill, not in the overlay
// -- the pill exists for the life of the bar, so both keep running
// while the panel is closed. Both are computed from wall-clock epochs
// rather than by counting ticks, so they stay accurate even if the
// render loop stalls or a tick is dropped.
Pill {
    id: clockPill

    SystemClock {
        id: clock
        // Seconds only while the panel is open: the bar itself needs
        // nothing finer than a minute, and Seconds re-evaluates every
        // binding that reads clock.date once a second.
        precision: overlay.visible ? SystemClock.Seconds : SystemClock.Minutes
    }

    // ==================================================================
    // Localised date
    //
    // The wanted format is glibc's, e.g. "pią, 25 wrz 2026, 23:37:02
    // CEST". Qt's own Polish abbreviations differ ("pt" rather than
    // "pią"), so the locale-dependent pieces come from `date` -- but
    // only the parts that change slowly. The seconds are rendered by Qt
    // from SystemClock, so this costs one process per panel-open rather
    // than one per second.
    // ==================================================================

    property string datePart: ""   // "pią, 25 wrz 2026"
    property string tzPart: ""     // "CEST"

    readonly property string fullStamp: datePart === "" ? Qt.formatDateTime(clock.date, "yyyy-MM-dd, HH:mm:ss") : datePart + ", " + Qt.formatDateTime(clock.date, "HH:mm:ss") + (tzPart === "" ? "" : " " + tzPart)

    Process {
        id: dateProbe
        // The session may not export LC_TIME (it is often only set in a
        // shell rc, which quickshell never sources), so an explicit
        // setting wins and Polish is the fallback. If that locale is not
        // generated, date degrades to C rather than failing.
        // %-d: no leading zero, matching the wanted sample.
        command: ["sh", "-c", 'export LC_TIME="${LC_TIME:-pl_PL.UTF-8}"; ' + "date '+%a, %-d %b %Y'; date '+%Z'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');
                clockPill.datePart = (lines[0] ?? "").trim();
                clockPill.tzPart = (lines[1] ?? "").trim();
            }
        }
        function refresh() {
            running = false;
            running = true;
        }
    }

    // Re-read while open so it survives midnight and a DST change.
    Timer {
        interval: 60000
        repeat: true
        running: overlay.visible
        onTriggered: dateProbe.refresh()
    }

    // ==================================================================
    // Stopwatch
    // ==================================================================

    property bool swRunning: false
    property int swAccumMs: 0      // time banked by previous runs
    property double swStartedAt: 0 // epoch of the current run
    property int swDisplayMs: 0
    property var swLaps: []

    function swToggle() {
        if (swRunning) {
            swAccumMs += Date.now() - swStartedAt;
            swRunning = false;
            swDisplayMs = swAccumMs;
        } else {
            swStartedAt = Date.now();
            swRunning = true;
        }
    }

    function swReset() {
        swRunning = false;
        swAccumMs = 0;
        swStartedAt = 0;
        swDisplayMs = 0;
        swLaps = [];
    }

    function swLap() {
        if (!swRunning && swDisplayMs === 0)
            return;
        // Newest first, and keep the list short enough to stay in view.
        swLaps = [swDisplayMs].concat(swLaps).slice(0, 5);
    }

    Timer {
        // ~20fps: enough for a smooth hundredths column without
        // repainting the panel more than it deserves.
        interval: 47
        repeat: true
        running: clockPill.swRunning
        onTriggered: clockPill.swDisplayMs = clockPill.swAccumMs + (Date.now() - clockPill.swStartedAt)
    }

    // ==================================================================
    // Countdown timer
    // ==================================================================

    property bool tmRunning: false
    property int tmSetMs: 5 * 60000    // what reset returns to
    property int tmRemainMs: 5 * 60000
    property double tmEndsAt: 0

    function tmSet(ms) {
        tmRunning = false;
        tmSetMs = Math.max(1000, ms);
        tmRemainMs = tmSetMs;
    }

    function tmAdjust(deltaMs) {
        if (tmRunning) {
            // Extend or trim the running countdown in place.
            tmEndsAt = Math.max(Date.now(), tmEndsAt + deltaMs);
            tmRemainMs = Math.max(0, tmEndsAt - Date.now());
        } else {
            tmSet(tmRemainMs + deltaMs);
        }
    }

    function tmToggle() {
        if (tmRunning) {
            tmRemainMs = Math.max(0, tmEndsAt - Date.now());
            tmRunning = false;
        } else {
            if (tmRemainMs <= 0)
                tmRemainMs = tmSetMs;
            tmEndsAt = Date.now() + tmRemainMs;
            tmRunning = true;
        }
    }

    function tmReset() {
        tmRunning = false;
        tmRemainMs = tmSetMs;
    }

    // Accepts "5" (bare number = minutes), "5m", "90s", "1h30m",
    // "1h30", "2:30" (mm:ss) and "1:02:30" (h:mm:ss).
    // Returns milliseconds, or -1 if it cannot be read.
    function parseDuration(str) {
        const t = String(str).trim().toLowerCase();
        if (t === "")
            return -1;

        if (t.indexOf(":") !== -1) {
            const parts = t.split(":");
            const nums = [];
            for (const p of parts) {
                const n = parseInt(p, 10);
                if (isNaN(n) || n < 0)
                    return -1;
                nums.push(n);
            }
            if (nums.length === 2)
                return (nums[0] * 60 + nums[1]) * 1000;
            if (nums.length === 3)
                return (nums[0] * 3600 + nums[1] * 60 + nums[2]) * 1000;
            return -1;
        }

        // Unit-suffixed pieces, in any combination.
        const units = t.match(/\d+\s*[hms]/g);
        if (units !== null) {
            let ms = 0;
            for (const u of units) {
                const v = parseInt(u, 10);
                const unit = u[u.length - 1];
                ms += unit === "h" ? v * 3600000 : unit === "m" ? v * 60000 : v * 1000;
            }
            // A trailing bare number after a unit means the next unit
            // down: "1h30" is 90 minutes. Captured in one match so
            // there is no second regex that could come back null.
            const tail = t.match(/([hms])\s*(\d+)$/);
            if (tail !== null) {
                const v = parseInt(tail[2], 10);
                ms += tail[1] === "h" ? v * 60000 : v * 1000;
            }
            return ms;
        }

        const n = parseInt(t, 10);
        if (isNaN(n) || n < 0)
            return -1;
        return n * 60000;   // bare number = minutes
    }

    Timer {
        interval: 100
        repeat: true
        running: clockPill.tmRunning
        onTriggered: {
            const left = Math.max(0, clockPill.tmEndsAt - Date.now());
            clockPill.tmRemainMs = left;
            if (left <= 0) {
                clockPill.tmRunning = false;
                alarmProcess.fire();
            }
        }
    }

    Process {
        id: alarmProcess
        function fire() {
            running = false;
            // Critical urgency: our own notification popups keep those
            // on screen until acted on, which is what an alarm wants.
            // The sound is best-effort -- not every system has the
            // freedesktop sound theme installed.
            command = ["sh", "-c", 'notify-send -u critical -a "Timer" "Timer finished" "$1"; ' + 'paplay /usr/share/sounds/freedesktop/stereo/complete.oga >/dev/null 2>&1 || true', "sh", clockPill.fmtClock(clockPill.tmSetMs) + " elapsed"];
            running = true;
        }
    }

    // ==================================================================
    // Formatting
    // ==================================================================

    function pad2(n) {
        return n < 10 ? "0" + n : String(n);
    }

    // H:MM:SS.cc, dropping the hour until it is needed.
    function fmtStopwatch(ms) {
        const cs = Math.floor((ms % 1000) / 10);
        const total = Math.floor(ms / 1000);
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        const head = h > 0 ? h + ":" + pad2(m) : String(m);
        return head + ":" + pad2(s) + "." + pad2(cs);
    }

    // MM:SS, or H:MM:SS past an hour. Rounded UP so a fresh 5:00 shows
    // 5:00 rather than 4:59.
    function fmtClock(ms) {
        const total = Math.ceil(ms / 1000);
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        return h > 0 ? h + ":" + pad2(m) + ":" + pad2(s) : m + ":" + pad2(s);
    }

    // ==================================================================
    // Pill
    // ==================================================================

    readonly property string clockText: Qt.formatDateTime(clock.date, "HH:mm")

    // A running countdown is appended to the clock: it is the thing you
    // are watching, and it stays visible with the panel closed.
    // Only while RUNNING. A finished timer says so through its
    // notification; it does not park a red 0:00 in the bar until reset.
    label: tmRunning ? clockText + "  " + fmtClock(tmRemainMs) : clockText
    tint: Colors.accent

    onClicked: button => {
        if (button === Qt.LeftButton)
            overlay.visible = !overlay.visible;
    }

    // ==================================================================
    // Panel
    // ==================================================================

    property int tab: 0
    readonly property var tabNames: ["CLOCK", "STOPWATCH", "TIMER"]

    component SectionLabel: Text {
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        font.letterSpacing: 1
        color: Colors.textFaint
    }

    component MiniButton: Rectangle {
        property string label: ""
        property color tint: Colors.textMain
        property bool emphasized: false
        property int hpad: 16
        signal clicked

        implicitWidth: mbText.implicitWidth + hpad
        implicitHeight: 24
        radius: 7
        color: emphasized ? (mbMouse.containsMouse ? Qt.alpha(tint, 0.30) : Qt.alpha(tint, 0.18)) : (mbMouse.containsMouse ? Colors.surface1 : Colors.surface0)
        border.width: emphasized ? 1 : 0
        border.color: Qt.alpha(tint, 0.5)
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        Text {
            id: mbText
            anchors.centerIn: parent
            text: parent.label
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.weight: parent.emphasized ? Font.DemiBold : Font.Normal
            color: parent.emphasized ? parent.tint : Colors.textDim
        }

        MouseArea {
            id: mbMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
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
        // The timer tab has a text field, so the panel has to be able to
        // take keyboard focus when clicked into.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-clock"
        color: "transparent"
        visible: false
        exclusiveZone: 0

        onVisibleChanged: if (visible)
            dateProbe.refresh()

        MouseArea {
            anchors.fill: parent
            onClicked: overlay.visible = false
        }

        Rectangle {
            id: panelCard

            x: Math.max(8, Math.min(clockPill.mapToItem(null, 0, 0).x + clockPill.width / 2 - width / 2, overlay.width - width - 8))
            // The overlay respects the bar's exclusive zone, so its top
            // edge is already the bottom of the bar.
            y: 6
            width: 320
            implicitHeight: col.implicitHeight + 28
            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            radius: 14
            color: Colors.base
            border.width: 1
            border.color: Colors.outline
            clip: true

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
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 11

                // ---- tab bar ----
                Row {
                    spacing: 4

                    Repeater {
                        model: clockPill.tabNames

                        Rectangle {
                            required property string modelData
                            required property int index
                            readonly property bool active: clockPill.tab === index

                            implicitWidth: tabText.implicitWidth + 18
                            implicitHeight: 24
                            radius: 8
                            color: active ? Colors.accent : tabMouse.containsMouse ? Colors.surface1 : Colors.surface0
                            Behavior on color {
                                ColorAnimation {
                                    duration: 130
                                }
                            }

                            Text {
                                id: tabText
                                anchors.centerIn: parent
                                text: parent.modelData
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.weight: parent.active ? Font.DemiBold : Font.Normal
                                color: parent.active ? Colors.accentFg : Colors.textDim
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: clockPill.tab = parent.index
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Colors.outline
                }

                // ================= CLOCK =================
                Column {
                    visible: clockPill.tab === 0
                    width: parent.width
                    spacing: 6

                    Text {
                        text: Qt.formatDateTime(clock.date, "HH:mm:ss")
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 30
                        font.weight: Font.DemiBold
                        color: Colors.textMain
                    }

                    Text {
                        width: parent.width
                        text: clockPill.fullStamp
                        wrapMode: Text.Wrap
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        color: Colors.textDim
                    }
                }

                // ================= STOPWATCH =================
                Column {
                    visible: clockPill.tab === 1
                    width: parent.width
                    spacing: 10

                    Text {
                        text: clockPill.fmtStopwatch(clockPill.swDisplayMs)
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 30
                        font.weight: Font.DemiBold
                        color: clockPill.swRunning ? Colors.accent : clockPill.swDisplayMs > 0 ? Colors.textMain : Colors.textFaint
                    }

                    Row {
                        spacing: 6

                        MiniButton {
                            label: clockPill.swRunning ? "pause" : (clockPill.swDisplayMs > 0 ? "resume" : "start")
                            tint: Colors.accent
                            emphasized: true
                            onClicked: clockPill.swToggle()
                        }
                        MiniButton {
                            label: "lap"
                            onClicked: clockPill.swLap()
                        }
                        MiniButton {
                            label: "reset"
                            onClicked: clockPill.swReset()
                        }
                    }

                    Column {
                        visible: clockPill.swLaps.length > 0
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: clockPill.swLaps

                            Item {
                                required property int modelData
                                required property int index
                                width: col.width
                                height: 15

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "lap " + (clockPill.swLaps.length - parent.index)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    color: Colors.textFaint
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: clockPill.fmtStopwatch(parent.modelData)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    color: Colors.textDim
                                }
                            }
                        }
                    }
                }

                // ================= TIMER =================
                Column {
                    visible: clockPill.tab === 2
                    width: parent.width
                    spacing: 10

                    Text {
                        text: clockPill.fmtClock(clockPill.tmRemainMs)
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 30
                        font.weight: Font.DemiBold
                        color: clockPill.tmRunning ? Colors.accent : clockPill.tmRemainMs <= 0 ? Colors.textFaint : Colors.textMain
                    }

                    // Progress of the current countdown.
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Colors.surface0

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: clockPill.tmSetMs > 0 ? parent.width * Math.max(0, Math.min(1, clockPill.tmRemainMs / clockPill.tmSetMs)) : 0
                            height: parent.height
                            radius: 2
                            color: Colors.accent
                            Behavior on width {
                                NumberAnimation {
                                    duration: 120
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 6

                        MiniButton {
                            label: clockPill.tmRunning ? "pause" : "start"
                            tint: Colors.accent
                            emphasized: true
                            onClicked: clockPill.tmToggle()
                        }
                        MiniButton {
                            label: "reset"
                            onClicked: clockPill.tmReset()
                        }
                        MiniButton {
                            label: "-1m"
                            hpad: 12
                            onClicked: clockPill.tmAdjust(-60000)
                        }
                        MiniButton {
                            label: "+1m"
                            hpad: 12
                            onClicked: clockPill.tmAdjust(60000)
                        }
                    }

                    SectionLabel {
                        text: "PRESETS"
                    }

                    Row {
                        width: parent.width
                        spacing: 5

                        Repeater {
                            model: [
                                {
                                    t: "3m",
                                    ms: 3 * 60000
                                },
                                {
                                    t: "5m",
                                    ms: 5 * 60000
                                },
                                {
                                    t: "10m",
                                    ms: 10 * 60000
                                },
                                {
                                    t: "15m",
                                    ms: 15 * 60000
                                },
                                {
                                    t: "30m",
                                    ms: 30 * 60000
                                },
                                {
                                    t: "1h",
                                    ms: 60 * 60000
                                }
                            ]

                            Rectangle {
                                required property var modelData
                                readonly property bool current: clockPill.tmSetMs === modelData.ms

                                width: (col.width - 25) / 6
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
                                    text: parent.modelData.t
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.weight: parent.current ? Font.DemiBold : Font.Normal
                                    color: parent.current ? Colors.accentFg : Colors.textDim
                                }

                                MouseArea {
                                    id: presetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    // Set AND start: that is what a
                                    // one-click "10 minutes" is for.
                                    onClicked: {
                                        clockPill.tmSet(parent.modelData.ms);
                                        clockPill.tmToggle();
                                    }
                                }
                            }
                        }
                    }

                    SectionLabel {
                        text: "CUSTOM  ·  5 · 90s · 1h30m · 2:30"
                    }

                    Row {
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            id: inputBox
                            width: parent.width - 66
                            height: 26
                            radius: 7
                            color: Colors.mantle
                            border.width: 1
                            border.color: durationInput.activeFocus ? Qt.alpha(Colors.accent, 0.7) : (durationInput.text !== "" && clockPill.parseDuration(durationInput.text) < 0 ? Qt.alpha(Colors.danger, 0.7) : Colors.outline)
                            Behavior on border.color {
                                ColorAnimation {
                                    duration: 130
                                }
                            }

                            TextInput {
                                id: durationInput
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: Colors.textMain
                                clip: true

                                onAccepted: applyButton.clicked()
                                Keys.onEscapePressed: {
                                    durationInput.text = "";
                                    overlay.visible = false;
                                }

                                Text {
                                    visible: durationInput.text === ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "type a duration…"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    color: Colors.textFaint
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                // Clicking the box focuses the field; the
                                // TextInput itself does not grab focus on
                                // a layer-shell surface without this.
                                onClicked: durationInput.forceActiveFocus()
                            }
                        }

                        MiniButton {
                            id: applyButton
                            label: "set"
                            hpad: 14
                            tint: Colors.accent
                            emphasized: true
                            onClicked: {
                                const ms = clockPill.parseDuration(durationInput.text);
                                if (ms <= 0)
                                    return;
                                clockPill.tmSet(ms);
                                clockPill.tmToggle();
                                durationInput.text = "";
                            }
                        }
                    }
                }
            }
        }
    }
}
