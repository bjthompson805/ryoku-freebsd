pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import "Singletons"

// Bluetooth subtab of Connections: adapter toggle, scan with 25 s auto-stop,
// live device list. known devices use Quickshell's connect/disconnect; unpaired
// ones run bluetoothctl pair-trust-connect with an inline ember while running
// and a transient failure line. ported from the shell's narrow LinkBt drill-in
// to a full-width hub page on the warm Theme palette. adapter/device state and
// the pair/scan/service-repair flows live in the shared BluetoothLink
// singleton (see ryoku/shared/quickshell/BluetoothLink.qml) so this page and
// the pill's LinkBt drill-in agree on them instead of racing separate copies.
Item {
    id: page

    readonly property bool adapterOn: BluetoothLink.adapter ? BluetoothLink.adapter.enabled === true : false

    // ---------- header band ------------------------------------------------
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 48

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            // BT rune.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24

                Shape {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    preferredRendererType: Shape.CurveRenderer
                    antialiasing: true
                    ShapePath {
                        strokeColor: page.adapterOn ? Theme.ember : Theme.dim
                        strokeWidth: 1.8
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: "M6.5 6.5l11 11L12 23V1l5.5 5.5L6.5 17.5" }
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "BLUETOOTH"
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: 2
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: page.adapterOn
                text: {
                    var known = BluetoothLink.devices.length;
                    if (known === 0)
                        return BluetoothLink.discovering ? "Scanning…" : "No devices yet";
                    if (BluetoothLink.connectedCount > 0)
                        return BluetoothLink.connectedCount + " connected · " + known + " known";
                    return known + " known";
                }
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            // scan toggle (only visible while adapter is on, mirroring the
            // shell). tap flips adapter.discovering and (re)arms the 25 s timer
            // so a forgotten scan doesn't keep the radio busy forever.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                visible: page.adapterOn
                width: scanPill.width
                height: scanPill.height

                Rectangle {
                    id: scanPill
                    radius: height / 2
                    height: 30
                    width: scanLbl.implicitWidth + 28
                    color: BluetoothLink.discovering ? Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.14)
                        : (scanHov.hovered ? Theme.keyTop : "transparent")
                    border.width: 1
                    border.color: BluetoothLink.discovering ? Theme.ember
                        : (scanHov.hovered ? Theme.ember : Theme.line)
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                    Text {
                        id: scanLbl
                        anchors.centerIn: parent
                        text: BluetoothLink.discovering ? "Scanning…" : "Scan"
                        color: BluetoothLink.discovering ? Theme.ember
                            : (scanHov.hovered ? Theme.bright : Theme.cream)
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    HoverHandler { id: scanHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: BluetoothLink.toggleScan() }
                }
            }

            // one primary toggle for the whole adapter. hidden when the
            // service is gone: a switch that can't act shouldn't look live.
            ToggleRow {
                anchors.verticalCenter: parent.verticalCenter
                visible: BluetoothLink.hasAdapter
                width: 56
                label: ""
                checked: page.adapterOn
                highlightId: "bluetooth_toggle"
                onToggled: (v) => BluetoothLink.setAdapterEnabled(v)
            }
        }
    }

    Rectangle {
        id: rule
        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.lineSoft
    }

    // ---------- body -------------------------------------------------------
    Item {
        id: body
        anchors.top: rule.bottom
        anchors.topMargin: 22
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // off / empty placeholder, centred so the page never looks broken.
        Column {
            anchors.centerIn: parent
            visible: !BluetoothLink.hasAdapter || !page.adapterOn || BluetoothLink.devices.length === 0
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !BluetoothLink.hasAdapter ? "Bluetooth isn't available."
                    : BluetoothLink.blocked ? "Bluetooth is blocked."
                    : !page.adapterOn ? "Bluetooth is off."
                    : (BluetoothLink.discovering ? "Scanning…" : "No devices yet.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !BluetoothLink.hasAdapter || !page.adapterOn || (!BluetoothLink.discovering && BluetoothLink.devices.length === 0)
                text: !BluetoothLink.hasAdapter ? "The bluetooth service (bluez) isn't running."
                    : BluetoothLink.blocked ? "The radio is off at the hardware level (rfkill); the toggle unblocks it."
                    : !page.adapterOn ? "Turn the adapter on to see nearby and paired devices."
                    : "Hit Scan to discover nearby devices."
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            // service repair, shown only when org.bluez is missing entirely.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !BluetoothLink.hasAdapter
                radius: height / 2
                height: 32
                width: svcLbl.implicitWidth + 32
                color: svcHov.hovered && !BluetoothLink.startingService ? Theme.keyTop : "transparent"
                border.width: 1
                border.color: BluetoothLink.startingService ? Theme.ember : (svcHov.hovered ? Theme.ember : Theme.line)
                Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                Text {
                    id: svcLbl
                    anchors.centerIn: parent
                    text: BluetoothLink.startingService ? "Starting…" : "Start service"
                    color: BluetoothLink.startingService ? Theme.ember : (svcHov.hovered ? Theme.bright : Theme.cream)
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                HoverHandler { id: svcHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: BluetoothLink.startService() }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: BluetoothLink.serviceFailed
                text: "Could not start the bluetooth service."
                color: Theme.ember
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        Flickable {
            id: devFlick
            visible: page.adapterOn && BluetoothLink.devices.length > 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - 48, 640)
            contentWidth: width
            contentHeight: devCol.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                id: sb
                policy: ScrollBar.AsNeeded
                width: 7
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: Theme.radius
                    color: Theme.line
                    opacity: sb.pressed ? 0.9 : (sb.hovered ? 0.7 : 0.4)
                    Behavior on opacity { NumberAnimation { duration: Theme.quick } }
                }
            }

            Column {
                id: devCol
                width: devFlick.width
                spacing: 8

                Repeater {
                    model: BluetoothLink.devicesSorted

                    delegate: Column {
                        id: dev

                        required property var modelData
                        readonly property bool isConnected: modelData ? modelData.connected === true : false
                        readonly property bool isPaired: modelData ? modelData.paired === true : false
                        readonly property string addr: (modelData && modelData.address) ? modelData.address : ""
                        readonly property bool pairing: addr.length > 0 && BluetoothLink.pairingAddress === addr
                        readonly property bool failed: addr.length > 0 && BluetoothLink.failedAddress === addr
                        readonly property int battery: BluetoothLink.batteryLevel(modelData)

                        width: parent.width
                        spacing: 4

                        Rectangle {
                            id: tile
                            width: parent.width
                            height: 64
                            radius: Theme.radius
                            color: dev.isConnected ? Theme.frameBg
                                : (rowHov.hovered ? Theme.keyTop : Theme.surfaceLo)
                            border.width: 1
                            border.color: dev.isConnected ? Theme.ember
                                : (rowHov.hovered ? Theme.line : Theme.lineSoft)
                            Behavior on color { ColorAnimation { duration: Theme.quick } }
                            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                            HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: BluetoothLink.activateDevice(dev.modelData) }

                            // BT rune tile.
                            Rectangle {
                                id: iconTile
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 40
                                radius: Theme.radius
                                color: dev.isConnected ? Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.16) : Theme.keyTop
                                border.width: 1
                                border.color: dev.isConnected ? Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.40) : Theme.line

                                Shape {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    preferredRendererType: Shape.CurveRenderer
                                    antialiasing: true
                                    ShapePath {
                                        strokeColor: dev.isConnected ? Theme.ember : Theme.subtle
                                        strokeWidth: 1.7
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin
                                        PathSvg { path: "M6.5 6.5l11 11L12 23V1l5.5 5.5L6.5 17.5" }
                                    }
                                }
                            }

                            Column {
                                anchors.left: iconTile.right
                                anchors.leftMargin: 14
                                anchors.right: rowRight.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: dev.modelData
                                        ? (dev.modelData.deviceName
                                            || dev.modelData.name
                                            || dev.addr
                                            || "Unknown")
                                        : "Unknown"
                                    color: dev.isConnected ? Theme.bright : Theme.cream
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    font.weight: dev.isConnected ? Font.DemiBold : Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: text.length > 0
                                    text: dev.pairing ? "pairing…" : BluetoothLink.metaFor(dev.modelData)
                                    color: dev.pairing ? Theme.ember : Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: rowRight
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                // pairing pulse.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: dev.pairing
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: Theme.ember

                                    SequentialAnimation on opacity {
                                        running: dev.pairing
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 1; duration: 600; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1; to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                                    }
                                }

                                // battery pill (connected + has a level).
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: dev.isConnected && dev.battery >= 0
                                    radius: 999
                                    color: Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.12)
                                    border.width: 1
                                    border.color: Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.32)
                                    height: 22
                                    width: battTxt.implicitWidth + 18

                                    Text {
                                        id: battTxt
                                        anchors.centerIn: parent
                                        text: Math.max(0, dev.battery) + "%"
                                        color: Theme.ember
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                // pair pill (unpaired, not currently pairing).
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !dev.isPaired && !dev.pairing
                                    radius: 999
                                    color: Theme.keyTop
                                    border.width: 1
                                    border.color: rowHov.hovered ? Theme.subtle : Theme.line
                                    height: 22
                                    width: pairTxt.implicitWidth + 18

                                    Text {
                                        id: pairTxt
                                        anchors.centerIn: parent
                                        text: "Pair"
                                        color: rowHov.hovered ? Theme.bright : Theme.cream
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                // disconnect hint.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: dev.isConnected
                                    radius: 999
                                    color: rowHov.hovered ? Theme.keyTop : "transparent"
                                    border.width: 1
                                    border.color: rowHov.hovered ? Theme.ember
                                        : Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.30)
                                    height: 22
                                    width: discTxt.implicitWidth + 18
                                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                                    Text {
                                        id: discTxt
                                        anchors.centerIn: parent
                                        text: "Disconnect"
                                        color: Theme.ember
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }

                        Text {
                            visible: dev.failed
                            width: parent.width
                            leftPadding: 66
                            text: "Pairing failed"
                            color: Theme.ember
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }
}
