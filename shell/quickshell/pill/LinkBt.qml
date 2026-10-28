pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

// bluetooth drill-in for the link surface. back chevron, scan with 25s
// auto-stop, adapter toggle, live device list. known devices use Quickshell
// connect/disconnect; unpaired = bluetoothctl pair-trust-connect with an
// inline ember while running + a transient failure line. adapter/device state
// and the pair/scan/service-repair flows live in the shared BluetoothLink
// singleton (see ryoku/shared/quickshell/BluetoothLink.qml) so this drill-in
// and the Hub's BluetoothTab agree on them instead of racing separate copies.
Item {
    id: root

    property real s: 1
    property bool active: false
    // compact = embedded as popout content (a bar popout): drop the drill-in
    // chrome so the host frame owns the header. hides the back chevron and the
    // redundant "BLUETOOTH" title (the popout supplies its own eyebrow); the
    // adapter toggle, scan control, and device list all stay. default false is
    // a strict no-op for the Link surface.
    property bool compact: false

    signal back()

    implicitHeight: listFrame.y + listFrame.height

    onActiveChanged: if (!active) BluetoothLink.stopScan()

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s

            Item {
                visible: !root.compact
                anchors.verticalCenter: parent.verticalCenter
                width: 17 * root.s
                height: 17 * root.s

                GlyphIcon {
                    anchors.fill: parent
                    name: "chevron-left"
                    color: backArea.containsMouse ? Theme.cream : Theme.iconDim
                    stroke: 1.8
                }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.back()
                }
            }

            Text {
                visible: !root.compact
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

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: BluetoothLink.adapter ? BluetoothLink.adapter.enabled === true : false
                text: BluetoothLink.discovering ? "Scanning…" : "Scan"
                color: BluetoothLink.discovering ? Theme.vermLit : Theme.dim
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
            }

            // compact hosts (the popout) pin their own refresh button in the
            // header they own, so only the standalone drill-in draws one here.
            RefreshButton {
                s: root.s
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.compact && (BluetoothLink.adapter ? BluetoothLink.adapter.enabled === true : false)
                spinning: BluetoothLink.discovering
                onClicked: BluetoothLink.startScan()
            }

            LinkToggle {
                s: root.s
                visible: BluetoothLink.hasAdapter
                anchors.verticalCenter: parent.verticalCenter
                on: BluetoothLink.adapter ? BluetoothLink.adapter.enabled === true : false
                onToggled: if (BluetoothLink.adapter) BluetoothLink.setAdapterEnabled(BluetoothLink.adapter.enabled !== true)
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }

    Item {
        id: listFrame
        anchors.top: divider.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: BluetoothLink.devices.length > 0 ? Math.min(devCol.implicitHeight, 200 * root.s) : 24 * root.s

        Text {
            visible: BluetoothLink.devices.length === 0
            anchors.left: parent.left
            anchors.leftMargin: 6 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: !BluetoothLink.hasAdapter
                ? (BluetoothLink.startingService ? "Starting service…"
                    : (BluetoothLink.serviceFailed ? "Couldn't start the service" : "Service off — tap to start"))
                : (BluetoothLink.blocked ? "Blocked (rfkill) — toggle to unblock"
                    : (BluetoothLink.discovering ? "Scanning…" : "No devices"))
            color: !BluetoothLink.hasAdapter && !BluetoothLink.startingService && !BluetoothLink.serviceFailed ? Theme.subtle : Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.Medium

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6 * root.s
                visible: !BluetoothLink.hasAdapter && !BluetoothLink.startingService
                cursorShape: Qt.PointingHandCursor
                onClicked: BluetoothLink.startService()
            }
        }

        Flickable {
            id: devFlick
            visible: BluetoothLink.devices.length > 0
            anchors.fill: parent
            contentHeight: devCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: devCol
                width: devFlick.width
                spacing: 2 * root.s

                Repeater {
                    model: BluetoothLink.devicesSorted

                    Column {
                        id: devItem
                        required property var modelData
                        readonly property bool isConnected: modelData ? modelData.connected === true : false
                        readonly property bool isPaired: modelData ? modelData.paired === true : false
                        readonly property string addr: (modelData && modelData.address) ? modelData.address : ""
                        readonly property bool pairing: addr.length > 0 && BluetoothLink.pairingAddress === addr
                        readonly property bool failed: addr.length > 0 && BluetoothLink.failedAddress === addr
                        readonly property int battery: BluetoothLink.batteryLevel(modelData)
                        width: devCol.width
                        spacing: 2 * root.s

                        Rectangle {
                            width: parent.width
                            height: 38 * root.s
                            radius: Theme.radius
                            color: rowHover.hovered ? Theme.frameBg : "transparent"

                            HoverHandler { id: rowHover }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: BluetoothLink.activateDevice(devItem.modelData)
                            }

                            Rectangle {
                                id: devTile
                                anchors.left: parent.left
                                anchors.leftMargin: 6 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26 * root.s
                                height: 26 * root.s
                                radius: Theme.radius
                                color: Theme.tileBg
                                border.width: 1
                                border.color: Theme.border

                                GlyphIcon {
                                    anchors.centerIn: parent
                                    width: 15 * root.s
                                    height: 15 * root.s
                                    name: "bluetooth"
                                    color: devItem.isConnected ? Theme.vermLit : Theme.iconDim
                                    stroke: 1.7
                                }
                            }

                            Column {
                                anchors.left: devTile.right
                                anchors.leftMargin: 10 * root.s
                                anchors.right: devRight.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1 * root.s

                                Text {
                                    width: parent.width
                                    text: devItem.modelData ? (devItem.modelData.deviceName || devItem.modelData.name || "Unknown") : "Unknown"
                                    color: devItem.isConnected ? Theme.cream : Theme.subtle
                                    font.family: Theme.font
                                    font.pixelSize: 11.5 * root.s
                                    font.weight: devItem.isConnected ? Font.DemiBold : Font.Medium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: text.length > 0
                                    text: BluetoothLink.metaFor(devItem.modelData)
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 9.5 * root.s
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: devRight
                                anchors.right: parent.right
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8 * root.s

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: devItem.pairing
                                    width: 4 * root.s
                                    height: 4 * root.s
                                    radius: width / 2
                                    color: Theme.flameGlow

                                    SequentialAnimation on opacity {
                                        running: devItem.pairing
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 1; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1; to: 0.35; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                    }
                                }

                                Filament {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: devItem.isConnected && devItem.battery >= 0
                                    s: root.s
                                    kind: "battery"
                                    level: Math.max(0, devItem.battery) / 100
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !devItem.isPaired && !devItem.pairing
                                    radius: 999
                                    color: Theme.tileBg
                                    border.width: 1
                                    border.color: Theme.border
                                    height: 18 * root.s
                                    width: pairText.implicitWidth + 16 * root.s

                                    Text {
                                        id: pairText
                                        anchors.centerIn: parent
                                        text: "Pair"
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: 9.5 * root.s
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }

                        Text {
                            visible: devItem.failed
                            text: "Pairing failed"
                            color: Theme.vermLit
                            font.family: Theme.font
                            font.pixelSize: 9.5 * root.s
                            leftPadding: 42 * root.s
                        }
                    }
                }
            }
        }

        WheelScroller {
            anchors.fill: parent
            s: root.s
            flick: devFlick
        }
    }
}
