import QtQuick
import qs

// A one-of-many picker that does not grow with the list.
//
// Chips laid out in a Flow are fine for five importance levels and
// hopeless for fifty categories: the picker becomes taller than the
// thing it belongs to, the add row pushes the task list off the card,
// and the same wall of chips appears again inside every open editor.
//
// So: a compact trigger showing the current value, and an expansion
// with a search box and a scrolling list. It expands INLINE rather
// than floating. A floating popup would be clipped by the card and by
// any Flickable it sits in, and fighting that is not worth it when
// pushing the content down reads fine and can never be cut off.
Item {
    id: picker

    property string placeholder: "none"
    // [{ name, color }] -- colour may be absent.
    property var options: []
    property var current: null
    property bool allowNone: true
    property bool open: false
    // Shown on the trigger before the value, e.g. "category".
    property string prefix: ""

    signal toggled()
    signal picked(var value)

    implicitHeight: col.implicitHeight
    height: implicitHeight

    onOpenChanged: if (open) search.focusInput(); else search.text = "";

    function labelFor(v) {
        if (v === null || v === undefined) return placeholder;
        return "" + v;
    }
    function colorFor(v) {
        for (const o of options) if (o.name === v) return o.color ?? Colors.textFaint;
        return Colors.textFaint;
    }

    readonly property var filtered: {
        const q = search.text.toLowerCase().trim();
        if (q === "") return options;
        // Prefix matches first: typing "ho" should put "home" above
        // "household chores" even though both match.
        const pre = [];
        const sub = [];
        for (const o of options) {
            const n = o.name.toLowerCase();
            if (n.startsWith(q)) pre.push(o);
            else if (n.indexOf(q) !== -1) sub.push(o);
        }
        return pre.concat(sub);
    }

    Column {
        id: col
        width: parent.width
        spacing: 6

        // ---- trigger ---------------------------------------------------

        Rectangle {
            id: trigger
            width: parent.width
            height: 26
            radius: 7
            color: picker.open ? Colors.surface1
                 : trigMouse.containsMouse ? Colors.surface0 : "transparent"
            border.width: 1
            border.color: picker.open ? Qt.alpha(Colors.accent, 0.6) : Colors.outline
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: picker.current !== null
                    width: 8
                    height: 8
                    radius: 4
                    color: picker.colorFor(picker.current)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: picker.prefix !== ""
                    text: picker.prefix
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    color: Colors.textFaint
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: picker.labelFor(picker.current)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    color: picker.current === null ? Colors.textFaint : Colors.textMain
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: picker.open ? "▾" : "▸"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                color: Colors.textFaint
            }

            MouseArea {
                id: trigMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.toggled()
            }
        }

        // ---- expansion -------------------------------------------------

        Rectangle {
            visible: picker.open
            width: parent.width
            implicitHeight: body.implicitHeight + 12
            radius: 8
            color: Colors.mantle
            border.width: 1
            border.color: Colors.outline

            Column {
                id: body
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                spacing: 5

                Field {
                    id: search
                    width: parent.width
                    fontSize: 11
                    placeholder: "filter…"
                    // Enter takes the top match, so a long list is
                    // three keystrokes rather than a scroll.
                    onSubmitted: {
                        if (picker.filtered.length > 0)
                            picker.picked(picker.filtered[0].name);
                    }
                }

                // "none" is an entry in the list rather than a chip
                // beside it, so there is exactly one place to look.
                Rectangle {
                    visible: picker.allowNone && search.text === ""
                    width: parent.width
                    height: 24
                    radius: 6
                    color: noneMouse.containsMouse ? Colors.surface1 : "transparent"
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: picker.placeholder
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        color: picker.current === null ? Colors.accent : Colors.textFaint
                    }
                    MouseArea {
                        id: noneMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.picked(null)
                    }
                }

                ListView {
                    id: optList
                    width: parent.width
                    // Capped and scrolling: fifty categories must not
                    // make this taller than the card.
                    height: Math.min(contentHeight, 170)
                    clip: true
                    model: picker.filtered
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: optRow
                        required property var modelData
                        width: optList.width
                        height: 24
                        radius: 6
                        readonly property bool chosen: picker.current === modelData.name
                        color: optMouse.containsMouse ? Colors.surface1
                             : chosen ? Qt.alpha(Colors.accent, 0.12) : "transparent"

                        Rectangle {
                            id: dot
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: optRow.modelData.color ?? Colors.textFaint
                        }
                        Text {
                            anchors.left: dot.right
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
                            onClicked: picker.picked(optRow.modelData.name)
                        }
                    }
                }

                Text {
                    visible: picker.filtered.length === 0
                    width: parent.width
                    text: "no match"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    color: Colors.textFaint
                }
            }
        }
    }
}
