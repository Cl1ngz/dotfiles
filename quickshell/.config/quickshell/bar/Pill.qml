import QtQuick
import qs

// The base "module" look from the waybar css: rounded pill on a faint
// fill, with the inset-underline glow on hover. Every simple widget is
// a Pill; widgets with custom content (workspaces, tray) build their
// own but reuse the same constants.
Rectangle {
    id: pill

    property string icon: ""
    property int iconSize: 15
    property string label: ""
    // Colour of the icon/text; the hover underline always uses accent,
    // matching the waybar hover glow which was always @red.
    property color tint: Colors.textMain
    property bool interactive: true
    // Right click shows/hides the label. The one resize this causes is
    // user-initiated, and the width Behavior animates it.
    property bool toggleableLabel: false
    property bool labelVisible: true

    signal clicked(int button)
    signal scrolled(int steps)

    implicitHeight: 28
    implicitWidth: content.implicitWidth + 16
    radius: 12

    // Labels change length (volume %, battery %); glide instead of jumping.
    Behavior on implicitWidth {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    color: mouse.containsMouse && interactive ? Colors.base : Qt.alpha(Colors.textMain, 0.10)

    Behavior on color {
        ColorAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 5

        Text {
            visible: pill.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: pill.icon
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: pill.iconSize
            color: pill.tint
            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }
        }
        Text {
            visible: pill.label !== "" && pill.labelVisible
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.Bold
            color: pill.tint
            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }
        }
    }

    // waybar's `box-shadow: inset 0 -2px @red` hover glow.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: mouse.containsMouse && pill.interactive ? parent.width - 10 : 0
        height: 2
        radius: 1
        color: Colors.accent
        Behavior on width {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            if (pill.toggleableLabel && event.button === Qt.RightButton) {
                pill.labelVisible = !pill.labelVisible;
                return;
            }
            pill.clicked(event.button);
        }
        onWheel: wheel => pill.scrolled(wheel.angleDelta.y > 0 ? 1 : -1)
    }
}
