import QtQuick
import qs

// Settings: the category and importance lists that live in config.md.
//
// Edits are staged locally and written on Save, not as you type. Two
// reasons: every keystroke writing a synced file is how you earn
// Syncthing conflict copies, and renaming a category has to rewrite
// every matching tag in tasks.md -- that is a single deliberate action,
// not something to fire per character.
Item {
    id: settings

    required property var store

    implicitHeight: col.implicitHeight

    // Working copies. `origName` is remembered per row so a rename can
    // be detected on save; without it we would only know the new name
    // and could not find the old tag to rewrite.
    property var cats: []
    property var imps: []
    property bool dirty: false

    function load() {
        const c = [];
        for (const x of store.config.categories)
            c.push({ name: x.name, color: x.color, origName: x.name });
        const i = [];
        for (const x of store.config.importance)
            i.push({ level: x.level, label: x.label, color: x.color });
        cats = c;
        imps = i;
        dirty = false;
        rev++;
    }

    Component.onCompleted: load()
    Connections {
        target: settings.store
        function onRefreshed() { if (!settings.dirty) settings.load(); }
    }

    // Bumped on every edit. `problems` and `renames` depend on it so
    // they re-evaluate as you type, WITHOUT the model array changing
    // identity -- see setCat below for why that matters.
    property int rev: 0

    function touch() { dirty = true; rev++; }

    // Mutated in place, deliberately.
    //
    // Reassigning `cats` makes the Repeater rebuild every delegate,
    // which destroys and recreates the very TextInput being typed into:
    // you get one character, then focus is gone. Editing the object
    // inside the array leaves the array identity alone, so the
    // delegates survive and keep focus. Nothing binds to modelData
    // while typing -- the row holds its own copy for display -- so
    // there is nothing that needed the change signal.
    function setCat(i, key, value) {
        cats[i][key] = value;
        touch();
    }
    function setImp(i, key, value) {
        imps[i][key] = value;
        touch();
    }
    function moveCat(i, delta) {
        const j = i + delta;
        if (j < 0 || j >= cats.length) return;
        const c = cats.slice();
        const tmp = c[i]; c[i] = c[j]; c[j] = tmp;
        cats = c;
        touch();
    }
    function moveImp(i, delta) {
        const j = i + delta;
        if (j < 0 || j >= imps.length) return;
        const m = imps.slice();
        const tmp = m[i]; m[i] = m[j]; m[j] = tmp;
        imps = m;
        touch();
    }
    function delCat(i) { cats = cats.slice(0, i).concat(cats.slice(i + 1)); touch(); }
    function delImp(i) { imps = imps.slice(0, i).concat(imps.slice(i + 1)); touch(); }

    function addCat() {
        cats = cats.concat([{ name: "", color: "#888888", origName: null }]);
        touch();
    }
    function addImp() {
        let next = 1;
        for (const m of imps) if (m.level >= next) next = m.level + 1;
        imps = imps.concat([{ level: next, label: "", color: "#888888" }]);
        touch();
    }

    // A tag cannot contain whitespace or '#', so those are stripped
    // rather than written out and silently failing to match anything.
    function cleanTag(s) { return s.replace(/[#\s]+/g, ""); }

    readonly property var problems: {
        void rev;   // re-evaluate on in-place edits
        const out = [];
        const seen = {};
        for (const c of cats) {
            const n = cleanTag(c.name);
            if (n === "") out.push("a category has no name");
            else if (seen[n]) out.push("two categories are both called " + n);
            seen[n] = true;
            if (!/^#[0-9a-fA-F]{3,8}$/.test(c.color))
                out.push((n || "a category") + " has an invalid colour");
        }
        const lv = {};
        for (const m of imps) {
            if (lv[m.level]) out.push("two importance levels are both !" + m.level);
            lv[m.level] = true;
            if (!/^#[0-9a-fA-F]{3,8}$/.test(m.color))
                out.push("!" + m.level + " has an invalid colour");
        }
        return out;
    }

    readonly property var renames: {
        void rev;   // re-evaluate on in-place edits
        const out = [];
        for (const c of cats) {
            const n = cleanTag(c.name);
            if (c.origName && n !== "" && n !== c.origName)
                out.push({ from: c.origName, to: n });
        }
        return out;
    }

    function save() {
        if (problems.length > 0) return;
        const cfg = {
            categories: cats.map((c) => ({ name: cleanTag(c.name), color: c.color })),
            importance: imps.map((m) => ({
                level: m.level, label: m.label.trim() || "level " + m.level, color: m.color
            }))
        };
        store.applyConfig(cfg, renames);
        dirty = false;
    }

    // ---- a single editable row ---------------------------------------

    component EditRow: Item {
        id: erow
        property string name: ""
        property string colorHex: "#888888"
        property string prefix: ""
        property bool canUp: true
        property bool canDown: true
        signal nameEdited(string value)
        signal colorEdited(string value)
        signal up()
        signal down()
        signal removed()

        height: 32

        Rectangle {
            id: swatch
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 4
            color: /^#[0-9a-fA-F]{3,8}$/.test(erow.colorHex) ? erow.colorHex : "transparent"
            border.width: 1
            border.color: Colors.outline
        }

        Text {
            id: pfx
            visible: erow.prefix !== ""
            anchors.left: swatch.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: erow.prefix
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: Colors.textFaint
        }

        Field {
            id: nameField
            anchors.left: erow.prefix !== "" ? pfx.right : swatch.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 190
            fontSize: 11
            placeholder: "name"
            // Seeded once from the model and never re-bound: a live
            // binding here would fight the cursor on every keystroke.
            text: erow.name
            onEdited: erow.nameEdited(text)
        }

        Field {
            id: colorField
            anchors.left: nameField.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 100
            fontSize: 11
            placeholder: "#rrggbb"
            text: erow.colorHex
            onEdited: {
                // Updates the swatch live. Assigning colorHex does not
                // break the text binding above, and writing the same
                // string back to a TextInput does not move the cursor.
                erow.colorHex = colorField.text;
                erow.colorEdited(colorField.text);
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            TinyBtn {
                label: "↑"
                enabled: erow.canUp
                onClicked: erow.up()
            }
            TinyBtn {
                label: "↓"
                enabled: erow.canDown
                onClicked: erow.down()
            }
            TinyBtn {
                label: "remove"
                tint: Colors.danger
                onClicked: erow.removed()
            }
        }
    }

    // ---- layout --------------------------------------------------------

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        Text {
            text: "CATEGORIES"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            font.letterSpacing: 1
            color: Colors.textFaint
        }

        // Scrolls instead of growing: fifty categories would
        // otherwise push the save button off the bottom of the
        // card with no way to reach it.
        Flickable {
            width: col.width
            height: Math.min(catsCol.implicitHeight, 260)
            contentHeight: catsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: catsCol
                width: parent.width
                spacing: 0
                    Repeater {
                        model: settings.cats
                        EditRow {
                            required property var modelData
                            required property int index
                            width: col.width
                            name: modelData.name
                            colorHex: modelData.color
                            canUp: index > 0
                            canDown: index < settings.cats.length - 1
                            onNameEdited: (v) => settings.setCat(index, "name", v)
                            onColorEdited: (v) => settings.setCat(index, "color", v)
                            onUp: settings.moveCat(index, -1)
                            onDown: settings.moveCat(index, 1)
                            onRemoved: settings.delCat(index)
                        }
                    }
            }
        }

        TinyBtn {
            label: "+ category"
            tint: Colors.accent
            onClicked: settings.addCat()
        }

        Rectangle { width: col.width; height: 1; color: Colors.outline }

        Text {
            text: "IMPORTANCE"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            font.letterSpacing: 1
            color: Colors.textFaint
        }

        // Scrolls instead of growing: fifty categories would
        // otherwise push the save button off the bottom of the
        // card with no way to reach it.
        Flickable {
            width: col.width
            height: Math.min(impsCol.implicitHeight, 200)
            contentHeight: impsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: impsCol
                width: parent.width
                spacing: 0
                    Repeater {
                        model: settings.imps
                        EditRow {
                            required property var modelData
                            required property int index
                            width: col.width
                            prefix: "!" + modelData.level
                            name: modelData.label
                            colorHex: modelData.color
                            canUp: index > 0
                            canDown: index < settings.imps.length - 1
                            onNameEdited: (v) => settings.setImp(index, "label", v)
                            onColorEdited: (v) => settings.setImp(index, "color", v)
                            onUp: settings.moveImp(index, -1)
                            onDown: settings.moveImp(index, 1)
                            onRemoved: settings.delImp(index)
                        }
                    }
            }
        }

        TinyBtn {
            label: "+ importance level"
            tint: Colors.accent
            onClicked: settings.addImp()
        }

        Rectangle { width: col.width; height: 1; color: Colors.outline }

        // What saving is about to do to tasks.md, spelled out before it
        // happens: a rename rewrites tags across the whole file, and
        // that is not something to discover afterwards.
        Text {
            visible: settings.renames.length > 0
            width: col.width
            text: "Saving will rewrite " + settings.renames
                    .map((r) => "#" + r.from + " → #" + r.to).join(", ")
                + " throughout tasks.md."
            wrapMode: Text.WordWrap
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            lineHeight: 1.3
            color: Colors.warn
        }

        // Deleting a category does not touch the tasks that use it;
        // they simply stop matching and fall into "uncategorized".
        // Better to say so than to silently orphan tags.
        Text {
            visible: settings.dirty
            width: col.width
            text: "Removing a category leaves its #tag on existing tasks — they "
                + "show as uncategorized until retagged."
            wrapMode: Text.WordWrap
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            lineHeight: 1.3
            color: Colors.textFaint
        }

        Text {
            visible: settings.problems.length > 0
            width: col.width
            text: "⚠  " + settings.problems.join("\n⚠  ")
            wrapMode: Text.WordWrap
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            lineHeight: 1.3
            color: Colors.danger
        }

        Item {
            width: col.width
            height: 26
            Row {
                anchors.right: parent.right
                spacing: 8
                TinyBtn {
                    label: "revert"
                    enabled: settings.dirty
                    onClicked: settings.load()
                }
                TinyBtn {
                    label: settings.store.busy ? "saving…" : "save"
                    tint: Colors.accent
                    enabled: settings.dirty && settings.problems.length === 0
                             && !settings.store.busy
                    onClicked: settings.save()
                }
            }
        }
    }
}
