import QtQuick
import Quickshell.Hyprland
import qs

// Six persistent numeric slots, plus any extra workspace that exists:
// higher numbers, named workspaces, and special workspaces. Named and
// special ones are labelled by NAME -- labelling them by id drew a pill
// with no meaningful number in it, which is the "blank circle".
Item {
    id: workspaces

    property int persistent: 6

    // Per-workspace icons, matching the window rules in hyprland.lua.
    // Keys are workspace numbers; anything without an entry falls back to
    // its number. Glyphs are classic Font Awesome codepoints (U+F0xx) --
    // the same range as the powermenu's working power icon. Swap any of
    // them for a glyph you prefer; it is one line each.
    readonly property var icons: ({
        1:  "\uf120",   // terminal        (default / unassigned)
        2:  "\uf269",   // firefox         zen
        3:  "\uf07b",   // folder          thunar
        4:  "\uf121",   // code            zed, intellij
        5:  "\uf086",   // comments        vesktop, calibre
        6:  "\uf02d",   // book            obsidian, localsend
        7:  "\uf233",   // server          virt-manager
        8:  "\uf0e0",   // envelope        thunderbird, qbittorrent
        9:  "\uf0ae",   // tasks           superProductivity
        10: "\uf084"    // key             keepassxc
    })

    readonly property int slotWidth: 22
    readonly property int focusExtra: 18
    readonly property int gap: 5

    function labelWidth(text) {
        // JetBrainsMono at 10px advances ~6.2px per glyph.
        return text.length <= 2 ? slotWidth
             : Math.round(text.length * 6.2) + 14;
    }

    readonly property var slots: {
        const out = [];
        for (let i = 1; i <= persistent; i++)
            out.push({
                wsid: i,
                label: String(i),
                icon: icons[i] ?? "",
                special: false
            });

        const live = Hyprland.workspaces.values;

        // Numeric workspaces past the persistent range.
        live.filter((w) => w.id > persistent)
            .sort((a, b) => a.id - b.id)
            .forEach((w) => out.push({
                wsid: w.id,
                label: String(w.id),
                icon: icons[w.id] ?? "",
                special: false
            }));

        // Named and special workspaces: negative ids in Hyprland.
        live.filter((w) => w.id < 0)
            .sort((a, b) => b.id - a.id)
            .forEach((w) => {
                const raw = w.name ?? "";
                const isSpecial = raw.startsWith("special:") || w.id <= -99;
                const nm = raw.replace(/^special:/, "");
                out.push({
                    wsid: w.id,
                    label: nm !== "" ? nm : String(w.id),
                    icon: "",
                    special: isSpecial
                });
            });

        return out;
    }

    function workspaceExists(id) {
        return Hyprland.workspaces.values.some((w) => w.id === id);
    }

    // Footprint reserves one focus-expansion up front, so moving between
    // workspaces animates inside a fixed box instead of shoving the
    // island around. It only changes when a workspace appears or dies.
    anchors.verticalCenter: parent.verticalCenter
    width: {
        let w = 0;
        for (const s of slots)
            w += labelWidth(s.icon !== "" ? "0" : s.label) + gap;
        return Math.max(0, w - gap) + focusExtra;
    }
    height: 18

    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: workspaces.gap

        Repeater {
            model: workspaces.slots

            Rectangle {
                id: wsButton
                required property var modelData
                readonly property int wsId: modelData.wsid
                readonly property bool focused: Hyprland.focusedWorkspace !== null
                    && Hyprland.focusedWorkspace.id === wsId
                readonly property bool occupied: workspaces.workspaceExists(wsId)

                anchors.verticalCenter: parent.verticalCenter
                width: workspaces.labelWidth(
                        modelData.icon !== "" ? "0" : modelData.label)
                    + (focused ? workspaces.focusExtra : 0)
                height: 18
                radius: 9
                color: focused || occupied
                     ? (modelData.special ? Colors.warn : Colors.accent)
                     : wsMouse.containsMouse ? Qt.alpha(Colors.textMain, 0.5)
                     : Colors.surface1

                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    text: wsButton.modelData.icon !== ""
                        ? wsButton.modelData.icon : wsButton.modelData.label
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: wsButton.modelData.icon !== "" ? 11 : 10
                    font.weight: Font.Bold
                    color: wsButton.focused || wsButton.occupied
                         ? Colors.accentFg : Colors.textFaint
                }

                MouseArea {
                    id: wsMouse
                    // Taller than the pill itself: the full bar height is
                    // clickable, not just the 18px strip.
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    // Hyprland >= 0.55 with a Lua config root evaluates
                    // dispatch requests as Lua. Special workspaces need
                    // the toggle dispatcher, not focus.
                    onClicked: {
                        if (wsButton.modelData.special) {
                            Hyprland.dispatch(
                                "hl.dsp.togglespecialworkspace({ name = \"" +
                                wsButton.modelData.label + "\" })");
                        } else {
                            Hyprland.dispatch(
                                "hl.dsp.focus({ workspace = " + wsButton.wsId + " })");
                        }
                    }
                }
            }
        }
    }
}
