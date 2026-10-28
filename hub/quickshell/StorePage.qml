import QtQuick
import "Singletons"

// Ryoku Store: browse + install shell plugins. managing what's already
// installed lives on Add-ons, so this only browses + installs.
Item {
    id: store

    ShowcaseBackdrop { anchors.fill: parent }

    Row {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: 12
        z: 3

        Rectangle {
            id: refreshBtn
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: Theme.radius
            readonly property bool spinning: pluginsPage.refreshing
            color: rHover.hovered ? Theme.surface : "transparent"
            border.width: 1
            border.color: rHover.hovered ? Theme.ember : Theme.line
            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

            Icon {
                anchors.centerIn: parent
                name: "refresh"
                size: 15
                weight: 2
                tint: rHover.hovered ? Theme.bright : Theme.dim
                RotationAnimation on rotation { running: refreshBtn.spinning; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
            }
            HoverHandler { id: rHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    pluginsPage.refreshing = true;
                    pluginsPage.loadCatalog();
                    pluginsPage.refresh();
                }
            }
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: head.bottom
        anchors.topMargin: 18
        anchors.bottom: parent.bottom

        PluginsPage {
            id: pluginsPage
            anchors.fill: parent
            storeMode: true
        }

    }
}
