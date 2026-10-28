pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "Singletons"

// system tray icons, one hover-lifted cell each. `vertical` stacks them for a
// side bar. right-click opens the item menu anchored to the band edge.
Grid {
    id: tray

    property real s: 1
    property bool vertical: false
    required property var trayWindow
    // y the tray menus anchor to (the band's inner edge).
    property real menuEdgeY: 0

    readonly property int count: SystemTray.items ? SystemTray.items.values.length : 0

    columns: vertical ? 1 : Math.max(1, count)
    spacing: 9 * s
    verticalItemAlignment: Grid.AlignVCenter
    horizontalItemAlignment: Grid.AlignHCenter

    Repeater {
        model: SystemTray.items
        delegate: Item {
            id: trayItem
            required property var modelData
            width: 16 * tray.s
            height: 16 * tray.s
            opacity: trayArea.containsMouse ? 1 : 0.78
            Behavior on opacity { NumberAnimation { duration: Motion.hover } }

            IconImage {
                anchors.fill: parent
                source: trayItem.modelData ? trayItem.modelData.icon : ""
            }
            MouseArea {
                id: trayArea
                anchors.fill: parent
                anchors.margins: -3 * tray.s
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (e) => {
                    if (!trayItem.modelData)
                        return;
                    if (e.button === Qt.RightButton && trayItem.modelData.hasMenu)
                        trayItem.modelData.display(tray.trayWindow, trayItem.mapToItem(null, trayItem.width / 2, 0).x, tray.menuEdgeY);
                    else
                        trayItem.modelData.activate();
                }
            }
        }
    }
}
