pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../Singletons"

// notification toast content for the bar-edge popout at the bell: the latest
// live popup (icon, app, summary, body, actions) with a '+N' count for the
// ones queued behind it. body click opens the full inbox; the Toast keeps its
// own expire timer (Notifs.popups), so the popout melts shut when the queue
// drains. no background of its own -- the popout blob body supplies the washi
// surface, like every other popout.
Item {
    id: root

    property real s: 1
    property bool open: false

    signal openCenter()

    readonly property real padX: 16 * s
    readonly property real padY: 12 * s

    implicitWidth: 342 * s
    implicitHeight: (toastLoader.item ? toastLoader.item.implicitHeight : 44 * s) + 2 * padY

    Loader {
        id: toastLoader
        // active whenever a popup exists (even hidden under fullscreen), so the
        // Toast's expire timer keeps running and a null notif never binds.
        active: Notifs.popups.length > 0
        anchors.fill: parent
        anchors.topMargin: root.padY
        anchors.bottomMargin: root.padY
        anchors.leftMargin: root.padX
        anchors.rightMargin: root.padX

        sourceComponent: Item {
            implicitHeight: toastContent.implicitHeight

            Toast {
                id: toastContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                s: root.s
                live: root.open
                notif: Notifs.popups.length > 0 ? Notifs.popups[Notifs.popups.length - 1] : null
                onOpenCenter: root.openCenter()
            }

            // '+N' overflow: how many more popups wait behind this one.
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: Notifs.popups.length > 1
                text: "+" + (Notifs.popups.length - 1)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9 * root.s
                font.weight: Font.DemiBold
            }
        }
    }
}
