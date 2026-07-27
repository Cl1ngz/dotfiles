import QtQuick
import Quickshell.Hyprland
import qs

// Six persistent slots plus any live workspace beyond them. The root
// Item reserves the full width up front -- including the +18px the
// focused pill grows by -- so switching workspaces animates *inside*
// a fixed footprint instead of resizing the island around it.
Item {
    id: workspaces

    property int persistent: 6
    readonly property int slotWidth: 22
    readonly property int focusExtra: 18
    readonly property int gap: 5

    readonly property var slots: {
        const ids = [];
        for (let i = 1; i <= persistent; i++) ids.push(i);
        const extra = Hyprland.workspaces.values
            .filter((w) => w.id > persistent)
            .map((w) => w.id)
            .sort((a, b) => a - b);
        return ids.concat(extra);
    }

    function workspaceExists(id) {
        return Hyprland.workspaces.values.some((w) => w.id === id);
    }

    anchors.verticalCenter: parent.verticalCenter
    width: slots.length * (slotWidth + gap) - gap + focusExtra
    height: 18

    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: workspaces.gap

        Repeater {
            model: workspaces.slots

            Rectangle {
                id: wsButton
                required property int modelData
                readonly property int wsId: modelData
                readonly property bool focused: Hyprland.focusedWorkspace !== null
                    && Hyprland.focusedWorkspace.id === wsId
                readonly property bool occupied: workspaces.workspaceExists(wsId)

                anchors.verticalCenter: parent.verticalCenter
                width: focused ? workspaces.slotWidth + workspaces.focusExtra : workspaces.slotWidth
                height: 18
                radius: 9
                color: focused || occupied ? Colors.accent
                     : wsMouse.containsMouse ? Qt.alpha(Colors.textMain, 0.5)
                     : Colors.surface1

                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    text: wsButton.wsId
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: wsButton.focused || wsButton.occupied ? Colors.accentFg : Colors.textFaint
                }

                MouseArea {
                    id: wsMouse
                    // Taller than the pill itself: the full bar height is
                    // clickable, not just the 18px strip.
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    // Hyprland >= 0.55 with a Lua config root evaluates
                    // dispatch requests as Lua: hl.dispatch(<request>).
                    // Classic-root Hyprland would want the old form instead:
                    // Hyprland.dispatch("workspace " + wsButton.wsId)
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsButton.wsId + " })")
                }
            }
        }
    }
}
