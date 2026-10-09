import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.tasks
import "tasks/Parse.js" as Parse

// Task dashboard. Standalone, bind a key to:
//   quickshell -p ~/.config/quickshell/tasks.qml
//
// Launching per keypress is the laziest possible lazy-load: the whole
// thing exists only while it is open, so idle cost is exactly zero.
//
// Tasks live in an Obsidian vault synced with Syncthing. Obsidian's own
// checkbox toggle writes "[x]" and nothing else -- no plugin, so no
// completion date -- which makes this dashboard the only thing that
// ever writes dates. It stamps undated ticks when it opens.
//
// LAYOUT, because an earlier version got this badly wrong: the card is
// a fixed shell with the header pinned to the top, the add row pinned
// to the bottom, and the list anchored BETWEEN them. It is not a
// Column with the list height guessed by subtracting magic numbers --
// that guess was wrong whenever a banner appeared or a picker opened,
// and the card grew taller than the screen with its contents clipped
// off both ends.
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-tasks"

    color: "transparent"

    // The id is deliberately NOT `store`. Writing `store: store` on a
    // child view resolves the right-hand side against that view's own
    // properties first, so it binds to itself: the view receives
    // undefined and collapses to zero height with no error anywhere.
    Store { id: taskStore }

    readonly property string todayIso: Parse.today()

    // ---- transient UI state ------------------------------------------

    property string filterCat: ""
    property string searchText: ""
    property string editingRaw: ""
    property string confirmRaw: ""

    property int tab: 0                // 0 tasks, 1 stats, 2 settings
    readonly property var tabNames: ["TASKS", "STATS", "SETTINGS"]

    property var folded: ({ open: false, done: false, cancelled: true })
    function toggleFold(key) {
        const f = {};
        for (const k in folded) f[k] = folded[k];
        f[key] = !f[key];
        folded = f;
    }

    // ---- one dropdown, shared by every picker ------------------------

    property string pickerKey: ""
    property var pickerAnchor: null
    property var pickerOptions: []
    property var pickerCurrent: null
    property string pickerPlaceholder: "none"
    property var pickerApply: null

    function showPicker(key, anchorItem, options, current, placeholder, apply) {
        if (pickerKey === key) { closePicker(); return; }
        pickerKey = key;
        pickerAnchor = anchorItem;
        pickerOptions = options;
        pickerCurrent = current;
        pickerPlaceholder = placeholder;
        pickerApply = apply;
    }
    function closePicker() {
        pickerKey = "";
        pickerAnchor = null;
        pickerApply = null;
    }

    // ---- deferred write, so a state change is visible ----------------
    //
    // A row stays on screen, animating, for one beat before its write
    // goes out. This only DELAYS the write, never fakes the result: the
    // row moves because the file changed, so a failed write leaves it
    // where it was with the error banner showing.

    property string vanishingRaw: ""
    property string vanishingAction: ""

    Timer {
        id: vanishTimer
        interval: 180
        onTriggered: {
            const raw = root.vanishingRaw;
            const what = root.vanishingAction;
            root.vanishingRaw = "";
            root.vanishingAction = "";
            switch (what) {
            case "tick":     taskStore.tick(raw); break;
            case "untick":   taskStore.untick(raw); break;
            case "cancel":   taskStore.cancel(raw); break;
            case "uncancel": taskStore.uncancel(raw); break;
            }
        }
    }

    function act(raw, what) {
        if (vanishingRaw !== "" || taskStore.busy) return;
        vanishingRaw = raw;
        vanishingAction = what;
        vanishTimer.restart();
    }

    // ---- model -------------------------------------------------------

    function matchesFilter(t) {
        if (filterCat !== "" && (t.category ?? "uncategorized") !== filterCat) return false;
        if (searchText !== "") {
            const q = searchText.toLowerCase();
            if (t.text.toLowerCase().indexOf(q) === -1
                && (t.category ?? "").toLowerCase().indexOf(q) === -1) return false;
        }
        return true;
    }

    // Importance first (1 is most urgent), then category, then text. A
    // task with no !N sorts last, rather than sorting as zero.
    function byPriority(a, b) {
        const ai = a.importance === null ? 9999 : a.importance;
        const bi = b.importance === null ? 9999 : b.importance;
        if (ai !== bi) return ai - bi;
        const ac = a.category ?? "￿";
        const bc = b.category ?? "￿";
        if (ac !== bc) return ac.localeCompare(bc);
        return a.text.localeCompare(b.text);
    }

    readonly property var openTasks:
        taskStore.tasks.filter((t) => t.open && matchesFilter(t)).slice().sort(byPriority)

    readonly property var doneToday:
        taskStore.tasks.filter((t) => t.done && !t.cancelled
                                   && t.effectiveDate === todayIso
                                   && matchesFilter(t))

    readonly property int cancelledCap: 50
    readonly property var cancelledAll:
        taskStore.tasks.filter((t) => t.cancelled && matchesFilter(t))

    // One flat model of headers and rows, so the list is a single
    // ListView with one delegate rather than three repeaters.
    readonly property var rows: {
        const out = [];
        // With nothing done or cancelled there is only one list, and a
        // header over it is pure noise.
        const sectioned = (doneToday.length > 0) || (cancelledAll.length > 0);

        if (sectioned)
            out.push({ kind: "header", key: "open", label: "OPEN", count: openTasks.length });
        if (!sectioned || !folded.open)
            for (const t of openTasks) out.push({ kind: "task", t: t, mode: "open" });

        if (doneToday.length > 0) {
            out.push({ kind: "header", key: "done", label: "DONE TODAY",
                       count: doneToday.length });
            if (!folded.done)
                for (const t of doneToday) out.push({ kind: "task", t: t, mode: "done" });
        }

        if (cancelledAll.length > 0) {
            out.push({ kind: "header", key: "cancelled", label: "CANCELLED",
                       count: cancelledAll.length });
            if (!folded.cancelled) {
                const shown = cancelledAll.slice(0, cancelledCap);
                for (const t of shown) out.push({ kind: "task", t: t, mode: "cancelled" });
                if (cancelledAll.length > shown.length)
                    out.push({ kind: "note",
                               text: "+" + (cancelledAll.length - shown.length)
                                   + " more, in tasks.md" });
            }
        }
        return out;
    }

    readonly property var liveCats: {
        const seen = {};
        for (const t of taskStore.tasks) if (t.open) seen[t.category ?? "uncategorized"] = true;
        return Object.keys(seen).sort();
    }

    readonly property var catOptions:
        taskStore.config.categories.map((c) => ({ name: c.name, color: c.color }))
    readonly property var filterOptions:
        liveCats.map((n) => ({ name: n, color: catColor(n) }))

    function catColor(name) {
        for (const c of taskStore.config.categories) if (c.name === name) return c.color;
        return Colors.textFaint;
    }
    function impColor(level) {
        for (const i of taskStore.config.importance) if (i.level === level) return i.color;
        return Colors.textFaint;
    }

    // ---- window behaviour --------------------------------------------

    function handleEscape() {
        if (root.pickerKey !== "") { root.closePicker(); return; }
        if (root.confirmRaw !== "") { root.confirmRaw = ""; return; }
        if (root.editingRaw !== "") { root.editingRaw = ""; return; }
        Qt.quit();
    }

    // Handled before key events reach any item, so it fires whatever
    // has focus -- including nothing, which is the case the moment you
    // click a chip or a row.
    Shortcut {
        sequences: ["Escape"]
        context: Qt.ApplicationShortcut
        onActivated: root.handleEscape()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Qt.quit()
    }

    // ==================================================================
    // card
    // ==================================================================

    Rectangle {
        id: card

        readonly property int pad: 16

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((root.height - height) / 2)
        implicitWidth: 760

        // FIXED. Not derived from content.
        //
        // A card sized to its contents re-laid-out on every tick,
        // delete, fold and tab change -- the whole panel jumped under
        // the cursor while you were using it, and the button you were
        // about to click moved. A constant height costs some empty
        // space on a short list and is worth it: the list scrolls
        // inside a frame that never moves.
        //
        // Clamped so it is neither cramped on a laptop panel nor
        // absurdly tall on a 1440p monitor.
        implicitHeight: Math.max(420, Math.min(780, Math.round(root.height * 0.72)))

        radius: 16
        color: Colors.base
        border.width: 1
        border.color: Colors.outline
        clip: true

        opacity: 0
        scale: 0.975
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; onClicked: root.closePicker() }

        // ---- header (pinned top) -------------------------------------

        Column {
            id: headerCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: card.pad
            spacing: 10

            Item {
                width: parent.width
                height: 26
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Tasks"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Colors.textMain
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.openTasks.length + " open"
                            + (root.doneToday.length > 0
                               ? "  ·  " + root.doneToday.length + " done today" : "")
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        color: Colors.textFaint
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: taskStore.busy
                        text: "saving…"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        color: Colors.warn
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: root.tabNames
                        Chip {
                            required property var modelData
                            required property int index
                            label: modelData
                            tint: Colors.accent
                            active: root.tab === index
                            onClicked: { root.closePicker(); root.tab = index; }
                        }
                    }
                    TinyBtn { label: "esc"; onClicked: Qt.quit() }
                }
            }

            Rectangle {
                visible: taskStore.hasConflicts
                width: parent.width
                implicitHeight: conflictText.implicitHeight + 14
                radius: 8
                color: Qt.alpha(Colors.warn, 0.12)
                border.width: 1
                border.color: Qt.alpha(Colors.warn, 0.45)
                Text {
                    id: conflictText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 7
                    text: "⚠  Syncthing conflict copies in the Tasker folder — "
                        + "tasks may be split across them."
                    wrapMode: Text.WordWrap
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    lineHeight: 1.3
                    color: Colors.warn
                }
            }

            Rectangle {
                visible: taskStore.error !== ""
                width: parent.width
                implicitHeight: errText.implicitHeight + 14
                radius: 8
                color: Qt.alpha(Colors.danger, 0.12)
                border.width: 1
                border.color: Qt.alpha(Colors.danger, 0.45)
                Text {
                    id: errText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 7
                    text: taskStore.error
                    wrapMode: Text.WordWrap
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    lineHeight: 1.3
                    color: Colors.danger
                }
            }

            Text {
                visible: taskStore.migratedCount > 0
                width: parent.width
                text: "Converted " + taskStore.migratedCount + " category marker"
                    + (taskStore.migratedCount === 1 ? "" : "s")
                    + " from #name to @name, so Obsidian stops indexing them as tags."
                wrapMode: Text.WordWrap
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                color: Colors.textFaint
            }

            Text {
                visible: taskStore.stampedCount > 0
                width: parent.width
                text: "Dated " + taskStore.stampedCount + " task"
                    + (taskStore.stampedCount === 1 ? "" : "s")
                    + " ticked elsewhere, using today's date."
                wrapMode: Text.WordWrap
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                color: Colors.textFaint
            }

            Item {
                visible: root.tab === 0
                width: parent.width
                height: 28

                Field {
                    id: searchField
                    anchors.left: parent.left
                    anchors.right: filterBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28
                    fontSize: 11
                    placeholder: "search tasks…"
                    text: root.searchText
                    onEdited: root.searchText = text
                }

                PickerButton {
                    id: filterBtn
                    anchors.right: clearBtn.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 150
                    placeholder: "all categories"
                    current: root.filterCat === "" ? null : root.filterCat
                    dotColor: root.catColor(root.filterCat)
                    open: root.pickerKey === "filter"
                    onToggled: root.showPicker("filter", filterBtn, root.filterOptions,
                                               root.filterCat === "" ? null : root.filterCat,
                                               "all categories",
                                               (v) => root.filterCat = (v === null ? "" : v))
                }

                TinyBtn {
                    id: clearBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: (root.searchText !== "" || root.filterCat !== "") ? 1 : 0
                    label: "clear"
                    onClicked: {
                        root.searchText = "";
                        searchField.text = "";
                        root.filterCat = "";
                    }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }

            Rectangle {
                visible: root.tab === 0
                width: parent.width
                height: 1
                color: Colors.outline
            }
        }

        // ---- list (fills the gap between header and footer) ----------

        ListView {
            id: list
            visible: root.tab === 0
            anchors.top: headerCol.bottom
            anchors.topMargin: 6
            anchors.bottom: footer.top
            anchors.bottomMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            clip: true
            model: root.rows
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            // The dropdown is positioned against a trigger in card
            // coordinates, so scrolling would leave it pointing at
            // nothing. Close it rather than track it.
            onContentYChanged: if (root.pickerKey !== "" && dragging) root.closePicker()

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
            }
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 170; easing.type: Easing.OutCubic }
            }

            delegate: Item {
                id: rowItem
                required property var modelData
                required property int index

                readonly property bool isTask: modelData.kind === "task"
                readonly property var task: modelData.kind === "task" ? modelData.t : null
                readonly property string mode: modelData.kind === "task" ? modelData.mode : ""

                readonly property bool editing: isTask && root.editingRaw === task.raw
                readonly property bool confirming: isTask && root.confirmRaw === task.raw
                readonly property bool vanishing: isTask && root.vanishingRaw === task.raw

                // Editor state lives on the delegate, seeded each time
                // the editor opens, so reopening after a cancelled edit
                // does not resurrect stale pickers.
                property var editCat: null
                property var editImp: null
                onEditingChanged: if (editing) {
                    editCat = task.category;
                    editImp = task.importance;
                }

                width: list.width
                implicitHeight: modelData.kind === "header" ? 24
                              : modelData.kind === "note" ? 20
                              : taskBg.implicitHeight
                height: implicitHeight

                // ---- section header ----------------------------------

                Item {
                    visible: rowItem.modelData.kind === "header"
                    anchors.fill: parent

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.folded[rowItem.modelData.key ?? "open"] ? "▸" : "▾"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            color: Colors.textFaint
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (rowItem.modelData.label ?? "") + "  "
                                + (rowItem.modelData.count ?? 0)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            color: Colors.textFaint
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleFold(rowItem.modelData.key)
                    }
                }

                Text {
                    visible: rowItem.modelData.kind === "note"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    text: rowItem.modelData.text ?? ""
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    color: Colors.textFaint
                }

                // ---- task row ----------------------------------------

                Rectangle {
                    id: taskBg
                    visible: rowItem.isTask
                    width: parent.width
                    // 30px for a plain row. The old 37 made 27 tasks
                    // look like a settings page.
                    implicitHeight: rowCol.implicitHeight + 10
                    radius: 7

                    // The whole row carries its importance colour, not
                    // just a sliver at the edge. Kept low-alpha so the
                    // text stays the brightest thing in the row and a
                    // list of urgent tasks does not turn into a wall of
                    // red -- and the hover step stays visible on top of
                    // the tint, which a flat fill would have swallowed.
                    color: {
                        if (!rowItem.isTask) return "transparent";
                        const hovered = rowHover.hovered || rowItem.editing
                                        || rowItem.confirming;
                        if (rowItem.task.importance !== null) {
                            // Done and cancelled rows are faded: their
                            // priority is history, not a call to act.
                            const base = rowItem.mode === "open" ? 0.14 : 0.05;
                            return Qt.alpha(root.impColor(rowItem.task.importance),
                                            hovered ? base + 0.10 : base);
                        }
                        return hovered ? Colors.surface0 : "transparent";
                    }
                    Behavior on color { ColorAnimation { duration: 120 } }

                    opacity: rowItem.vanishing ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                    }

                    // Importance as a bar down the left edge rather than
                    // a dot on the right: it reads as a property of the
                    // row, and a list sorted by importance gets a
                    // visible gradient instead of scattered dots.
                    Rectangle {
                        visible: rowItem.isTask && rowItem.task.importance !== null
                        anchors.left: parent.left
                        anchors.leftMargin: 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: Math.max(0, parent.height - 12)
                        radius: 2
                        color: rowItem.isTask && rowItem.task.importance !== null
                            ? root.impColor(rowItem.task.importance) : "transparent"
                        opacity: rowItem.mode === "open" ? 1 : 0.4
                    }

                    // A HoverHandler, not a hoverEnabled MouseArea:
                    // a MouseArea here loses hover the instant the
                    // cursor crosses onto a button inside it, and the
                    // buttons are shown BECAUSE the row is hovered.
                    // That fed back on itself and flickered.
                    HoverHandler { id: rowHover }

                    Column {
                        id: rowCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 5
                        anchors.leftMargin: 11
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 20

                            Rectangle {
                                id: box
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 15
                                height: 15
                                radius: 5
                                color: "transparent"
                                border.width: 1
                                border.color: rowItem.vanishing || boxHover.hovered
                                    ? Colors.accent
                                    : rowItem.mode === "open"
                                        ? Colors.outline : Qt.alpha(Colors.outline, 0.6)
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                Rectangle {
                                    anchors.centerIn: parent
                                    readonly property bool full:
                                        rowItem.vanishing || rowItem.mode === "done"
                                    width: full ? 15 : 7
                                    height: width
                                    radius: full ? 5 : 3
                                    color: rowItem.mode === "cancelled"
                                        ? Colors.textFaint : Colors.accent
                                    opacity: full ? 1
                                           : rowItem.mode === "cancelled" ? 0.35
                                           : boxHover.hovered ? 0.5 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    Behavior on width {
                                        NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                                    }
                                    Behavior on radius { NumberAnimation { duration: 150 } }
                                }

                                HoverHandler {
                                    id: boxHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    onTapped: {
                                        if (rowItem.mode === "open")
                                            root.act(rowItem.task.raw, "tick");
                                        else if (rowItem.mode === "done")
                                            root.act(rowItem.task.raw, "untick");
                                        else
                                            root.act(rowItem.task.raw, "uncancel");
                                    }
                                }
                            }

                            Text {
                                visible: !rowItem.editing
                                anchors.left: box.right
                                anchors.leftMargin: 9
                                anchors.right: rowTags.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: rowItem.isTask ? rowItem.task.text : ""
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.strikeout: rowItem.vanishing || rowItem.mode !== "open"
                                color: rowItem.vanishing || rowItem.mode !== "open"
                                    ? Colors.textFaint : Colors.textMain
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }

                            Item {
                                id: rowTags
                                anchors.right: rowActions.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !rowItem.editing
                                width: catPill.visible ? catPill.width : 0
                                height: 17

                                Rectangle {
                                    id: catPill
                                    visible: rowItem.isTask && rowItem.task.category !== null
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                    implicitWidth: catLbl.implicitWidth + 13
                                    width: implicitWidth
                                    height: 17
                                    radius: 8
                                    opacity: rowItem.mode === "open" ? 1 : 0.5
                                    color: rowItem.isTask && rowItem.task.category
                                        ? Qt.alpha(root.catColor(rowItem.task.category), 0.18)
                                        : "transparent"
                                    Text {
                                        id: catLbl
                                        anchors.centerIn: parent
                                        text: rowItem.isTask ? (rowItem.task.category ?? "") : ""
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                        color: rowItem.isTask && rowItem.task.category
                                            ? root.catColor(rowItem.task.category)
                                            : Colors.textFaint
                                    }
                                }
                            }

                            Row {
                                id: rowActions
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                // Always laid out, only faded. Hiding
                                // it with `visible` changed the width
                                // available to the text and the
                                // category pill, so everything in the
                                // row jumped sideways on hover.
                                readonly property bool shown:
                                    rowHover.hovered || rowItem.editing || rowItem.confirming
                                opacity: shown ? 1 : 0
                                enabled: shown
                                Behavior on opacity { NumberAnimation { duration: 110 } }

                                TinyBtn {
                                    visible: rowItem.mode === "open"
                                    label: rowItem.editing ? "close" : "edit"
                                    onClicked: {
                                        root.closePicker();
                                        root.editingRaw = rowItem.editing ? "" : rowItem.task.raw;
                                    }
                                }
                                TinyBtn {
                                    visible: rowItem.mode === "open"
                                    label: "cancel"
                                    onClicked: root.act(rowItem.task.raw, "cancel")
                                }
                                TinyBtn {
                                    visible: rowItem.mode === "done"
                                    label: "undo"
                                    onClicked: root.act(rowItem.task.raw, "untick")
                                }
                                TinyBtn {
                                    visible: rowItem.mode === "cancelled"
                                    label: "restore"
                                    tint: Colors.accent
                                    onClicked: root.act(rowItem.task.raw, "uncancel")
                                }
                                TinyBtn {
                                    label: rowItem.confirming ? "sure?" : "delete"
                                    tint: Colors.danger
                                    onClicked: {
                                        if (rowItem.confirming) {
                                            taskStore.remove(rowItem.task.raw);
                                            root.confirmRaw = "";
                                        } else {
                                            root.confirmRaw = rowItem.task.raw;
                                        }
                                    }
                                }
                            }
                        }

                        // ---- inline editor -------------------------

                        Column {
                            visible: rowItem.editing
                            width: parent.width
                            spacing: 6

                            Field {
                                id: editText
                                width: parent.width
                                height: 28
                                text: rowItem.isTask ? rowItem.task.text : ""
                                placeholder: "task text"
                                Component.onCompleted: focusInput()
                                onSubmitted: editSave.clicked()
                            }

                            Item {
                                width: parent.width
                                height: 26

                                PickerButton {
                                    id: editCatBtn
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 170
                                    placeholder: "no category"
                                    current: rowItem.editCat
                                    dotColor: root.catColor(rowItem.editCat)
                                    open: root.pickerKey === "edit"
                                    onToggled: root.showPicker("edit", editCatBtn,
                                                               root.catOptions, rowItem.editCat,
                                                               "no category",
                                                               (v) => rowItem.editCat = v)
                                }

                                Row {
                                    anchors.left: editCatBtn.right
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 5
                                    Chip {
                                        label: "—"
                                        active: rowItem.editImp === null
                                        onClicked: rowItem.editImp = null
                                    }
                                    Repeater {
                                        model: taskStore.config.importance
                                        Chip {
                                            required property var modelData
                                            label: "!" + modelData.level
                                            tint: modelData.color
                                            active: rowItem.editImp === modelData.level
                                            onClicked: rowItem.editImp = modelData.level
                                        }
                                    }
                                }

                                TinyBtn {
                                    id: editSave
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "save"
                                    tint: Colors.accent
                                    onClicked: {
                                        taskStore.edit(rowItem.task.raw, {
                                            text: editText.text,
                                            category: rowItem.editCat,
                                            importance: rowItem.editImp
                                        });
                                        root.editingRaw = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Thin scroll indicator: with 27 tasks there was no sign the
        // list continued past the fold.
        Rectangle {
            visible: root.tab === 0 && list.contentHeight > list.height
            width: 3
            radius: 2
            color: Qt.alpha(Colors.textFaint, 0.45)
            x: card.width - 8
            height: Math.max(24, list.height * (list.height / Math.max(1, list.contentHeight)))
            y: list.y + (list.contentHeight > list.height
                ? (list.contentY / (list.contentHeight - list.height)) * (list.height - height)
                : 0)
        }

        Text {
            visible: root.tab === 0 && taskStore.loaded && root.rows.length === 0
            anchors.top: headerCol.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.leftMargin: card.pad
            anchors.right: parent.right
            anchors.rightMargin: card.pad
            text: taskStore.tasks.length === 0
                ? "No tasks file yet at\n" + taskStore.tasksPath
                : (root.searchText !== "" || root.filterCat !== "")
                    ? "Nothing matches." : "All clear."
            wrapMode: Text.WordWrap
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            lineHeight: 1.4
            color: Colors.textFaint
        }

        // ---- add row (pinned bottom) ---------------------------------

        Column {
            id: footer
            visible: root.tab === 0
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: card.pad
            spacing: 8

            Rectangle { width: parent.width; height: 1; color: Colors.outline }

            Item {
                width: parent.width
                height: 30

                Field {
                    id: addText
                    anchors.left: parent.left
                    anchors.right: addGo.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 30
                    placeholder: "new task…"
                    Component.onCompleted: focusInput()
                    onSubmitted: addGo.clicked()
                }
                TinyBtn {
                    id: addGo
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: "add"
                    tint: Colors.accent
                    onClicked: {
                        if (addText.text.trim() === "") return;
                        taskStore.add({
                            text: addText.text,
                            category: addPick.cat,
                            importance: addPick.imp
                        });
                        addText.text = "";
                        addText.focusInput();
                    }
                }
            }

            Item {
                id: addPick
                property var cat: null
                property var imp: null
                width: parent.width
                height: 26

                PickerButton {
                    id: addCatBtn
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 190
                    placeholder: "no category"
                    current: addPick.cat
                    dotColor: root.catColor(addPick.cat)
                    open: root.pickerKey === "add"
                    onToggled: root.showPicker("add", addCatBtn, root.catOptions,
                                               addPick.cat, "no category",
                                               (v) => addPick.cat = v)
                }

                Row {
                    anchors.left: addCatBtn.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Chip {
                        label: "—"
                        active: addPick.imp === null
                        onClicked: addPick.imp = null
                    }
                    Repeater {
                        model: taskStore.config.importance
                        Chip {
                            required property var modelData
                            label: "!" + modelData.level
                            tint: modelData.color
                            active: addPick.imp === modelData.level
                            onClicked: addPick.imp = modelData.level
                        }
                    }
                }
            }
        }

        // ---- stats / settings ----------------------------------------

        Flickable {
            id: altBodyFlick
            visible: root.tab !== 0
            anchors.top: headerCol.bottom
            anchors.topMargin: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: card.pad
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            contentHeight: altBody.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Item {
                id: altBody
                width: altBodyFlick.width
                implicitHeight: root.tab === 2 ? settingsView.implicitHeight
                              : root.tab === 1 ? statsView.implicitHeight : 0

                SettingsView {
                    id: settingsView
                    visible: root.tab === 2
                    width: parent.width
                    store: taskStore
                }
                StatsView {
                    id: statsView
                    visible: root.tab === 1
                    width: parent.width
                    store: taskStore
                }
            }
        }

        // ---- the one dropdown -----------------------------------------
        //
        // Positioned against whichever trigger is open, clamped to the
        // card, flipped above the trigger when there is no room below.
        // Being a child of the card, it cannot be drawn outside it --
        // which is exactly what the old inline lists did, rendering the
        // options onto the desktop below the card's bottom edge.

        Item {
            id: pickerLayer
            anchors.fill: parent
            z: 100
            visible: root.pickerKey !== ""

            MouseArea {
                anchors.fill: parent
                onClicked: root.closePicker()
            }

            Rectangle {
                id: pop

                readonly property point src: root.pickerAnchor
                    ? root.pickerAnchor.mapToItem(card, 0, 0) : Qt.point(0, 0)
                readonly property real anchorH: root.pickerAnchor ? root.pickerAnchor.height : 0
                readonly property bool below: src.y + anchorH + 4 + height < card.height - 8

                readonly property var filtered: {
                    const q = popSearch.text.toLowerCase().trim();
                    if (q === "") return root.pickerOptions;
                    // Prefix matches first: typing "ho" puts "home"
                    // above "household chores".
                    const pre = [];
                    const sub = [];
                    for (const o of root.pickerOptions) {
                        const n = o.name.toLowerCase();
                        if (n.startsWith(q)) pre.push(o);
                        else if (n.indexOf(q) !== -1) sub.push(o);
                    }
                    return pre.concat(sub);
                }

                width: Math.max(210, root.pickerAnchor ? root.pickerAnchor.width : 210)
                height: Math.min(268, popBody.implicitHeight + 12)
                x: Math.max(8, Math.min(src.x, card.width - width - 8))
                y: below ? src.y + anchorH + 4 : Math.max(8, src.y - height - 4)

                radius: 9
                color: Colors.mantle
                border.width: 1
                border.color: Qt.alpha(Colors.accent, 0.4)

                Column {
                    id: popBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 6
                    spacing: 5

                    Field {
                        id: popSearch
                        width: parent.width
                        height: 26
                        fontSize: 11
                        placeholder: "filter…"
                        onSubmitted: {
                            if (pop.filtered.length > 0 && root.pickerApply) {
                                root.pickerApply(pop.filtered[0].name);
                                root.closePicker();
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 24
                        radius: 6
                        visible: popSearch.text === ""
                        color: noneMouse.containsMouse ? Colors.surface1 : "transparent"
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.pickerPlaceholder
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            color: root.pickerCurrent === null ? Colors.accent : Colors.textFaint
                        }
                        MouseArea {
                            id: noneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.pickerApply) root.pickerApply(null);
                                root.closePicker();
                            }
                        }
                    }

                    ListView {
                        id: popList
                        width: parent.width
                        height: Math.min(contentHeight, 180)
                        clip: true
                        model: pop.filtered
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: optRow
                            required property var modelData
                            width: popList.width
                            height: 24
                            radius: 6
                            readonly property bool chosen: root.pickerCurrent === modelData.name
                            color: optMouse.containsMouse ? Colors.surface1
                                 : chosen ? Qt.alpha(Colors.accent, 0.12) : "transparent"

                            Rectangle {
                                id: optDot
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: optRow.modelData.color ?? Colors.textFaint
                            }
                            Text {
                                anchors.left: optDot.right
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: optRow.modelData.name
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.weight: optRow.chosen ? Font.DemiBold : Font.Normal
                                color: optRow.chosen ? Colors.accent : Colors.textMain
                            }
                            MouseArea {
                                id: optMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.pickerApply) root.pickerApply(optRow.modelData.name);
                                    root.closePicker();
                                }
                            }
                        }
                    }

                    Text {
                        visible: pop.filtered.length === 0
                        text: "no match"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        color: Colors.textFaint
                    }
                }
            }
        }
    }

    // Clear and focus the dropdown's filter each time one opens, so a
    // long category list is reachable by typing straight away.
    onPickerKeyChanged: {
        popSearch.text = "";
        if (pickerKey !== "") popSearch.focusInput();
    }
}
