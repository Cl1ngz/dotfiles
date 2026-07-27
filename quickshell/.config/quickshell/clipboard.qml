import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: clipboardWindow

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-clipboard"

    color: "transparent"

    // ---- palette (catppuccin mocha) ----------------------------------
    readonly property color crust: "#11111b"
    readonly property color mantle: "#181825"
    readonly property color base: "#1e1e2e"
    readonly property color surface0: "#313244"
    readonly property color surface1: "#45475a"
    readonly property color overlay0: "#6c7086"
    readonly property color textMain: "#cdd6f4"
    readonly property color textDim: "#a6adc8"
    readonly property color textFaint: "#7f849c"
    readonly property color accent: "#89b4fa"
    readonly property color accentAlt: "#cba6f7"
    readonly property color danger: "#f38ba8"
    readonly property color warn: "#f9e2af"

    // ---- confirmation state ------------------------------------------
    // Only one confirmation panel can be armed at a time.
    property bool clearConfirm: false
    property string pendingDeleteId: ""

    function cancelConfirmations() {
        clearConfirm = false;
        pendingDeleteId = "";
    }

    function anyConfirmArmed() {
        return clearConfirm || pendingDeleteId !== "";
    }

    // ==================================================================
    // Persistent pin storage
    //
    // This is deliberately plain Process + a newline-delimited file
    // rather than FileView/JsonAdapter. The FileView version silently
    // never wrote anything (the log showed "pins.json ... File does not
    // exist"), which is why pins vanished as soon as the panel closed.
    // Writing through sh is boring but verifiable: the file is either
    // there with the ids in it, or it isn't.
    //
    // Pins are keyed by cliphist's own entry id -- the exact database
    // lookup key for one stored selection. The preview text beside it is
    // truncated to ~100 chars and is NOT unique, which is why hashing
    // the preview used to make two same-size images share a pin.
    // ==================================================================

    readonly property string pinsDir: Quickshell.statePath("clipboard")
    readonly property string pinsFile: Quickshell.statePath("clipboard/pins.json")

    property var pinnedIds: []

    function isPinned(itemId) {
        return pinnedIds.indexOf(itemId) !== -1;
    }

    function setPinned(itemId, pinned) {
        const ids = pinnedIds.slice();
        const idx = ids.indexOf(itemId);
        if (pinned && idx === -1)
            ids.push(itemId);
        else if (!pinned && idx !== -1)
            ids.splice(idx, 1);
        else
            return;

        pinnedIds = ids;
        pinsSaveProcess.save(ids);
    }

    // Reads the pin file, then kicks off the first cliphist list. The
    // ordering matters: if the list arrived first, every entry would be
    // built with pinned=false and the pins wouldn't show until a refresh.
    Process {
        id: pinsLoadProcess
        running: true
        command: ["sh", "-c", "cat '" + clipboardWindow.pinsFile + "' 2>/dev/null || true"]

        stdout: StdioCollector {
            onStreamFinished: {
                clipboardWindow.pinnedIds = text.split('\n').map(s => s.trim()).filter(s => s !== "");
                listProcess.refresh();
            }
        }
    }

    Process {
        id: pinsSaveProcess
        property var pendingWrite: null

        function save(ids) {
            // A write is already in flight. Queue this one instead of
            // killing the running process mid-write, which would leave a
            // truncated file -- i.e. lose the pins we're trying to save.
            if (running) {
                pendingWrite = ids.slice();
                return;
            }
            const safe = ids.filter(id => /^[0-9]+$/.test(id));
            const body = safe.length === 0 ? ":" : "printf '%s\\n' " + safe.join(" ");
            command = ["sh", "-c", "mkdir -p '" + clipboardWindow.pinsDir + "' && { " + body + "; } > '" + clipboardWindow.pinsFile + "'"];
            running = true;
        }

        onExited: {
            if (pendingWrite !== null) {
                const next = pendingWrite;
                pendingWrite = null;
                save(next);
            }
        }
    }

    // ==================================================================
    // Entry data
    //
    // allEntries is the single source of truth; clipboardModel (bound to
    // the ListView) is always derived from it via applyFilter().
    // ==================================================================

    property var allEntries: []
    // The itemId currently shown in the preview pane. Decode processes
    // compare against this before writing their result, so a slow reply
    // for an entry you've since arrowed past can't clobber the screen.
    property string activePreviewId: ""

    function setEntriesFromCliphistOutput(text) {
        const lines = text.split('\n');
        const entries = [];

        for (let i = 0; i < lines.length; i++) {
            if (lines[i].trim() === "")
                continue;
            const parts = lines[i].split('\t');
            if (parts.length < 2)
                continue;

            const itemId = parts[0];
            const payload = parts[1];

            // cliphist renders binary entries as "[[ binary data 1 MiB png 1900x1069 ]]".
            // Pull the useful part out so the row reads "1 MiB png 1900x1069".
            const binaryMatch = payload.match(/\[\[\s*binary data\s+(.+?)\s*\]\]/);
            const isImg = binaryMatch !== null;

            // cliphist does not store timestamps, so size is all we can show.
            entries.push({
                itemId: itemId,
                title: isImg ? binaryMatch[1] : payload,
                meta: isImg ? "binary" : (payload.length + " B"),
                isImage: isImg,
                pinned: clipboardWindow.isPinned(itemId)
            });
        }

        allEntries = entries;
        applyFilter();
    }

    function applyFilter() {
        const query = searchField.text.toLowerCase().trim();
        const matches = query === "" ? allEntries : allEntries.filter(e => e.title.toLowerCase().indexOf(query) !== -1);

        const pinned = matches.filter(e => e.pinned);
        const unpinned = matches.filter(e => !e.pinned);

        const previousId = clipboardList.currentIndex >= 0 && clipboardList.currentIndex < clipboardModel.count ? clipboardModel.get(clipboardList.currentIndex).itemId : "";

        clipboardModel.clear();
        for (const it of pinned)
            clipboardModel.append(it);
        for (const it of unpinned)
            clipboardModel.append(it);

        let restored = -1;
        if (previousId !== "") {
            for (let i = 0; i < clipboardModel.count; i++) {
                if (clipboardModel.get(i).itemId === previousId) {
                    restored = i;
                    break;
                }
            }
        }
        clipboardList.currentIndex = clipboardModel.count === 0 ? -1 : (restored !== -1 ? restored : 0);

        // currentIndex may not have *changed* numerically even though the
        // entry sitting at that index did, so refresh the preview by hand.
        // onSelectionChanged() no-ops when the id genuinely matches.
        onSelectionChanged();
    }

    function togglePinnedAt(index) {
        if (index < 0 || index >= clipboardModel.count)
            return;
        const itemId = clipboardModel.get(index).itemId;
        const updated = allEntries.slice();
        for (let i = 0; i < updated.length; i++) {
            if (updated[i].itemId === itemId) {
                updated[i] = Object.assign({}, updated[i], {
                    pinned: !updated[i].pinned
                });
                setPinned(itemId, updated[i].pinned);
                allEntries = updated;
                applyFilter();
                return;
            }
        }
    }

    function hasAnyPinned() {
        return allEntries.some(e => e.pinned);
    }

    function selectedEntry() {
        if (clipboardList.currentIndex < 0 || clipboardList.currentIndex >= clipboardModel.count)
            return null;
        return clipboardModel.get(clipboardList.currentIndex);
    }

    // ---- selection ---------------------------------------------------
    // The ListView never takes keyboard focus; focus lives permanently in
    // the search field and arrow keys are routed here. Previously focus
    // bounced between the field and the list, and each owner tracked its
    // own idea of the current row -- that's why up-then-down-then-up
    // "forgot" where you were.

    function moveSelection(delta) {
        if (clipboardModel.count === 0)
            return;
        let next = clipboardList.currentIndex + delta;
        if (next < 0)
            next = 0;
        if (next > clipboardModel.count - 1)
            next = clipboardModel.count - 1;
        if (next === clipboardList.currentIndex)
            return;
        clipboardList.currentIndex = next;
        clipboardList.positionViewAtIndex(next, ListView.Contain);
    }

    function selectIndex(index) {
        if (index < 0 || index >= clipboardModel.count)
            return;
        clipboardList.currentIndex = index;
        clipboardList.positionViewAtIndex(index, ListView.Contain);
    }

    function onSelectionChanged() {
        pendingDeleteId = "";

        const entry = selectedEntry();
        if (entry === null) {
            activePreviewId = "";
            previewDebounce.stop();
            previewText.text = allEntries.length === 0 ? "Clipboard is empty." : "No matches.";
            return;
        }
        if (entry.itemId === activePreviewId)
            return;

        activePreviewId = entry.itemId;
        previewText.text = "Loading…";
        previewDebounce.restart();
    }

    Timer {
        id: previewDebounce
        interval: 80
        onTriggered: clipboardWindow.loadPreview()
    }

    Timer {
        id: filterDebounce
        interval: 120
        onTriggered: clipboardWindow.applyFilter()
    }

    function loadPreview() {
        const id = activePreviewId;
        if (id === "")
            return;
        const entry = allEntries.find(e => e.itemId === id);
        if (entry === undefined)
            return;

        if (entry.isImage)
            decodeImageProcess.runDecode(id);
        else
            decodeProcess.runDecode(id);
    }

    function activateSelected() {
        const entry = selectedEntry();
        if (entry === null)
            return;
        copyProcess.runCopy(entry.itemId);
        Qt.quit();
    }

    // ==================================================================
    // cliphist processes
    // ==================================================================

    Process {
        id: listProcess
        stdout: StdioCollector {
            onStreamFinished: clipboardWindow.setEntriesFromCliphistOutput(text)
        }
        function refresh() {
            running = false;
            command = ["sh", "-c", "cliphist list | head -n 50"];
            running = true;
        }
    }

    Process {
        id: decodeProcess
        property string requestId: ""

        stdout: StdioCollector {
            onStreamFinished: {
                if (decodeProcess.requestId !== clipboardWindow.activePreviewId)
                    return;
                const body = text;
                const trimmed = body.trim();
                // A copied file usually lands in the clipboard as a URI or a
                // bare absolute path -- show just that, not a wall of text.
                if (trimmed.indexOf('\n') === -1 && (trimmed.startsWith("file://") || trimmed.startsWith("/"))) {
                    previewText.text = trimmed.replace(/^file:\/\//, "");
                } else {
                    previewText.text = body;
                }
            }
        }

        function runDecode(id) {
            requestId = id;
            running = false;
            command = ["sh", "-c", "cliphist list | awk -F'\\t' '$1 == " + id + " {print $0}' | cliphist decode"];
            running = true;
        }
    }

    // Images are written to a temp file and the preview shows that path.
    // Piping image bytes into a text widget renders as garbage, and the
    // path is the thing you actually want to hand to another program.
    Process {
        id: decodeImageProcess
        property string pendingPath: ""
        property string requestId: ""

        function runDecode(id) {
            requestId = id;
            pendingPath = "/tmp/quickshell-clipboard-" + id;
            running = false;
            command = ["sh", "-c", "cliphist list | awk -F'\\t' '$1 == " + id + " {print $0}' | cliphist decode > '" + pendingPath + "'"];
            running = true;
        }

        onExited: exitCode => {
            if (requestId !== clipboardWindow.activePreviewId)
                return;
            previewText.text = exitCode === 0 ? pendingPath : "Could not decode this entry.";
        }
    }

    Process {
        id: copyProcess
        function runCopy(id) {
            running = false;
            command = ["sh", "-c", "cliphist list | awk -F'\\t' '$1 == " + id + " {print $0}' | cliphist decode | wl-copy"];
            running = true;
        }
    }

    Process {
        id: deleteProcess
        onExited: listProcess.refresh()
        function runDelete(id) {
            running = false;
            command = ["sh", "-c", "cliphist list | awk -F'\\t' '$1 == " + id + " {print $0}' | cliphist delete"];
            running = true;
        }
    }

    Process {
        id: wipeProcess
        onExited: listProcess.refresh()
        function runWipe() {
            running = false;
            command = ["cliphist", "wipe"];
            running = true;
        }
    }

    // Deletes every currently-unpinned entry one at a time, leaving
    // pinned entries (and their stored ids) untouched.
    Process {
        id: clearUnpinnedProcess
        onExited: listProcess.refresh()

        function run(ids) {
            if (ids.length === 0) {
                listProcess.refresh();
                return;
            }
            running = false;
            command = ["sh", "-c", "for id in " + ids.join(" ") + "; do " + "cliphist list | awk -F'\\t' -v id=\"$id\" '$1==id{print;exit}' | cliphist delete; " + "done"];
            running = true;
        }
    }

    function confirmKeepPinned() {
        const ids = allEntries.filter(e => !e.pinned).map(e => e.itemId);
        clearConfirm = false;
        clearUnpinnedProcess.run(ids);
    }

    function confirmClearAll() {
        clearConfirm = false;
        // Pinned ids refer to entries that no longer exist after a wipe.
        pinnedIds = [];
        pinsSaveProcess.save([]);
        wipeProcess.runWipe();
    }

    function confirmDelete() {
        const id = pendingDeleteId;
        if (id === "")
            return;
        pendingDeleteId = "";
        setPinned(id, false);
        deleteProcess.runDelete(id);
    }

    // ==================================================================
    // Reusable UI pieces
    // ==================================================================

    component IconButton: Rectangle {
        id: iconBtn
        property string glyph: ""
        property color tint: clipboardWindow.textDim
        property bool active: false
        property string tip: ""
        signal clicked

        implicitWidth: 30
        implicitHeight: 30
        radius: 7
        color: iconBtn.active ? Qt.alpha(iconBtn.tint, 0.20) : iconMouse.containsMouse ? clipboardWindow.surface0 : "transparent"
        border.width: 1
        border.color: iconBtn.active ? Qt.alpha(iconBtn.tint, 0.55) : "transparent"
        scale: iconMouse.pressed ? 0.88 : 1.0

        Behavior on color {
            ColorAnimation {
                duration: 110
                easing.type: Easing.OutCubic
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 110
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }

        Text {
            anchors.centerIn: parent
            text: iconBtn.glyph
            font.pixelSize: 13
            color: iconBtn.active || iconMouse.containsMouse ? iconBtn.tint : clipboardWindow.textFaint
            Behavior on color {
                ColorAnimation {
                    duration: 110
                }
            }
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: iconBtn.clicked()
        }
    }

    component TextButton: Rectangle {
        id: txtBtn
        property string label: ""
        property color tint: clipboardWindow.textMain
        property bool emphasized: false
        signal clicked

        implicitWidth: btnLabel.implicitWidth + 26
        implicitHeight: 30
        radius: 7
        color: txtBtn.emphasized ? (btnMouse.containsMouse ? Qt.alpha(txtBtn.tint, 0.28) : Qt.alpha(txtBtn.tint, 0.16)) : (btnMouse.containsMouse ? clipboardWindow.surface1 : clipboardWindow.surface0)
        border.width: 1
        border.color: txtBtn.emphasized ? Qt.alpha(txtBtn.tint, 0.5) : "transparent"
        scale: btnMouse.pressed ? 0.96 : 1.0

        Behavior on color {
            ColorAnimation {
                duration: 110
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }

        Text {
            id: btnLabel
            anchors.centerIn: parent
            text: txtBtn.label
            font.pixelSize: 12
            font.weight: Font.Medium
            color: txtBtn.emphasized ? txtBtn.tint : clipboardWindow.textMain
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: txtBtn.clicked()
        }
    }

    // Inline confirmation strip. Animates height + opacity so it grows
    // into place instead of snapping the layout around.
    component ConfirmPanel: Rectangle {
        id: confirmPanel
        property bool shown: false
        default property alias contentChildren: confirmColumn.children

        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        implicitHeight: shown ? confirmColumn.implicitHeight + 22 : 0
        opacity: shown ? 1 : 0
        clip: true
        radius: 8
        color: Qt.alpha(clipboardWindow.danger, 0.10)
        border.width: 1
        border.color: Qt.alpha(clipboardWindow.danger, 0.45)

        Behavior on implicitHeight {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            id: confirmColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 11
            spacing: 8
        }
    }

    // ==================================================================
    // Window chrome
    // ==================================================================

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (clipboardWindow.anyConfirmArmed()) {
                clipboardWindow.cancelConfirmations();
                return;
            }
            Qt.quit();
        }
    }

    Rectangle {
        id: card
        implicitWidth: 860
        implicitHeight: 540
        anchors.centerIn: parent

        color: clipboardWindow.base
        radius: 12
        border.width: 1
        border.color: clipboardWindow.surface0

        opacity: 0
        scale: 0.985
        Component.onCompleted: {
            opacity = 1;
            scale = 1;
            searchField.forceActiveFocus();
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        // Swallow clicks so they don't reach the dismiss-on-click backdrop.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            ConfirmPanel {
                shown: clipboardWindow.clearConfirm

                Text {
                    text: "Clear clipboard history?"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: clipboardWindow.danger
                }
                Text {
                    text: clipboardWindow.hasAnyPinned() ? "\"Keep pinned\" removes everything except your pinned entries." : "Nothing is pinned, so both options remove everything."
                    font.pixelSize: 11
                    color: clipboardWindow.textDim
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item {
                        Layout.fillWidth: true
                    }
                    TextButton {
                        label: "Cancel"
                        onClicked: clipboardWindow.clearConfirm = false
                    }
                    TextButton {
                        label: "Keep pinned"
                        visible: clipboardWindow.hasAnyPinned()
                        onClicked: clipboardWindow.confirmKeepPinned()
                    }
                    TextButton {
                        label: "Clear all"
                        tint: clipboardWindow.danger
                        emphasized: true
                        onClicked: clipboardWindow.confirmClearAll()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                // ---------------- SIDEBAR ----------------
                ColumnLayout {
                    Layout.fillHeight: true
                    // Bound to the card, not to the parent layout: binding to
                    // the layout's own width fed its result back into the same
                    // layout pass ("Detected recursive rearrange").
                    Layout.preferredWidth: card.width * 0.36
                    spacing: 11

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Clipboard"
                            font.pixelSize: 19
                            font.weight: Font.DemiBold
                            color: clipboardWindow.textMain
                        }

                        Rectangle {
                            visible: clipboardWindow.allEntries.length > 0
                            implicitWidth: countLabel.implicitWidth + 14
                            implicitHeight: 19
                            radius: 9
                            color: clipboardWindow.surface0
                            Text {
                                id: countLabel
                                anchors.centerIn: parent
                                text: clipboardWindow.allEntries.length
                                font.pixelSize: 10
                                color: clipboardWindow.textFaint
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        IconButton {
                            glyph: "🗑"
                            tint: clipboardWindow.danger
                            active: clipboardWindow.clearConfirm
                            onClicked: {
                                if (clipboardWindow.allEntries.length === 0)
                                    return;
                                clipboardWindow.pendingDeleteId = "";
                                clipboardWindow.clearConfirm = !clipboardWindow.clearConfirm;
                            }
                        }
                    }

                    // Focus lives here for the whole session; arrow keys are
                    // forwarded to the list so you can type and navigate
                    // without ever clicking anything.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 8
                        color: clipboardWindow.mantle
                        border.width: 1
                        border.color: searchField.activeFocus ? Qt.alpha(clipboardWindow.accent, 0.7) : clipboardWindow.surface0
                        Behavior on border.color {
                            ColorAnimation {
                                duration: 130
                                easing.type: Easing.OutCubic
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11
                            spacing: 7

                            Text {
                                text: "⌕"
                                font.pixelSize: 15
                                color: searchField.activeFocus ? clipboardWindow.accent : clipboardWindow.textFaint
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 130
                                    }
                                }
                            }

                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                placeholderText: "Search history…"
                                color: clipboardWindow.textMain
                                placeholderTextColor: clipboardWindow.textFaint
                                font.pixelSize: 13
                                background: null
                                padding: 0
                                verticalAlignment: TextInput.AlignVCenter
                                focus: true

                                onTextChanged: filterDebounce.restart()

                                Keys.onUpPressed: clipboardWindow.moveSelection(-1)
                                Keys.onDownPressed: clipboardWindow.moveSelection(1)
                                Keys.onPressed: event => {
                                    switch (event.key) {
                                    case Qt.Key_Escape:
                                        if (clipboardWindow.anyConfirmArmed())
                                            clipboardWindow.cancelConfirmations();
                                        else if (searchField.text !== "")
                                            searchField.text = "";
                                        else
                                            Qt.quit();
                                        event.accepted = true;
                                        break;
                                    case Qt.Key_Return:
                                    case Qt.Key_Enter:
                                        if (clipboardWindow.pendingDeleteId !== "")
                                            clipboardWindow.confirmDelete();
                                        else if (clipboardWindow.clearConfirm)
                                            clipboardWindow.confirmKeepPinned();
                                        else
                                            clipboardWindow.activateSelected();
                                        event.accepted = true;
                                        break;
                                    case Qt.Key_PageUp:
                                        clipboardWindow.moveSelection(-6);
                                        event.accepted = true;
                                        break;
                                    case Qt.Key_PageDown:
                                        clipboardWindow.moveSelection(6);
                                        event.accepted = true;
                                        break;
                                    case Qt.Key_P:
                                        if (event.modifiers & Qt.ControlModifier) {
                                            clipboardWindow.togglePinnedAt(clipboardList.currentIndex);
                                            event.accepted = true;
                                        }
                                        break;
                                    case Qt.Key_D:
                                        if (event.modifiers & Qt.ControlModifier) {
                                            const entry = clipboardWindow.selectedEntry();
                                            if (entry !== null) {
                                                clipboardWindow.clearConfirm = false;
                                                clipboardWindow.pendingDeleteId = clipboardWindow.pendingDeleteId === entry.itemId ? "" : entry.itemId;
                                            }
                                            event.accepted = true;
                                        }
                                        break;
                                    }
                                }
                            }

                            IconButton {
                                glyph: "✕"
                                visible: searchField.text !== ""
                                implicitWidth: 20
                                implicitHeight: 20
                                onClicked: {
                                    searchField.text = "";
                                    searchField.forceActiveFocus();
                                }
                            }
                        }
                    }

                    ListModel {
                        id: clipboardModel
                    }

                    ListView {
                        id: clipboardList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        model: clipboardModel
                        // Never focusable: focus stays in the search field so
                        // there is exactly one owner of the current row.
                        focus: false
                        interactive: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 130
                        highlightMoveVelocity: -1

                        onCurrentIndexChanged: clipboardWindow.onSelectionChanged()

                        delegate: Rectangle {
                            id: row
                            // ListView.isCurrentItem only resolves on the
                            // delegate root. Reading it from nested children
                            // yields undefined, which broke their color
                            // bindings and made selected rows render invisible.
                            readonly property bool selected: ListView.isCurrentItem

                            width: ListView.view.width
                            height: 54
                            radius: 8
                            color: row.selected ? clipboardWindow.surface0 : rowMouse.containsMouse ? Qt.alpha(clipboardWindow.surface0, 0.5) : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: 110
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: row.selected ? 28 : 0
                                radius: 2
                                color: model.pinned ? clipboardWindow.warn : clipboardWindow.accent
                                Behavior on height {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutBack
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 13
                                anchors.rightMargin: 11
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 9

                                Text {
                                    text: model.isImage ? "🖼" : (model.pinned ? "📌" : "📄")
                                    font.pixelSize: 13
                                    color: model.pinned ? clipboardWindow.warn : clipboardWindow.textFaint
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: model.title
                                        font.pixelSize: 13
                                        font.weight: row.selected ? Font.DemiBold : Font.Normal
                                        color: row.selected ? clipboardWindow.textMain : clipboardWindow.textDim
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: model.meta
                                        font.pixelSize: 10
                                        color: clipboardWindow.textFaint
                                    }
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                // Click selects, double-click copies and closes.
                                // Copying on a single click made it impossible
                                // to browse without overwriting the clipboard.
                                onClicked: clipboardWindow.selectIndex(index)
                                onDoubleClicked: {
                                    clipboardWindow.selectIndex(index);
                                    clipboardWindow.activateSelected();
                                }
                            }
                        }
                    }
                }

                // ---------------- PREVIEW ----------------
                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    spacing: 11

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                readonly property var entry: clipboardWindow.selectedEntry()
                                text: entry === null ? "Nothing selected" : (entry.isImage ? "Image entry" : "Text entry")
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                color: clipboardWindow.textMain
                            }
                            Text {
                                readonly property var entry: clipboardWindow.selectedEntry()
                                text: entry === null ? "" : (entry.pinned ? entry.meta + "  ·  pinned" : entry.meta)
                                font.pixelSize: 11
                                color: entry !== null && entry.pinned ? clipboardWindow.warn : clipboardWindow.textFaint
                            }
                        }

                        IconButton {
                            glyph: "📋"
                            tint: clipboardWindow.accent
                            onClicked: clipboardWindow.activateSelected()
                        }
                        IconButton {
                            glyph: "📌"
                            tint: clipboardWindow.warn
                            active: {
                                const e = clipboardWindow.selectedEntry();
                                return e !== null && e.pinned;
                            }
                            onClicked: clipboardWindow.togglePinnedAt(clipboardList.currentIndex)
                        }
                        IconButton {
                            glyph: "🗑"
                            tint: clipboardWindow.danger
                            active: {
                                const e = clipboardWindow.selectedEntry();
                                return e !== null && clipboardWindow.pendingDeleteId === e.itemId;
                            }
                            onClicked: {
                                const e = clipboardWindow.selectedEntry();
                                if (e === null)
                                    return;
                                clipboardWindow.clearConfirm = false;
                                clipboardWindow.pendingDeleteId = clipboardWindow.pendingDeleteId === e.itemId ? "" : e.itemId;
                            }
                        }
                        IconButton {
                            glyph: "✕"
                            onClicked: Qt.quit()
                        }
                    }

                    ConfirmPanel {
                        shown: clipboardWindow.pendingDeleteId !== ""

                        Text {
                            text: "Delete this entry?"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: clipboardWindow.danger
                        }
                        Text {
                            text: "It will be removed from cliphist. This can't be undone."
                            font.pixelSize: 11
                            color: clipboardWindow.textDim
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Item {
                                Layout.fillWidth: true
                            }
                            TextButton {
                                label: "Cancel"
                                onClicked: clipboardWindow.pendingDeleteId = ""
                            }
                            TextButton {
                                label: "Delete"
                                tint: clipboardWindow.danger
                                emphasized: true
                                onClicked: clipboardWindow.confirmDelete()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: clipboardWindow.mantle
                        border.width: 1
                        border.color: clipboardWindow.surface0
                        clip: true

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 12
                            clip: true

                            TextArea {
                                id: previewText
                                text: "Loading…"
                                color: clipboardWindow.textDim
                                readOnly: true
                                selectByMouse: true
                                wrapMode: Text.Wrap
                                background: null
                                padding: 0
                                font.pixelSize: 12
                                font.family: "monospace"
                            }
                        }
                    }
                }
            }

            // ---------------- FOOTER HINTS ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Repeater {
                    model: [
                        {
                            k: "↑↓",
                            d: "navigate"
                        },
                        {
                            k: "⏎",
                            d: "copy & close"
                        },
                        {
                            k: "^P",
                            d: "pin"
                        },
                        {
                            k: "^D",
                            d: "delete"
                        },
                        {
                            k: "esc",
                            d: "close"
                        }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        spacing: 5
                        Rectangle {
                            implicitWidth: keyLabel.implicitWidth + 10
                            implicitHeight: 17
                            radius: 4
                            color: clipboardWindow.surface0
                            Text {
                                id: keyLabel
                                anchors.centerIn: parent
                                text: modelData.k
                                font.pixelSize: 10
                                color: clipboardWindow.textDim
                            }
                        }
                        Text {
                            text: modelData.d
                            font.pixelSize: 10
                            color: clipboardWindow.textFaint
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
