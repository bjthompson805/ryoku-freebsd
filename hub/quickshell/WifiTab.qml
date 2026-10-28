pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Singletons"

// wi-fi subtab. master on/off, rescan (spins ~10s), live list sorted by signal.
// nmcli scan/connect state, security lookups, and the connect flow all live in
// the shared WifiLink singleton (see ryoku/shared/quickshell/WifiLink.qml) so
// this page and the pill's LinkWifi drill-in agree on them instead of racing
// separate copies. parent Loader recreates the page on tab change; the device
// scanner runs while we're visible (setScannerActive), and mount/unmount also
// drives WifiLink's own list refresh.
Item {
    id: page

    // content column cap on this wide hub page.
    readonly property real colMax: 640

    Component.onCompleted: { WifiLink.setScannerActive(true); WifiLink.refresh(); }
    Component.onDestruction: WifiLink.setScannerActive(false)

    // ---- layout -----------------------------------------------------------

    Item {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: Math.min(parent.width, page.colMax)

        // header row. "WI-FI" label + hairline + scan button.
        Item {
            id: bar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 40

            Text {
                id: secLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "WI-FI"
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 2
            }

            Rectangle {
                anchors.left: secLabel.right
                anchors.leftMargin: 14
                anchors.right: scanBtn.visible ? scanBtn.left : parent.right
                anchors.rightMargin: scanBtn.visible ? 14 : 0
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Theme.lineSoft
            }

            HubButton {
                id: scanBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: WifiLink.wifiOn
                label: WifiLink.scanning ? "Scanning…" : "Scan"
                icon: "refresh"
                enabled: !WifiLink.scanning
                onClicked: WifiLink.startScan()
            }
        }

        // master on/off. same toggle as the link surface, but labelled so it
        // reads as a setting on this page.
        ToggleRow {
            id: wifiToggle
            anchors.top: bar.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            label: "Wi-Fi"
            highlightId: "wifi_toggle"
            checked: WifiLink.wifiOn
            onToggled: (v) => WifiLink.setWifiEnabled(v)
        }

        Rectangle {
            id: divider
            anchors.top: wifiToggle.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.lineSoft
        }

        // empty states. both pin to the divider so we never double-stack a
        // message and a possibly-empty flickable.
        Text {
            anchors.top: divider.bottom
            anchors.topMargin: 28
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !WifiLink.wifiOn
            text: "Wi-Fi is off."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Row {
            anchors.top: divider.bottom
            anchors.topMargin: 28
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            visible: WifiLink.wifiOn && WifiLink.netsSorted.length === 0

            Spinner {
                anchors.verticalCenter: parent.verticalCenter
                size: 14
                tint: Theme.faint
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Searching networks…"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        // live network list.
        Flickable {
            id: netFlick
            anchors.top: divider.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: WifiLink.wifiOn && WifiLink.netsSorted.length > 0
            contentHeight: netCol.implicitHeight + 16
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
                id: netCol
                width: netFlick.width
                topPadding: 2
                spacing: 4

                Repeater {
                    model: WifiLink.netsSorted

                    delegate: Column {
                        id: netItem
                        required property var modelData

                        readonly property string ssid: (modelData && modelData.name) ? modelData.name : ""
                        readonly property bool isActive: modelData ? modelData.connected === true : false
                        readonly property bool secured: WifiLink.isSecured(ssid)
                        readonly property bool known: WifiLink.knownProfiles[ssid] === true
                        readonly property bool expanded: ssid.length > 0 && WifiLink.expandedSsid === ssid
                        readonly property int strength: modelData ? Math.round((modelData.signalStrength || 0)) : 0

                        width: netCol.width
                        spacing: 4

                        function syncPwField() {
                            pwField.text = WifiLink.pwDraft;
                            pwField.cursorPosition = pwField.text.length;
                            pwField.forceActiveFocus();
                        }

                        onExpandedChanged: if (expanded) Qt.callLater(syncPwField)
                        Component.onCompleted: if (expanded) Qt.callLater(syncPwField)

                        // the row itself.
                        Rectangle {
                            id: rowBg
                            width: parent.width
                            height: 46
                            radius: Theme.radius
                            color: netItem.isActive
                                ? Theme.frameBg
                                : (rowHover.hovered ? Theme.surfaceLo : "transparent")
                            Behavior on color { ColorAnimation { duration: Theme.quick } }

                            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: WifiLink.activateNetwork(netItem.modelData) }

                            // signal bars: 4 ascending rects, bottom-anchored.
                            Item {
                                id: bars
                                width: 21
                                height: 16
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.verticalCenter: parent.verticalCenter

                                readonly property int filled: Math.max(0, Math.min(4, Math.ceil(netItem.strength / 25)))
                                readonly property color litColor: netItem.isActive ? Theme.brand : Theme.cream
                                readonly property color dimColor: Theme.faint

                                Rectangle {
                                    x: 0; width: 3; height: 4
                                    y: bars.height - height
                                    radius: Theme.radius
                                    color: bars.filled > 0 ? bars.litColor : bars.dimColor
                                }
                                Rectangle {
                                    x: 6; width: 3; height: 8
                                    y: bars.height - height
                                    radius: Theme.radius
                                    color: bars.filled > 1 ? bars.litColor : bars.dimColor
                                }
                                Rectangle {
                                    x: 12; width: 3; height: 12
                                    y: bars.height - height
                                    radius: Theme.radius
                                    color: bars.filled > 2 ? bars.litColor : bars.dimColor
                                }
                                Rectangle {
                                    x: 18; width: 3; height: 16
                                    y: bars.height - height
                                    radius: Theme.radius
                                    color: bars.filled > 3 ? bars.litColor : bars.dimColor
                                }
                            }

                            // ssid + status hint.
                            Column {
                                anchors.left: bars.right
                                anchors.leftMargin: 14
                                anchors.right: rowRight.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: netItem.ssid
                                    color: netItem.isActive ? Theme.brand : Theme.cream
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    font.weight: netItem.isActive ? Font.DemiBold : Font.Medium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: netItem.isActive
                                        ? "Connected"
                                        : (netItem.known
                                            ? (netItem.secured ? "Saved · Secured" : "Saved · Open")
                                            : (netItem.secured ? "Secured" : "Open"))
                                    color: netItem.isActive ? Theme.ember : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }

                            // right side: lock + signal %.
                            Row {
                                id: rowRight
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: netItem.secured
                                    name: "lock"
                                    size: 14
                                    weight: 1.7
                                    tint: netItem.isActive ? Theme.ember : Theme.dim
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: netItem.strength + "%"
                                    color: Theme.subtle
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }

                        // password row. secured + unknown only.
                        Item {
                            width: parent.width
                            height: netItem.expanded ? 44 : 0
                            clip: true
                            visible: height > 0.5
                            opacity: netItem.expanded ? 1 : 0
                            Behavior on height { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }
                            Behavior on opacity { NumberAnimation { duration: Theme.quick } }

                            Rectangle {
                                id: pwBg
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.right: pwRight.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                height: 32
                                radius: Theme.radius
                                color: Theme.surfaceLo
                                border.width: 1
                                border.color: pwField.activeFocus ? Theme.ember : Theme.line
                                Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                                TextField {
                                    id: pwField
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    background: null
                                    padding: 0
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.bright
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                    echoMode: TextInput.Password
                                    placeholderText: "Password"
                                    placeholderTextColor: Theme.faint
                                    selectByMouse: true
                                    selectionColor: Theme.ember
                                    onTextEdited: WifiLink.pwDraft = text
                                    onAccepted: WifiLink.connectWithPassword(netItem.ssid, text)
                                }
                            }

                            Row {
                                id: pwRight
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    height: 24
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "close"
                                        size: 13
                                        tint: pwCloseHov.hovered ? Theme.ember : Theme.faint
                                        Behavior on tint { ColorAnimation { duration: Theme.quick } }
                                    }
                                    HoverHandler { id: pwCloseHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: WifiLink.expandedSsid = "" }
                                }

                                Spinner {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: WifiLink.connecting
                                    size: 14
                                    tint: Theme.ember
                                }

                                HubButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "Connect"
                                    primary: true
                                    enabled: !WifiLink.connecting && pwField.text.length > 0
                                    onClicked: WifiLink.connectWithPassword(netItem.ssid, pwField.text)
                                }
                            }
                        }

                        Text {
                            readonly property bool show: netItem.expanded && WifiLink.connectFailed
                            visible: height > 0.5
                            height: show ? implicitHeight : 0
                            opacity: show ? 1 : 0
                            clip: true
                            Behavior on height { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }
                            Behavior on opacity { NumberAnimation { duration: Theme.quick } }
                            text: "Connection failed."
                            color: Theme.bad
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            leftPadding: 16
                        }
                    }
                }
            }
        }
    }
}
