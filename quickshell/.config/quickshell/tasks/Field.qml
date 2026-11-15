// Text input.

import QtQuick
import qs

// Escape is deliberately NOT handled here. It used to be, because a
// layer-shell PanelWindow is not an Item and Keys attached to it never
// fire -- but that made Escape depend on a field having focus, so it
// died the moment you clicked a chip. The window uses an application
// Shortcut instead, and this must not swallow the key.
Rectangle {
    id: field

    property alias text: fi.text
    property string placeholder: ""
    property int fontSize: 12
    // When true, Tab is handed to the owner (completion) instead of
    // moving focus to the next field.
    property bool captureTab: false
    // True while the text box inside has the keyboard. The Rectangle
    // itself never does, so `activeFocus` on a Field is always false.
    readonly property bool inputFocused: fi.activeFocus

    signal submitted()
    // Ctrl+Enter: "do it and close" in the add row.
    signal ctrlSubmitted()
    signal edited()
    // Up / Down, and Ctrl+P / Ctrl+N / Ctrl+K / Ctrl+J -- the keys vim's
    // completion menu uses -- for moving through a list from a field.
    signal upPressed()
    signal downPressed()
    signal tabPressed()

    function focusInput() {
        fi.forceActiveFocus();
    }

    function enterKey(e) {
        if (e.modifiers & Qt.ControlModifier)
            field.ctrlSubmitted();
        else
            field.submitted();
        e.accepted = true;
    }

    height: 30
    radius: 8
    color: Colors.mantle
    border.width: 1
    border.color: fi.activeFocus ? Qt.alpha(Colors.accent, 0.7) : Colors.outline

    TextInput {
        id: fi

        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: field.fontSize
        color: Colors.textMain
        clip: true
        selectByMouse: true
        selectionColor: Qt.alpha(Colors.accent, 0.35)
        // In the Tab chain, so Tab / Shift+Tab walk between fields.
        activeFocusOnTab: true
        onTextEdited: field.edited()
        Keys.onReturnPressed: (e) => field.enterKey(e)
        Keys.onEnterPressed: (e) => field.enterKey(e)
        Keys.onUpPressed: (e) => {
            field.upPressed();
            e.accepted = true;
        }
        Keys.onDownPressed: (e) => {
            field.downPressed();
            e.accepted = true;
        }
        Keys.onTabPressed: (e) => {
            if (field.captureTab) {
                field.tabPressed();
                e.accepted = true;
            } else {
                e.accepted = false;
            }
        }
        Keys.onPressed: (e) => {
            if (!(e.modifiers & Qt.ControlModifier))
                return ;

            switch (e.key) {
            case Qt.Key_N:
            case Qt.Key_J:
                field.downPressed();
                e.accepted = true;
                break;
            case Qt.Key_P:
            case Qt.Key_K:
                field.upPressed();
                e.accepted = true;
                break;
            case Qt.Key_W: {
                // Delete the word before the cursor, as in vim's insert
                // mode and every shell.
                const before = fi.text.slice(0, fi.cursorPosition);
                const kept = before.replace(/\S+\s*$|\s+$/, "");
                fi.remove(kept.length, fi.cursorPosition);
                field.edited();
                e.accepted = true;
                break;
            }
            case Qt.Key_U:
                // Delete back to the start of the line.
                fi.remove(0, fi.cursorPosition);
                field.edited();
                e.accepted = true;
                break;
            }
        }

        Text {
            visible: fi.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: field.placeholder
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: field.fontSize
            color: Colors.textFaint
        }

    }

    // Layer-shell hands the window the keyboard on click, but the click
    // still has to land on something that claims QML focus.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: (mouse) => {
            fi.forceActiveFocus();
            mouse.accepted = false;
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: 130
        }

    }

}
