import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs

// Native StatusNotifier tray. Left click activates, middle click
// secondary-activates, right click opens the item's dbus menu.
Row {
    id: tray

    spacing: 2
    anchors.verticalCenter: parent.verticalCenter
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        Item {
            id: trayItem
            required property var modelData

            anchors.verticalCenter: parent.verticalCenter
            width: 19
            height: 19

            IconImage {
                anchors.centerIn: parent
                implicitSize: 13
                source: trayItem.modelData.icon
                opacity: itemMouse.containsMouse ? 1.0 : 0.85
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            QsMenuAnchor {
                id: menuAnchor
                menu: trayItem.modelData.menu
                anchor.item: trayItem
                anchor.rect.y: trayItem.height + 6
            }

            MouseArea {
                id: itemMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: (event) => {
                    if (event.button === Qt.RightButton && trayItem.modelData.hasMenu)
                        menuAnchor.open();
                    else if (event.button === Qt.MiddleButton)
                        trayItem.modelData.secondaryActivate();
                    else
                        trayItem.modelData.activate();
                }
            }
        }
    }
}
