pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../Singletons"

// bluetooth popout content: a compact bluetooth control center that reuses the
// LinkBt drill-in with its surface-only chrome stripped (no back chevron, no
// redundant title -- the eyebrow below already says BLUETOOTH). a BLUETOOTH
// header (with the scan refresh button pinned top-right) over LinkBt's live
// adapter toggle, connect/pair flow and the signal-sorted device list. plain transparent Item -- the frame blob behind it
// IS the surface; Popout reads the reported implicit size to melt open to fit
// and grows as the list fills or a device pairs. pointer-driven, no keyboard focus.
Item {
    id: root

    property real s: 1
    // popout open: gates LinkBt's scan/discovery so the radio never spins while closed.
    property bool open: false

    anchors.fill: parent

    implicitWidth: 300 * s
    implicitHeight: body.implicitHeight + 27 * s

    Column {
        id: body
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 13 * root.s
        anchors.leftMargin: 16 * root.s
        anchors.rightMargin: 16 * root.s
        spacing: 11 * root.s

        Item {
            width: parent.width
            height: Math.max(headerRow.implicitHeight, refreshBtn.height)

            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "bluetooth"
                    fill: 1
                    color: Theme.brand
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BLUETOOTH"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6 * root.s
                }
            }

            // the scan trigger: a scan is a refresh of the device list.
            RefreshButton {
                id: refreshBtn
                s: root.s
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: BluetoothLink.adapter ? BluetoothLink.adapter.enabled === true : false
                spinning: BluetoothLink.discovering
                onClicked: BluetoothLink.startScan()
            }
        }

        LinkBt {
            compact: true
            s: root.s
            active: root.open
            enabled: root.open
            width: parent.width
        }
    }
}
