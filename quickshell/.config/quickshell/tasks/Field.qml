import QtQuick
import qs

// Text input.
//
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
    signal submitted()
    signal edited()
    function focusInput() { fi.forceActiveFocus(); }

    height: 30
    radius: 8
    color: Colors.mantle
    border.width: 1
    border.color: fi.activeFocus ? Qt.alpha(Colors.accent, 0.7) : Colors.outline
    Behavior on border.color { ColorAnimation { duration: 130 } }

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
        onTextEdited: field.edited()
        Keys.onReturnPressed: field.submitted()
        Keys.onEnterPressed: field.submitted()

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
        onPressed: (mouse) => { fi.forceActiveFocus(); mouse.accepted = false; }
    }
}
