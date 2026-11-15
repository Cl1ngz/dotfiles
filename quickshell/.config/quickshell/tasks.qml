// Task dashboard. Standalone, bind a key to:
//   quickshell -p ~/.config/quickshell/tasks.qml
// Launching per keypress is the laziest possible lazy-load: the whole
// thing exists only while it is open, so idle cost is exactly zero.
//
// Keyboard, vim style. It opens in INSERT on the new-task field: type,
// Enter, done (Ctrl+Enter adds and closes). Esc drops to NORMAL, where
// j/k move, space ticks, e edits, dd deletes, / searches, ? lists the
// rest. Esc in NORMAL (or q) closes.
//
// Tasks live in an Obsidian vault synced with Syncthing. Obsidian's own
// checkbox toggle writes "[x]" and nothing else -- no plugin, so no
// completion date -- which makes this dashboard the only thing that
// ever writes dates. It stamps undated ticks when it opens.

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.tasks
import "tasks/Parse.js" as Parse

// LAYOUT, because an earlier version got this badly wrong: the card is
// a fixed shell with the header pinned to the top, the add row pinned
// to the bottom, and the list anchored BETWEEN them. It is not a
// Column with the list height guessed by subtracting magic numbers --
// that guess was wrong whenever a banner appeared or a picker opened,
// and the card grew taller than the screen with its contents clipped
// off both ends.
PanelWindow {
    // ---- transient UI state ------------------------------------------
    // ---- one dropdown, shared by every picker ------------------------
    // ---- deferred write, so a state change is visible ----------------
    // A row stays on screen, animating, for one beat before its write
    // goes out. This only DELAYS the write, never fakes the result: the
    // row moves because the file changed, so a failed write leaves it
    // where it was with the error banner showing.
    // ---- model -------------------------------------------------------
    // ---- window behaviour --------------------------------------------
    // ==================================================================
    // card
    // ==================================================================

    id: root

    readonly property string todayIso: Parse.today()
    property string filterCat: ""
    property string searchText: ""
    property string editingRaw: ""
    property string confirmRaw: ""
    property int tab: 0 // 0 tasks, 1 stats, 2 settings
    readonly property var tabNames: ["TASKS", "STATS", "SETTINGS"]
    property var folded: ({
        "open": false,
        "done": false,
        "cancelled": true
    })
    property string pickerKey: ""
    property var pickerAnchor: null
    property var pickerOptions: []
    property var pickerCurrent: null
    property string pickerPlaceholder: "none"
    property var pickerApply: null
    property string vanishingRaw: ""
    property string vanishingAction: ""

    // ---- keyboard ----------------------------------------------------
    //
    // NORMAL mode is `nav` having focus; INSERT is any text field having
    // it. There is no separate mode variable to drift out of sync with
    // where the keys actually go.
    readonly property bool normalMode: nav.activeFocus
    // The selected row. Tracked by key as well as index, so a write that
    // reshuffles the list keeps the cursor on the same task; selAfter /
    // selBefore are where it goes when that task leaves the list (ticked,
    // deleted), like the cursor after dd in vim.
    property int selIndex: -1
    property string selKey: ""
    property string selAfter: ""
    property string selBefore: ""
    // Set when a change will rewrite the selected task's line: the line
    // it is expected to become, so the cursor can follow it.
    property string pendingSelRaw: ""
    // First key of a two-key command: gg, gt, gT, dd, za.
    property string pending: ""
    property bool showHelp: false
    property bool quitWhenIdle: false
    property bool ready: false
    property var pickerReturn: null
    property bool pickerNarrow: false
    property int pickerHi: 0
    property string editDraft: ""
    readonly property var focusItem: card.Window.activeFocusItem
    readonly property var catNames: taskStore.config.categories.map((c) => {
        return c.name;
    })
    readonly property var addSuggest: suggestFor(addText.text)
    readonly property var editSuggest: editingRaw !== "" ? suggestFor(editDraft) : []
    readonly property var selRow: selIndex >= 0 && selIndex < rows.length ? rows[selIndex] : null
    readonly property string confirmLabel: {
        const t = taskStore.tasks.find((x) => {
            return x.raw === confirmRaw;
        });
        const s = t ? t.text : "";
        return s.length > 40 ? s.slice(0, 39) + "…" : s;
    }
    readonly property string hint: {
        if (showHelp)
            return "? or esc  close help";

        if (pickerKey !== "")
            return "type to filter · ↑ ↓  ctrl+n ctrl+p  move · enter pick · esc close";

        if (confirmRaw !== "")
            return normalMode ? "delete “" + confirmLabel + "”?   y  yes · any other key  no" : "click “sure?” to delete · esc keeps it";

        if (addText.inputFocused)
            return addSuggest.length > 0 ? "tab →  @" + addSuggest.join("   @") : "enter add · ctrl+enter add & close · @category !1 inline · esc normal mode";

        if (searchField.inputFocused)
            return "type to search · enter or ↓  to the list · esc normal mode";

        if (editingRaw !== "" && !normalMode)
            return editSuggest.length > 0 ? "tab →  @" + editSuggest.join("   @") : "enter save · @category !1 inline · esc cancel";

        if (!normalMode)
            return tab === 2 ? "tab / shift+tab  next field · ctrl+s save · esc normal mode" : "esc normal mode";

        if (tab === 1)
            return "h l  range · j k  scroll · gt gT  tabs · q quit · ?  help";

        if (tab === 2)
            return "tab or i  into the fields · ctrl+s save · j k  scroll · gt gT  tabs · ?  help";

        return "j k move · space done · e edit · c cancel · dd delete · @ category · 1-9 importance · / search · a add · ? help";
    }
    readonly property var openTasks: taskStore.tasks.filter((t) => {
        return t.open && matchesFilter(t);
    }).slice().sort(byPriority)
    readonly property var doneToday: taskStore.tasks.filter((t) => {
        return t.done && !t.cancelled && t.effectiveDate === todayIso && matchesFilter(t);
    })
    readonly property int cancelledCap: 50
    readonly property var cancelledAll: taskStore.tasks.filter((t) => {
        return t.cancelled && matchesFilter(t);
    })
    // One flat model of headers and rows, so the list is a single
    // ListView with one delegate rather than three repeaters.
    readonly property var rows: {
        const out = [];
        // With nothing done or cancelled there is only one list, and a
        // header over it is pure noise.
        const sectioned = (doneToday.length > 0) || (cancelledAll.length > 0);
        if (sectioned)
            out.push({
            "kind": "header",
            "key": "open",
            "label": "OPEN",
            "count": openTasks.length
        });

        if (!sectioned || !folded.open)
            for (const t of openTasks) out.push({
            "kind": "task",
            "t": t,
            "mode": "open"
        });

        if (doneToday.length > 0) {
            out.push({
                "kind": "header",
                "key": "done",
                "label": "DONE TODAY",
                "count": doneToday.length
            });
            if (!folded.done)
                for (const t of doneToday) out.push({
                "kind": "task",
                "t": t,
                "mode": "done"
            });

        }
        if (cancelledAll.length > 0) {
            out.push({
                "kind": "header",
                "key": "cancelled",
                "label": "CANCELLED",
                "count": cancelledAll.length
            });
            if (!folded.cancelled) {
                const shown = cancelledAll.slice(0, cancelledCap);
                for (const t of shown) out.push({
                    "kind": "task",
                    "t": t,
                    "mode": "cancelled"
                })
                if (cancelledAll.length > shown.length)
                    out.push({
                    "kind": "note",
                    "text": "+" + (cancelledAll.length - shown.length) + " more, in tasks.md"
                });

            }
        }
        return out;
    }
    readonly property var liveCats: {
        const seen = {
        };
        for (const t of taskStore.tasks) if (t.open) {
            seen[t.category ?? "uncategorized"] = true;
        }
        return Object.keys(seen).sort();
    }
    readonly property var catOptions: taskStore.config.categories.map((c) => {
        return ({
            "name": c.name,
            "color": c.color
        });
    })
    readonly property var filterOptions: liveCats.map((n) => {
        return ({
            "name": n,
            "color": catColor(n)
        });
    })

    function toggleFold(key) {
        const f = {
        };
        for (const k in folded) f[k] = folded[k]
        f[key] = !f[key];
        folded = f;
    }

    function showPicker(key, anchorItem, options, current, placeholder, apply, narrow) {
        if (pickerKey === key) {
            closePicker();
            return ;
        }
        // Where the keyboard was, so closing the picker puts it back.
        if (pickerKey === "")
            pickerReturn = focusItem;

        pickerAnchor = anchorItem;
        pickerOptions = options;
        pickerCurrent = current;
        pickerPlaceholder = placeholder;
        pickerApply = apply;
        pickerNarrow = narrow === true;
        // Last: onPickerKeyChanged reads the options set above.
        pickerKey = key;
    }

    function closePicker() {
        if (pickerKey === "")
            return ;

        const back = pickerReturn;
        pickerKey = "";
        pickerAnchor = null;
        pickerApply = null;
        pickerReturn = null;
        pickerNarrow = false;
        if (back && back.visible)
            back.forceActiveFocus();
        else
            toNormal();
    }

    // ---- picker by keyboard -------------------------------------------

    function pickerCount() {
        return (pop.noneShown ? 1 : 0) + pop.filtered.length;
    }

    function movePicker(delta) {
        const n = pickerCount();
        if (n === 0)
            return ;

        pickerHi = Math.max(0, Math.min(n - 1, pickerHi + delta));
        const li = pickerHi - (pop.noneShown ? 1 : 0);
        if (li >= 0)
            popList.positionViewAtIndex(li, ListView.Contain);

    }

    function pickAt(i) {
        const fn = pickerApply;
        if (!fn) {
            closePicker();
            return ;
        }
        if (pop.noneShown && i === 0) {
            fn(null);
        } else {
            const o = pop.filtered[i - (pop.noneShown ? 1 : 0)];
            if (o === undefined)
                return ;

            fn(o.name);
        }
        closePicker();
    }

    // A second action while the first is still animating no longer gets
    // dropped: the first is sent straight away and the new one starts.
    // Space, j, space must tick two tasks, not one.
    function act(raw, what) {
        if (vanishTimer.running) {
            vanishTimer.stop();
            fireVanish();
        }
        vanishingRaw = raw;
        vanishingAction = what;
        vanishTimer.restart();
    }

    function matchesFilter(t) {
        if (filterCat !== "" && (t.category ?? "uncategorized") !== filterCat)
            return false;

        if (searchText !== "") {
            const q = searchText.toLowerCase();
            if (t.text.toLowerCase().indexOf(q) === -1 && (t.category ?? "").toLowerCase().indexOf(q) === -1)
                return false;

        }
        return true;
    }

    // Importance first (1 is most urgent), then category, then text. A
    // task with no !N sorts last, rather than sorting as zero.
    function byPriority(a, b) {
        const ai = a.importance === null ? 9999 : a.importance;
        const bi = b.importance === null ? 9999 : b.importance;
        if (ai !== bi)
            return ai - bi;

        const ac = a.category ?? "￿";
        const bc = b.category ?? "￿";
        if (ac !== bc)
            return ac.localeCompare(bc);

        return a.text.localeCompare(b.text);
    }

    function catColor(name) {
        for (const c of taskStore.config.categories) if (c.name === name) {
            return c.color;
        }
        return Colors.textFaint;
    }

    function impColor(level) {
        for (const i of taskStore.config.importance) if (i.level === level) {
            return i.color;
        }
        return Colors.textFaint;
    }

    // One level at a time, innermost first: help, picker, delete prompt,
    // inline edit, a text field (INSERT -> NORMAL), and only then quit.
    function handleEscape() {
        pending = "";
        if (showHelp) {
            showHelp = false;
            return ;
        }
        if (pickerKey !== "") {
            closePicker();
            return ;
        }
        if (confirmRaw !== "") {
            confirmRaw = "";
            return ;
        }
        if (editingRaw !== "") {
            editingRaw = "";
            toNormal();
            return ;
        }
        if (!normalMode) {
            toNormal();
            return ;
        }
        quit();
    }

    // ---- quitting without losing a write ---------------------------------
    //
    // Closing kills every running Process, including one halfway through
    // writing tasks.md. From the keyboard, "space then q" is a quarter of
    // a second: well inside the tick animation, before the write has even
    // started. So a quit waits until nothing is in flight.

    function idle() {
        return !vanishTimer.running && !taskStore.busy && taskStore.opQueue.length === 0 && taskStore.writeQueue.length === 0;
    }

    function quit() {
        // Asked twice: you mean it.
        if (idle() || quitWhenIdle) {
            Qt.quit();
            return ;
        }
        quitWhenIdle = true;
    }

    // ---- selection --------------------------------------------------------

    function rowKey(r) {
        if (!r)
            return "";

        return r.kind === "task" ? "t:" + r.t.raw : r.kind === "header" ? "h:" + r.key : "";
    }

    function selectable(i) {
        const r = rows[i];
        return r !== undefined && (r.kind === "task" || r.kind === "header");
    }

    function firstTaskIndex() {
        const i = rows.findIndex((r) => {
            return r.kind === "task";
        });
        return i === -1 ? 0 : i;
    }

    // Neighbours in the same section only: ticking the last open task
    // should leave the cursor on the open list, not jump into DONE.
    function rememberNeighbours() {
        selAfter = "";
        selBefore = "";
        for (let j = selIndex + 1; j < rows.length && rows[j].kind === "task"; j++) {
            selAfter = rowKey(rows[j]);
            break;
        }
        for (let j = selIndex - 1; j >= 0 && rows[j].kind === "task"; j--) {
            selBefore = rowKey(rows[j]);
            break;
        }
    }

    function select(i) {
        if (rows.length === 0) {
            selIndex = -1;
            selKey = "";
            return ;
        }
        i = Math.max(0, Math.min(rows.length - 1, i));
        while (i > 0 && !selectable(i))i--
        selIndex = i;
        selKey = rowKey(rows[i]);
        rememberNeighbours();
    }

    function move(delta) {
        if (selIndex < 0 || !selectable(selIndex)) {
            select(firstTaskIndex());
            return ;
        }
        const step = delta > 0 ? 1 : -1;
        let i = selIndex;
        for (let n = Math.abs(delta); n > 0; n--) {
            let j = i + step;
            while (j >= 0 && j < rows.length && !selectable(j))j += step
            if (j < 0 || j >= rows.length)
                break;

            i = j;
        }
        select(i);
    }

    function toNormal(selectFirst) {
        nav.forceActiveFocus();
        if (selectFirst === true || selIndex < 0 || !selectable(selIndex))
            select(firstTaskIndex());

    }

    function setTab(i) {
        closePicker();
        showHelp = false;
        tab = i;
        // The field that had the keyboard may have just been hidden.
        Qt.callLater(() => {
            if (!root.normalMode && !(root.focusItem && root.focusItem.visible))
                root.toNormal();

        });
    }

    function focusAdd() {
        if (tab !== 0)
            setTab(0);

        Qt.callLater(() => {
            return addText.focusInput();
        });
    }

    function focusField(forward) {
        const n = nav.nextItemInFocusChain(forward);
        if (n && n !== nav)
            n.forceActiveFocus();

    }

    // "/" starts a new search, as in vim.
    function startSearch() {
        searchText = "";
        searchField.text = "";
        searchField.focusInput();
    }

    function clearFilters() {
        searchText = "";
        searchField.text = "";
        filterCat = "";
    }

    function openFilterPicker() {
        showPicker("filter", filterBtn, filterOptions, filterCat === "" ? null : filterCat, "all categories", (v) => {
            return root.filterCat = (v === null ? "" : v);
        });
    }

    // ---- inline tokens and completion --------------------------------------
    //
    // "buy milk @home !2" in the add or edit field sets the category and
    // importance, in the same syntax as tasks.md. Unknown @words stay in
    // the text, exactly as the parser treats them in the file.

    function parseInline(text) {
        return Parse.splitBody(text, catNames);
    }

    // Categories matching the @word being typed at the end of the text.
    function suggestFor(text) {
        const m = /(^|\s)@([^\s@]*)$/.exec(text ?? "");
        if (!m)
            return [];

        const q = m[2].toLowerCase();
        const pre = [];
        const sub = [];
        for (const n of catNames) {
            const l = n.toLowerCase();
            if (l.startsWith(q))
                pre.push(n);
            else if (l.indexOf(q) !== -1)
                sub.push(n);
        }
        return pre.concat(sub).slice(0, 6);
    }

    function completeTag(text, list) {
        if (list.length === 0)
            return text;

        return text.replace(/@([^\s@]*)$/, "@" + list[0] + " ");
    }

    // The line a task becomes after an edit, so the cursor can follow it
    // through the reload. Written by the same function Parse uses.
    function predictRaw(task, text, cat, imp) {
        return Parse.renderTask({
            "indent": "",
            "bullet": task.raw.charAt(0),
            "mark": task.raw.charAt(3) === "X" ? "x" : task.raw.charAt(3),
            "text": (text ?? "").trim(),
            "category": cat || null,
            "importance": (imp === null || imp === undefined || imp === "") ? null : parseInt(imp, 10),
            "doneDate": task.doneDate
        });
    }

    function addFromField(andQuit) {
        const raw = addText.text.trim();
        if (raw !== "") {
            const p = parseInline(raw);
            if (p.text !== "") {
                taskStore.add({
                    "text": p.text,
                    "category": p.category ?? addPick.cat,
                    "importance": p.importance ?? addPick.imp
                });
                addText.text = "";
            }
        }
        if (andQuit)
            quit();
        else
            addText.focusInput();
    }

    function saveEdit(task, text, cat, imp) {
        const p = parseInline(text);
        const c = p.category ?? cat;
        const i = p.importance ?? imp;
        taskStore.edit(task.raw, {
            "text": p.text,
            "category": c,
            "importance": i
        });
        pendingSelRaw = predictRaw(task, p.text, c, i);
        editingRaw = "";
        toNormal();
    }

    function setImportanceOf(task, level) {
        if (level !== null && !taskStore.config.importance.some((x) => {
            return x.level === level;
        }))
            return ;

        taskStore.edit(task.raw, {
            "importance": level
        });
        pendingSelRaw = predictRaw(task, task.text, task.category, level);
    }

    function pickCategoryFor(task) {
        const anchor = list.itemAtIndex(selIndex);
        if (!anchor)
            return ;

        showPicker("sel", anchor, catOptions, task.category, "no category", (v) => {
            taskStore.edit(task.raw, {
                "category": v
            });
            root.pendingSelRaw = root.predictRaw(task, task.text, v, task.importance);
        }, true);
    }

    // ---- normal mode keys ------------------------------------------------

    function normalKey(e) {
        const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
        const t = e.text;
        const k = e.key;
        const prev = pending;
        pending = "";
        e.accepted = true;
        if (showHelp) {
            if (t === "?" || t === "q")
                showHelp = false;

            return ;
        }
        // The delete prompt eats the next key: y deletes, anything else
        // keeps the task.
        if (confirmRaw !== "") {
            if (t === "y" || k === Qt.Key_Return || k === Qt.Key_Enter)
                taskStore.remove(confirmRaw);

            confirmRaw = "";
            return ;
        }
        if (prev === "g" && t === "t") {
            setTab((tab + 1) % 3);
            return ;
        }
        if (prev === "g" && t === "T") {
            setTab((tab + 2) % 3);
            return ;
        }
        if (k === Qt.Key_Backtab) {
            if (ctrl)
                setTab((tab + 2) % 3);
            else
                focusField(false);
            return ;
        }
        if (k === Qt.Key_Tab) {
            if (ctrl)
                setTab((tab + 1) % 3);
            else
                focusField(true);
            return ;
        }
        if (t === "q") {
            quit();
            return ;
        }
        if (t === "?") {
            showHelp = true;
            return ;
        }
        const handled = tab === 0 ? tasksKey(t, k, ctrl, prev) : otherKey(t, k, ctrl, prev);
        if (!handled)
            e.accepted = false;

    }

    function tasksKey(t, k, ctrl, prev) {
        const half = Math.max(3, Math.floor(list.height / 60));
        if (ctrl) {
            switch (k) {
            case Qt.Key_D:
                move(half);
                return true;
            case Qt.Key_U:
                move(-half);
                return true;
            case Qt.Key_N:
            case Qt.Key_J:
                move(1);
                return true;
            case Qt.Key_P:
            case Qt.Key_K:
                move(-1);
                return true;
            }
            return false;
        }
        const r = selRow;
        // Second key of a two-key command. Settled first, so the "d" of
        // dd or the "a" of za is never read as a command of its own.
        if (prev === "d") {
            if (t === "d" && r !== null && r.kind === "task")
                confirmRaw = r.t.raw;

            return true;
        }
        if (prev === "z") {
            if (t === "a" && r !== null) {
                for (let i = selIndex; i >= 0; i--) {
                    if (rows[i].kind === "header") {
                        toggleFold(rows[i].key);
                        select(i);
                        break;
                    }
                }
            }
            return true;
        }
        if (prev === "g") {
            if (t === "g")
                select(0);

            return true;
        }
        if (t === "g" || t === "z" || t === "d") {
            pending = t;
            return true;
        }
        if (t === "j" || k === Qt.Key_Down) {
            move(1);
            return true;
        }
        if (t === "k" || k === Qt.Key_Up) {
            move(-1);
            return true;
        }
        if (k === Qt.Key_Home) {
            select(0);
            return true;
        }
        if (t === "G" || k === Qt.Key_End) {
            select(rows.length - 1);
            return true;
        }
        if (t === "/") {
            startSearch();
            return true;
        }
        if (t === "a" || t === "A" || t === "o" || t === "O") {
            focusAdd();
            return true;
        }
        if (t === "f") {
            openFilterPicker();
            return true;
        }
        if (t === "F") {
            clearFilters();
            return true;
        }
        if (r === null)
            return t !== "";

        const enter = k === Qt.Key_Return || k === Qt.Key_Enter;
        if (r.kind === "header") {
            const isFolded = folded[r.key] === true;
            if (t === " " || t === "x" || enter || (t === "l" && isFolded) || (t === "h" && !isFolded))
                toggleFold(r.key);

            return true;
        }
        const task = r.t;
        const mode = r.mode;
        if (t === " " || t === "x") {
            act(task.raw, mode === "open" ? "tick" : mode === "done" ? "untick" : "uncancel");
            return true;
        }
        if (t === "u" && mode !== "open") {
            act(task.raw, mode === "done" ? "untick" : "uncancel");
            return true;
        }
        if (t === "c" && mode !== "done") {
            act(task.raw, mode === "cancelled" ? "uncancel" : "cancel");
            return true;
        }
        if (mode !== "open")
            return t !== "";

        if (t === "e" || t === "i" || t === "I" || enter) {
            closePicker();
            editingRaw = task.raw;
            return true;
        }
        if (t === "@") {
            pickCategoryFor(task);
            return true;
        }
        if (/^[0-9]$/.test(t)) {
            setImportanceOf(task, t === "0" ? null : parseInt(t, 10));
            return true;
        }
        return t !== "";
    }

    // Stats and settings: the page scrolls, h/l walk the stats ranges,
    // and i / Enter / Tab go into the settings fields.
    function otherKey(t, k, ctrl, prev) {
        const f = altBodyFlick;
        const maxY = Math.max(0, f.contentHeight - f.height);
        const scroll = (dy) => {
            f.contentY = Math.max(0, Math.min(maxY, f.contentY + dy));
        };
        if (ctrl) {
            if (k === Qt.Key_D) {
                scroll(f.height / 2);
                return true;
            }
            if (k === Qt.Key_U) {
                scroll(-f.height / 2);
                return true;
            }
            return false;
        }
        if (t === "j" || k === Qt.Key_Down) {
            scroll(48);
            return true;
        }
        if (t === "k" || k === Qt.Key_Up) {
            scroll(-48);
            return true;
        }
        if ((prev === "g" && t === "g") || k === Qt.Key_Home) {
            f.contentY = 0;
            return true;
        }
        if (t === "G" || k === Qt.Key_End) {
            f.contentY = maxY;
            return true;
        }
        if (t === "g") {
            pending = "g";
            return true;
        }
        if (tab === 1 && (t === "h" || k === Qt.Key_Left)) {
            statsView.range = Math.max(0, statsView.range - 1);
            return true;
        }
        if (tab === 1 && (t === "l" || k === Qt.Key_Right)) {
            statsView.range = Math.min(statsView.rangeNames.length - 1, statsView.range + 1);
            return true;
        }
        if (tab === 2 && (t === "i" || t === "a" || k === Qt.Key_Return || k === Qt.Key_Enter)) {
            focusField(true);
            return true;
        }
        return t !== "";
    }

    // Safety net: if the focused field disappears (tab switch, editor
    // closed by a reload), keys would go nowhere. Fall back to NORMAL.
    function ensureFocus() {
        const f = card.Window.activeFocusItem;
        const isInput = f !== null && f !== undefined && f.selectByMouse !== undefined && f.visible;
        if (f !== nav && !isInput)
            toNormal();

    }

    function fireVanish() {
        const raw = root.vanishingRaw;
        const what = root.vanishingAction;
        root.vanishingRaw = "";
        root.vanishingAction = "";
        switch (what) {
        case "tick":
            taskStore.tick(raw);
            break;
        case "untick":
            taskStore.untick(raw);
            break;
        case "cancel":
            taskStore.cancel(raw);
            break;
        case "uncancel":
            taskStore.uncancel(raw);
            break;
        }
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-tasks"
    color: "transparent"
    // Clear and focus the dropdown's filter each time one opens, so a
    // long category list is reachable by typing straight away.
    onPickerKeyChanged: {
        popSearch.text = "";
        if (pickerKey !== "") {
            // Start on the current value, so Enter straight away keeps it.
            const i = pickerCurrent === null ? -1 : pickerOptions.findIndex((o) => {
                return o.name === pickerCurrent;
            });
            pickerHi = i === -1 ? 0 : i + 1;
            Qt.callLater(() => {
                popSearch.focusInput();
                root.movePicker(0);
            });
        }
    }
    onFocusItemChanged: {
        if (ready)
            Qt.callLater(ensureFocus);

    }
    onSelIndexChanged: Qt.callLater(() => {
        if (root.selIndex >= 0 && root.tab === 0)
            list.positionViewAtIndex(root.selIndex, ListView.Contain);

    })
    // Keep the cursor on the same task across reloads; when it is gone,
    // move to its neighbour in the same section, then to the same spot.
    onRowsChanged: {
        let k = -1;
        if (pendingSelRaw !== "")
            k = rows.findIndex((r) => {
            return r.kind === "task" && r.t.raw === pendingSelRaw;
        });

        for (const key of [selKey, selAfter, selBefore]) {
            if (k !== -1 || key === "")
                continue;

            k = rows.findIndex((r) => {
                return rowKey(r) === key;
            });
        }
        if (k !== -1) {
            selIndex = k;
            selKey = rowKey(rows[k]);
            rememberNeighbours();
            return ;
        }
        if (selIndex >= 0)
            select(selIndex);

    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // The id is deliberately NOT `store`. Writing `store: store` on a
    // child view resolves the right-hand side against that view's own
    // properties first, so it binds to itself: the view receives
    // undefined and collapses to zero height with no error anywhere.
    Store {
        id: taskStore
    }

    Timer {
        id: vanishTimer

        interval: 180
        onTriggered: root.fireVanish()
    }

    // Opens in INSERT on the new-task field. A beat after creation, so
    // it lands after the window has the keyboard and after the first
    // list build.
    Timer {
        interval: 60
        running: true
        onTriggered: {
            addText.focusInput();
            root.ready = true;
        }
    }

    // Polls while a quit is waiting on a write; a failed write cancels
    // the quit so the error stays on screen.
    Timer {
        interval: 80
        repeat: true
        running: root.quitWhenIdle
        onTriggered: {
            if (taskStore.error !== "")
                root.quitWhenIdle = false;
            else if (root.idle())
                Qt.quit();
        }
    }

    Connections {
        function onRefreshed() {
            root.pendingSelRaw = "";
        }

        target: taskStore
    }

    // Handled before key events reach any item, so it fires whatever
    // has focus -- including nothing, which is the case the moment you
    // click a chip or a row.
    Shortcut {
        sequences: ["Escape"]
        context: Qt.ApplicationShortcut
        onActivated: root.handleEscape()
    }

    Shortcut {
        sequences: ["Ctrl+S"]
        context: Qt.ApplicationShortcut
        enabled: root.tab === 2
        onActivated: {
            if (settingsView.dirty)
                settingsView.save();

        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.quit()
    }

    Rectangle {
        // FIXED. Not derived from content.
        // A card sized to its contents re-laid-out on every tick,
        // delete, fold and tab change -- the whole panel jumped under
        // the cursor while you were using it, and the button you were
        // about to click moved. A constant height costs some empty
        // space on a short list and is worth it: the list scrolls
        // inside a frame that never moves.
        // ---- header (pinned top) -------------------------------------
        // ---- list (fills the gap between header and footer) ----------
        // ---- add row (pinned bottom) ---------------------------------
        // ---- stats / settings ----------------------------------------
        // ---- the one dropdown -----------------------------------------
        // Positioned against whichever trigger is open, clamped to the
        // card, flipped above the trigger when there is no room below.
        // Being a child of the card, it cannot be drawn outside it --
        // which is exactly what the old inline lists did, rendering the
        // options onto the desktop below the card's bottom edge.

        id: card

        readonly property int pad: 16

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((root.height - height) / 2)
        implicitWidth: 760
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
        Component.onCompleted: {
            opacity = 1;
            scale = 1;
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closePicker()
        }

        // NORMAL mode lives here: an empty item that is not an ancestor
        // of any field, so keys typed into a field travel up the field's
        // own parents and never arrive here -- "j" in search types a j.
        // First in the card, so Tab from it reaches the first field and
        // Shift+Tab the last.
        Item {
            id: nav

            objectName: "nav"
            Keys.onPressed: (e) => {
                return root.normalKey(e);
            }
        }

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
                        text: root.openTasks.length + " open" + (root.doneToday.length > 0 ? "  ·  " + root.doneToday.length + " done today" : "")
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        color: Colors.textFaint
                    }

                    // Which mode the keys are in, as vim shows it, plus the
                    // first half of a two-key command while it waits.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: modeLbl.implicitWidth + 12
                        implicitHeight: 16
                        radius: 4
                        color: root.normalMode ? Qt.alpha(Colors.accent, 0.16) : Qt.alpha(Colors.warn, 0.16)

                        Text {
                            id: modeLbl

                            anchors.centerIn: parent
                            text: (root.normalMode ? "NORMAL" : "INSERT") + (root.pending !== "" ? "  " + root.pending : "")
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            font.weight: Font.DemiBold
                            color: root.normalMode ? Colors.accent : Colors.warn
                        }

                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: taskStore.busy || root.quitWhenIdle
                        text: root.quitWhenIdle ? "saving, then closing…" : "saving…"
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
                            onClicked: root.setTab(index)
                        }

                    }

                    TinyBtn {
                        label: "esc"
                        onClicked: root.quit()
                    }

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
                    text: "⚠  Syncthing conflict copies in the Tasker folder — " + "tasks may be split across them."
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
                text: "Converted " + taskStore.migratedCount + " category marker" + (taskStore.migratedCount === 1 ? "" : "s") + " from #name to @name, so Obsidian stops indexing them as tags."
                wrapMode: Text.WordWrap
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                color: Colors.textFaint
            }

            Text {
                visible: taskStore.stampedCount > 0
                width: parent.width
                text: "Dated " + taskStore.stampedCount + " task" + (taskStore.stampedCount === 1 ? "" : "s") + " ticked elsewhere, using today's date."
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
                    // Enter or Down: to the results, cursor on the first.
                    onSubmitted: root.toNormal(true)
                    onDownPressed: root.toNormal(true)
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
                    onToggled: root.openFilterPicker()
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

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 120
                        }

                    }

                }

            }

            Rectangle {
                visible: root.tab === 0
                width: parent.width
                height: 1
                color: Colors.outline
            }

        }

        ListView {
            // ---- section header ----------------------------------
            // ---- task row ----------------------------------------

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
            onContentYChanged: {
                if (root.pickerKey !== "" && dragging) {
                    root.closePicker();
                }
            }

            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 140
                }

            }

            displaced: Transition {
                NumberAnimation {
                    properties: "y"
                    duration: 170
                    easing.type: Easing.OutCubic
                }

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
                readonly property bool selected: root.normalMode && root.tab === 0 && index === root.selIndex
                // Editor state lives on the delegate, seeded each time
                // the editor opens, so reopening after a cancelled edit
                // does not resurrect stale pickers.
                property var editCat: null
                property var editImp: null

                // The editor's field is focused when editing STARTS, never
                // when a row is created. Focusing on creation was the bug:
                // every row has a (hidden) editor, the list rebuilds all
                // rows on every keystroke in search and once more when
                // the file loads -- and each rebuild handed the keyboard
                // to a hidden editor, out of search and out of new task.
                onEditingChanged: {
                    if (editing) {
                        editCat = task.category;
                        editImp = task.importance;
                        root.editDraft = task.text;
                        focusEditor.start();
                    }
                }
                // A reload rebuilds the row being edited; give it back the
                // keyboard it had.
                Component.onCompleted: {
                    if (editing)
                        focusEditor.start();

                }
                width: list.width
                implicitHeight: modelData.kind === "header" ? 24 : modelData.kind === "note" ? 20 : taskBg.implicitHeight
                height: implicitHeight

                // Dies with the row, unlike Qt.callLater, so it can never
                // fire into a destroyed editor.
                Timer {
                    id: focusEditor

                    interval: 0
                    onTriggered: {
                        if (rowItem.editing)
                            editText.focusInput();

                    }
                }

                Item {
                    visible: rowItem.modelData.kind === "header"
                    anchors.fill: parent

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        visible: rowItem.selected
                        color: Colors.surface0
                        border.width: 1
                        border.color: Qt.alpha(Colors.accent, 0.6)
                    }

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
                            text: (rowItem.modelData.label ?? "") + "  " + (rowItem.modelData.count ?? 0)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            color: Colors.textFaint
                        }

                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.select(rowItem.index);
                            root.toggleFold(rowItem.modelData.key);
                        }
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
                        if (!rowItem.isTask)
                            return "transparent";

                        const hovered = rowHover.hovered || rowItem.editing || rowItem.confirming || rowItem.selected;
                        if (rowItem.task.importance !== null) {
                            // Done and cancelled rows are faded: their
                            // priority is history, not a call to act.
                            const base = rowItem.mode === "open" ? 0.14 : 0.05;
                            return Qt.alpha(root.impColor(rowItem.task.importance), hovered ? base + 0.1 : base);
                        }
                        return hovered ? Colors.surface0 : "transparent";
                    }
                    opacity: rowItem.vanishing ? 0 : 1
                    // The keyboard cursor: an outline, so it reads on top
                    // of any importance tint.
                    border.width: rowItem.selected ? 1 : 0
                    border.color: Qt.alpha(Colors.accent, 0.75)

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
                        color: rowItem.isTask && rowItem.task.importance !== null ? root.impColor(rowItem.task.importance) : "transparent"
                        opacity: rowItem.mode === "open" ? 1 : 0.4
                    }

                    // A HoverHandler, not a hoverEnabled MouseArea:
                    // a MouseArea here loses hover the instant the
                    // cursor crosses onto a button inside it, and the
                    // buttons are shown BECAUSE the row is hovered.
                    // That fed back on itself and flickered.
                    HoverHandler {
                        id: rowHover
                    }

                    // Clicking a row puts the keyboard cursor on it, so
                    // mouse and keys can be mixed.
                    TapHandler {
                        onTapped: root.select(rowItem.index)
                    }

                    Column {
                        // ---- inline editor -------------------------

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
                                border.color: rowItem.vanishing || boxHover.hovered ? Colors.accent : rowItem.mode === "open" ? Colors.outline : Qt.alpha(Colors.outline, 0.6)

                                Rectangle {
                                    readonly property bool full: rowItem.vanishing || rowItem.mode === "done"

                                    anchors.centerIn: parent
                                    width: full ? 15 : 7
                                    height: width
                                    radius: full ? 5 : 3
                                    color: rowItem.mode === "cancelled" ? Colors.textFaint : Colors.accent
                                    opacity: full ? 1 : rowItem.mode === "cancelled" ? 0.35 : boxHover.hovered ? 0.5 : 0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 120
                                        }

                                    }

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: 150
                                            easing.type: Easing.OutBack
                                        }

                                    }

                                    Behavior on radius {
                                        NumberAnimation {
                                            duration: 150
                                        }

                                    }

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

                                Behavior on border.color {
                                    ColorAnimation {
                                        duration: 120
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
                                color: rowItem.vanishing || rowItem.mode !== "open" ? Colors.textFaint : Colors.textMain

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 140
                                    }

                                }

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
                                    color: rowItem.isTask && rowItem.task.category ? Qt.alpha(root.catColor(rowItem.task.category), 0.18) : "transparent"

                                    Text {
                                        id: catLbl

                                        anchors.centerIn: parent
                                        text: rowItem.isTask ? (rowItem.task.category ?? "") : ""
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                        color: rowItem.isTask && rowItem.task.category ? root.catColor(rowItem.task.category) : Colors.textFaint
                                    }

                                }

                            }

                            Row {
                                id: rowActions

                                // Always laid out, only faded. Hiding
                                // it with `visible` changed the width
                                // available to the text and the
                                // category pill, so everything in the
                                // row jumped sideways on hover.
                                readonly property bool shown: rowHover.hovered || rowItem.editing || rowItem.confirming || rowItem.selected

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                opacity: shown ? 1 : 0
                                enabled: shown

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

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 110
                                    }

                                }

                            }

                        }

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
                                captureTab: root.editSuggest.length > 0
                                onEdited: root.editDraft = text
                                onTabPressed: {
                                    text = root.completeTag(text, root.editSuggest);
                                    root.editDraft = text;
                                }
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
                                    onToggled: root.showPicker("edit", editCatBtn, root.catOptions, rowItem.editCat, "no category", (v) => {
                                        return rowItem.editCat = v;
                                    })
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
                                    onClicked: root.saveEdit(rowItem.task, editText.text, rowItem.editCat, rowItem.editImp)
                                }

                            }

                        }

                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }

                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 170
                            easing.type: Easing.OutCubic
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
            y: list.y + (list.contentHeight > list.height ? (list.contentY / (list.contentHeight - list.height)) * (list.height - height) : 0)
        }

        Text {
            visible: root.tab === 0 && taskStore.loaded && root.rows.length === 0
            anchors.top: headerCol.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.leftMargin: card.pad
            anchors.right: parent.right
            anchors.rightMargin: card.pad
            text: taskStore.tasks.length === 0 ? "No tasks file yet at\n" + taskStore.tasksPath : (root.searchText !== "" || root.filterCat !== "") ? "Nothing matches." : "All clear."
            wrapMode: Text.WordWrap
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            lineHeight: 1.4
            color: Colors.textFaint
        }

        // One line, always present: what the keys do right now. It is the
        // cheat sheet that changes with the mode, so ? is rarely needed.
        Text {
            id: hintBar

            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            height: 14
            text: root.hint
            elide: Text.ElideRight
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            color: root.confirmRaw !== "" ? Colors.danger : Colors.textFaint
        }

        Column {
            id: footer

            visible: root.tab === 0
            anchors.bottom: hintBar.top
            anchors.bottomMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            spacing: 8

            Rectangle {
                width: parent.width
                height: 1
                color: Colors.outline
            }

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
                    placeholder: "new task…  (@category !1 work inline)"
                    Component.onCompleted: focusInput()
                    captureTab: root.addSuggest.length > 0
                    onTabPressed: text = root.completeTag(text, root.addSuggest)
                    onSubmitted: root.addFromField(false)
                    onCtrlSubmitted: root.addFromField(true)
                }

                TinyBtn {
                    id: addGo

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: "add"
                    tint: Colors.accent
                    onClicked: root.addFromField(false)
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
                    onToggled: root.showPicker("add", addCatBtn, root.catOptions, addPick.cat, "no category", (v) => {
                        return addPick.cat = v;
                    })
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

        Flickable {
            id: altBodyFlick

            visible: root.tab !== 0
            anchors.top: headerCol.bottom
            anchors.topMargin: 10
            anchors.bottom: hintBar.top
            anchors.bottomMargin: 8
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
                implicitHeight: root.tab === 2 ? settingsView.implicitHeight : root.tab === 1 ? statsView.implicitHeight : 0

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

                readonly property point src: root.pickerAnchor ? root.pickerAnchor.mapToItem(card, 0, 0) : Qt.point(0, 0)
                readonly property real anchorH: root.pickerAnchor ? root.pickerAnchor.height : 0
                readonly property bool below: src.y + anchorH + 4 + height < card.height - 8
                // The "none" row only shows with an empty filter, so it
                // shifts every index by one; pickerHi counts it.
                readonly property bool noneShown: popSearch.text === ""
                readonly property var filtered: {
                    const q = popSearch.text.toLowerCase().trim();
                    if (q === "")
                        return root.pickerOptions;

                    // Prefix matches first: typing "ho" puts "home"
                    // above "household chores".
                    const pre = [];
                    const sub = [];
                    for (const o of root.pickerOptions) {
                        const n = o.name.toLowerCase();
                        if (n.startsWith(q))
                            pre.push(o);
                        else if (n.indexOf(q) !== -1)
                            sub.push(o);
                    }
                    return pre.concat(sub);
                }

                // Narrow when opened for a whole row (@ on a task): a
                // row-wide dropdown would be 700px of mostly nothing.
                width: root.pickerNarrow ? 240 : Math.max(210, root.pickerAnchor ? root.pickerAnchor.width : 210)
                height: Math.min(268, popBody.implicitHeight + 12)
                x: Math.max(8, Math.min(root.pickerNarrow && root.pickerAnchor ? src.x + root.pickerAnchor.width - width : src.x, card.width - width - 8))
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
                        onEdited: root.pickerHi = 0
                        onUpPressed: root.movePicker(-1)
                        onDownPressed: root.movePicker(1)
                        onSubmitted: {
                            if (root.pickerCount() > 0)
                                root.pickAt(root.pickerHi);

                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 24
                        radius: 6
                        visible: popSearch.text === ""
                        color: noneMouse.containsMouse || root.pickerHi === 0 ? Colors.surface1 : "transparent"

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
                                if (root.pickerApply)
                                    root.pickerApply(null);

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
                            required property int index
                            readonly property bool chosen: root.pickerCurrent === modelData.name
                            readonly property bool lit: root.pickerHi === index + (pop.noneShown ? 1 : 0)

                            width: popList.width
                            height: 24
                            radius: 6
                            color: optMouse.containsMouse || lit ? Colors.surface1 : chosen ? Qt.alpha(Colors.accent, 0.12) : "transparent"

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
                                    if (root.pickerApply)
                                        root.pickerApply(optRow.modelData.name);

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

        // ? -- every key in one place.
        Rectangle {
            id: helpPanel

            readonly property var normalKeys: [["j k  ↓ ↑", "move"], ["gg  G", "top / bottom"], ["ctrl+d  ctrl+u", "half a page"], ["space  x", "done · undo · restore"], ["e  enter", "edit the text"], ["c", "cancel · restore"], ["dd  then y", "delete"], ["@", "category"], ["1-9  0", "importance · none"], ["/", "search"], ["f  F", "category filter · clear filters"], ["a  o", "new task"], ["space on a header", "fold / unfold"], ["za", "fold this section"], ["gt  gT", "next / previous tab"], ["h l", "stats range"], ["tab  shift+tab", "into the fields"], ["q  esc", "close"]]
            readonly property var insertKeys: [["enter", "add · save"], ["ctrl+enter", "add and close"], ["@name  !N", "category, importance inline"], ["tab", "complete @category"], ["ctrl+w  ctrl+u", "delete word · line"], ["ctrl+s", "save settings"], ["esc", "back to NORMAL"]]
            readonly property var pickerKeys: [["type", "filter"], ["↑ ↓  ctrl+n ctrl+p", "move"], ["enter", "pick"], ["esc", "close"]]

            visible: root.showHelp
            z: 200
            anchors.centerIn: parent
            width: 660
            height: helpBody.implicitHeight + 32
            radius: 12
            color: Colors.mantle
            border.width: 1
            border.color: Qt.alpha(Colors.accent, 0.5)

            MouseArea {
                anchors.fill: parent
                onClicked: root.showHelp = false
            }

            Row {
                id: helpBody

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 24

                Column {
                    width: 330
                    spacing: 4

                    HelpTitle {
                        text: "NORMAL"
                    }

                    Repeater {
                        model: helpPanel.normalKeys

                        HelpRow {
                        }

                    }

                }

                Column {
                    width: 270
                    spacing: 4

                    HelpTitle {
                        text: "INSERT"
                    }

                    Repeater {
                        model: helpPanel.insertKeys

                        HelpRow {
                        }

                    }

                    Item {
                        width: 1
                        height: 8
                    }

                    HelpTitle {
                        text: "PICKER"
                    }

                    Repeater {
                        model: helpPanel.pickerKeys

                        HelpRow {
                        }

                    }

                }

            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }

        }

    }

    // Inline components: top level of the root object only.
    component HelpTitle: Text {
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        font.letterSpacing: 1
        color: Colors.textFaint
        bottomPadding: 2
    }

    component HelpRow: Row {
        required property var modelData

        spacing: 10

        Text {
            width: 130
            text: parent.modelData[0]
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: Colors.accent
        }

        Text {
            text: parent.modelData[1]
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: Colors.textMain
        }

    }

}
