pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Singletons"

// wifi drill-in for the link surface. back chevron, enable toggle, live
// network list sorted by signal. nmcli is ground truth for security and
// known-profile state; clicking a secured-unknown network drops an inline
// password row that pipes through `nmcli dev wifi connect`. background comes
// from the pill body, so we draw none. all of that state and the connect/
// hotspot flows live in the shared WifiLink singleton (see
// ryoku/shared/quickshell/WifiLink.qml) so this drill-in and the Hub's Wi-Fi
// + Hotspot tabs agree on them instead of racing separate copies.
Item {
    id: root

    property real s: 1
    property bool active: false
    property bool compact: false

    signal back()

    implicitHeight: compact ? (listFrame.y + listFrame.height) : (hsBlock.y + hsBlock.height)

    onActiveChanged: {
        WifiLink.setScannerActive(active);
        if (active) {
            WifiLink.refresh();
            WifiLink.refreshHotspot();
        }
    }

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
                anchors.verticalCenter: parent.verticalCenter
                width: 17 * root.s
                height: 17 * root.s
                visible: !root.compact

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
                anchors.verticalCenter: parent.verticalCenter
                text: "WIFI"
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
            spacing: 12 * root.s

            Item {
                anchors.verticalCenter: parent.verticalCenter
                visible: WifiLink.wifiOn
                width: 16 * root.s
                height: 16 * root.s

                GlyphIcon {
                    id: reloadGlyph
                    anchors.fill: parent
                    name: "reboot"
                    color: WifiLink.scanning ? Theme.flameGlow : (reloadArea.containsMouse ? Theme.cream : Theme.iconDim)
                    stroke: 1.8

                    RotationAnimator {
                        target: reloadGlyph
                        running: WifiLink.scanning
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) reloadGlyph.rotation = 0
                    }
                }

                MouseArea {
                    id: reloadArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: WifiLink.scanning ? WifiLink.stopScan() : WifiLink.startScan()
                }
            }

            LinkToggle {
                s: root.s
                anchors.verticalCenter: parent.verticalCenter
                on: WifiLink.wifiOn
                onToggled: WifiLink.setWifiEnabled(!WifiLink.wifiOn)
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
        height: WifiLink.wifiOn ? Math.min(Math.max(netCol.implicitHeight, 26 * root.s), 200 * root.s) : 0

        Text {
            anchors.centerIn: parent
            visible: WifiLink.wifiOn && WifiLink.nets.length === 0
            text: "Searching networks…"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
        }

        Flickable {
            id: netFlick
            anchors.fill: parent
            contentHeight: netCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: netCol
                width: netFlick.width
                spacing: 2 * root.s

                Repeater {
                    model: WifiLink.netsSorted

                    Column {
                        id: netItem
                        required property var modelData
                        readonly property string ssid: (modelData && modelData.name) ? modelData.name : ""
                        readonly property bool isActive: modelData ? modelData.connected === true : false
                        readonly property bool secured: WifiLink.isSecured(ssid)
                        readonly property bool expanded: ssid.length > 0 && WifiLink.expandedSsid === ssid
                        width: netCol.width
                        spacing: 2 * root.s

                        function syncPwField() {
                            pwField.text = WifiLink.pwDraft;
                            pwField.cursorPosition = pwField.text.length;
                            pwField.forceActiveFocus();
                        }

                        onExpandedChanged: if (expanded) Qt.callLater(syncPwField)
                        Component.onCompleted: if (expanded) Qt.callLater(syncPwField)

                        Rectangle {
                            width: parent.width
                            height: 30 * root.s
                            radius: Theme.radius
                            color: netItem.isActive ? Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.14)
                                : (rowHover.hovered ? Theme.frameBg : "transparent")

                            HoverHandler { id: rowHover }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: WifiLink.activateNetwork(netItem.modelData)
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10 * root.s
                                anchors.right: rowRight.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: netItem.ssid.length ? netItem.ssid : "Hidden"
                                color: netItem.isActive ? Theme.vermLit : Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                font.weight: netItem.isActive ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }

                            Row {
                                id: rowRight
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 7 * root.s

                                GlyphIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: netItem.secured
                                    width: 11 * root.s
                                    height: 11 * root.s
                                    name: "lock-round"
                                    color: Theme.iconDim
                                    stroke: 1.8
                                }

                                WifiGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 15 * root.s
                                    height: 15 * root.s
                                    s: root.s
                                    on: true
                                    level: (netItem.modelData && netItem.modelData.signalStrength) || 0
                                }
                            }
                        }

                        Item {
                            visible: netItem.expanded
                            width: parent.width
                            height: 30 * root.s

                            TextField {
                                id: pwField
                                anchors.left: parent.left
                                anchors.leftMargin: 10 * root.s
                                anchors.right: pwRight.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                background: null
                                padding: 0
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                echoMode: TextInput.Password
                                placeholderText: "Password"
                                placeholderTextColor: Theme.faint
                                selectByMouse: true
                                selectionColor: Theme.verm
                                onTextEdited: WifiLink.pwDraft = text
                                onAccepted: WifiLink.connectWithPassword(netItem.ssid, text)
                            }

                            Row {
                                id: pwRight
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 7 * root.s

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: WifiLink.connecting && netItem.expanded
                                    width: 4 * root.s
                                    height: 4 * root.s
                                    radius: width / 2
                                    color: Theme.flameGlow

                                    SequentialAnimation on opacity {
                                        running: WifiLink.connecting && netItem.expanded
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 1; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1; to: 0.35; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "↵"
                                    color: enterArea.containsMouse ? Theme.cream : Theme.vermLit
                                    font.family: Theme.font
                                    font.pixelSize: 12 * root.s

                                    MouseArea {
                                        id: enterArea
                                        anchors.fill: parent
                                        anchors.margins: -6 * root.s
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WifiLink.connectWithPassword(netItem.ssid, pwField.text)
                                    }
                                }
                            }
                        }

                        Text {
                            visible: netItem.expanded && WifiLink.connectFailed
                            text: "Connection failed"
                            color: Theme.vermLit
                            font.family: Theme.font
                            font.pixelSize: 9.5 * root.s
                            leftPadding: 10 * root.s
                        }
                    }
                }
            }
        }

        WheelScroller {
            anchors.fill: parent
            s: root.s
            flick: netFlick
        }
    }

    Item {
        id: hsBlock
        anchors.top: listFrame.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        visible: WifiLink.wifiOn && !root.compact
        height: WifiLink.wifiOn ? hsCol.implicitHeight + 9 * root.s : 0
        clip: true

        Rectangle {
            id: hsDivider
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.hair
        }

        Column {
            id: hsCol
            anchors.top: hsDivider.bottom
            anchors.topMargin: 9 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 6 * root.s

            component CredRow: Item {
                id: cr
                property string field: ""
                property string label: ""
                property string value: ""
                property bool secret: false
                readonly property bool editing: WifiLink.hsEdit === cr.field
                width: parent ? parent.width : 0
                height: 22 * root.s

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: cr.label
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1 * root.s
                }

                Text {
                    visible: !cr.editing
                    anchors.right: parent.right
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: cr.value.length ? cr.value : "tap to set"
                    color: cr.value.length ? (cr.secret ? Theme.flameCore : Theme.cream) : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6 * root.s
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            WifiLink.hsDraft = cr.value;
                            WifiLink.hsEdit = cr.field;
                            Qt.callLater(crField.forceActiveFocus);
                        }
                    }
                }

                TextField {
                    id: crField
                    visible: cr.editing
                    anchors.right: parent.right
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 150 * root.s
                    horizontalAlignment: TextInput.AlignRight
                    background: null
                    padding: 0
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    placeholderText: cr.field === "pw" ? "8+ characters" : "Name"
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.verm
                    text: cr.editing ? WifiLink.hsDraft : ""
                    onTextEdited: WifiLink.hsDraft = text
                    onAccepted: WifiLink.commitHotspotEdit()
                }
            }

            Rectangle {
                width: parent.width
                height: 34 * root.s
                radius: Theme.radius
                color: WifiLink.hsActive ? Theme.frameBg : "transparent"

                GlyphIcon {
                    id: hsGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * root.s
                    height: 17 * root.s
                    name: "hotspot"
                    color: WifiLink.hsActive ? Theme.flameGlow : Theme.iconDim
                    stroke: 1.7
                }

                Column {
                    anchors.left: hsGlyph.right
                    anchors.leftMargin: 11 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1 * root.s

                    Text {
                        text: "Hotspot"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: WifiLink.hsBusy ? "…" : (WifiLink.hsActive ? "Active" : "Off")
                        color: WifiLink.hsActive ? Theme.flameGlow : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Medium
                    }
                }

                LinkToggle {
                    s: root.s
                    anchors.right: parent.right
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    on: WifiLink.hsActive
                    onToggled: {
                        if (WifiLink.hsActive) {
                            WifiLink.stopHotspot();
                        } else {
                            if (WifiLink.hsPw.length < 8)
                                WifiLink.hsPw = WifiLink.generatePw();
                            WifiLink.applyHotspot();
                        }
                    }
                }
            }

            CredRow {
                field: "name"
                label: "Network"
                value: WifiLink.hsName
            }

            CredRow {
                field: "pw"
                label: "Password"
                value: WifiLink.hsPw
                secret: true
            }
        }
    }
}
