pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Singletons"

// Hotspot subtab of Connections: brings the persistent `RyokuHotspot`
// NetworkManager profile up/down through nmcli, with an editable SSID + WPA2
// password. state and credentials read straight from NM on entry, so the page
// always reflects what the system thinks.
//
// the nmcli wire protocol, state, and apply/stop/edit flow all live in the
// shared WifiLink singleton (see ryoku/shared/quickshell/WifiLink.qml) --
// identical to the pill's LinkWifi hotspot block, so this page and that
// drill-in agree on them instead of racing separate copies. only the layout
// here is recast for the full hub content area + warm Theme.
Item {
    id: page

    Component.onCompleted: WifiLink.refreshHotspot()

    // --- header explainer --------------------------------------------------
    Column {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 6

        Text {
            text: "Share this machine's connection as a Wi-Fi hotspot. NetworkManager owns the profile (named " + WifiLink.hsCon + "); changes to the network name or password apply at once when the hotspot is live."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
            width: Math.min(parent.width, 640)
            wrapMode: Text.WordWrap
        }
    }

    // --- form column -------------------------------------------------------
    Column {
        id: form
        anchors.left: parent.left
        anchors.top: head.bottom
        anchors.topMargin: 28
        width: Math.min(parent.width, 600)
        spacing: 30

        // -- big toggle card: icon, label, live status, switch -------------
        Rectangle {
            width: parent.width
            height: 76
            radius: Theme.radius
            color: WifiLink.hsActive ? Theme.frameBg : Theme.surfaceLo
            border.width: 1
            border.color: WifiLink.hsActive ? Theme.ember : Theme.line
            Behavior on color { ColorAnimation { duration: Theme.quick } }
            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

            Icon {
                id: hsGlyph
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                name: "wifi"
                size: 22
                weight: 1.8
                tint: WifiLink.hsActive ? Theme.ember : Theme.subtle
                Behavior on tint { ColorAnimation { duration: Theme.quick } }
            }

            Column {
                anchors.left: hsGlyph.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "Hotspot"
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Text {
                    text: WifiLink.hsBusy ? "Working\u2026"
                        : (WifiLink.hsActive ? ("Active on " + WifiLink.hsIface) : "Off")
                    color: WifiLink.hsActive ? Theme.ember : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                }
            }

            ToggleRow {
                id: hsSwitch
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                checked: WifiLink.hsActive
                enabled: !WifiLink.hsBusy
                highlightId: "hotspot_toggle"
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

        // -- credentials ---------------------------------------------------
        SettingSection {
            width: parent.width
            title: "DETAILS"

            // editable label/value row. tap the value to drop an inline
            // TextField in its place; Enter commits via commitHotspotEdit, Esc
            // (loss of focus) cancels.
            component CredRow: Item {
                id: cr
                property string field: ""
                property string label: ""
                property string value: ""
                property string placeholder: ""
                property bool secret: false
                property bool reveal: false
                // shared with a searchIndex.js entry's `highlight` field --
                // see HighlightFlash.qml.
                property string highlightId: ""
                readonly property bool editing: WifiLink.hsEdit === cr.field
                readonly property bool tooShort: cr.field === "pw" && cr.editing && WifiLink.hsDraft.length > 0 && WifiLink.hsDraft.length < 8

                width: parent ? parent.width : 0
                height: 44

                HighlightFlash { target: cr; highlightId: cr.highlightId }

                // hairline background, lights up while editing.
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: cr.editing ? Theme.surfaceLo : "transparent"
                    border.width: 1
                    border.color: cr.editing ? Theme.ember : Theme.lineSoft
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }
                }

                Text {
                    id: crLabel
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: cr.label
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                // read-only value + tap-to-edit affordance.
                Item {
                    visible: !cr.editing
                    anchors.left: crLabel.right
                    anchors.right: (cr.secret && cr.value.length > 0) ? revealBtn.left : parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height

                    Text {
                        id: crValue
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool isSecretHidden: cr.secret && !cr.reveal && cr.value.length > 0
                        text: cr.value.length === 0
                            ? (cr.placeholder.length ? cr.placeholder : "tap to set")
                            : (isSecretHidden ? "\u2022".repeat(Math.max(cr.value.length, 8)) : cr.value)
                        color: cr.value.length === 0
                            ? Theme.faint
                            : (cr.secret ? Theme.ember : Theme.bright)
                        font.family: cr.secret ? Theme.mono : Theme.font
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        font.features: ({ "tnum": 1 })
                        elide: Text.ElideLeft
                        maximumLineCount: 1
                    }

                    HoverHandler {
                        id: valueHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: {
                            WifiLink.hsDraft = cr.value;
                            WifiLink.hsEdit = cr.field;
                            Qt.callLater(crField.forceActiveFocus);
                        }
                    }
                }

                // "Show" / "Hide" pill, password row only.
                Rectangle {
                    id: revealBtn
                    visible: cr.secret && !cr.editing && cr.value.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: revealText.implicitWidth + 18
                    height: 24
                    radius: Theme.radius
                    color: revealHov.hovered ? Theme.surface : "transparent"
                    border.width: 1
                    border.color: revealHov.hovered ? Theme.ember : Theme.line
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                    Text {
                        id: revealText
                        anchors.centerIn: parent
                        text: cr.reveal ? "Hide" : "Show"
                        color: revealHov.hovered ? Theme.bright : Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    HoverHandler { id: revealHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: cr.reveal = !cr.reveal }
                }

                // inline editor.
                TextField {
                    id: crField
                    visible: cr.editing
                    anchors.left: crLabel.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: TextInput.AlignRight
                    background: null
                    padding: 0
                    color: Theme.bright
                    font.family: cr.secret ? Theme.mono : Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    placeholderText: cr.field === "pw" ? "8+ characters" : "Network name"
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.ember
                    selectedTextColor: Theme.onAccent
                    text: cr.editing ? WifiLink.hsDraft : ""
                    onTextEdited: WifiLink.hsDraft = text
                    onAccepted: WifiLink.commitHotspotEdit()
                    onActiveFocusChanged: {
                        if (!activeFocus && cr.editing)
                            WifiLink.commitHotspotEdit();
                    }
                    Keys.onEscapePressed: (event) => {
                        WifiLink.hsEdit = "";
                        WifiLink.hsDraft = "";
                        event.accepted = true;
                    }
                }

                // inline validation: password row only, only while typing too
                // few characters. real rejection happens in commitHotspotEdit;
                // this is just the heads-up.
                Text {
                    visible: cr.tooShort
                    anchors.left: crLabel.right
                    anchors.leftMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    text: "WPA2 needs at least 8 characters"
                    color: Theme.bad
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }
            }

            CredRow {
                field: "name"
                label: "Network name"
                value: WifiLink.hsName
                placeholder: "Ryoku"
                highlightId: "hotspot_name"
            }

            CredRow {
                field: "pw"
                label: "Password"
                value: WifiLink.hsPw
                placeholder: "Tap to set"
                secret: true
                highlightId: "hotspot_password"
            }
        }
    }
}
