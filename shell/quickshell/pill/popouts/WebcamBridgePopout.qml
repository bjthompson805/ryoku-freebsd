pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../Singletons"

// webcam-bridge popout content: opened from BarStatus.qml's bridge icon,
// which only shows while ryoku-cmd-webcam-bridge is up. explains what the
// icon means (this isn't obvious the way "battery" or "network" are) and
// reports its live status straight from the Webcam singleton -- streaming
// right now vs. just standing by, the virtual device it publishes to, and
// the flip calibration applied (set in Ryoku Hub > Input > Camera). no
// on/off control here on purpose: the sidebar's Webcam quick toggle already
// owns that, this panel is read-only. plain transparent Item -- the Popout
// blob behind it IS the surface; this panel only reports its implicit size.
Item {
    id: root

    property real s: 1
    property bool open: false

    anchors.fill: parent

    implicitWidth: 280 * s
    implicitHeight: body.implicitHeight + 27 * s

    component InfoRow: Item {
        id: infoRow

        property string label: ""
        property string value: ""

        width: parent ? parent.width : 0
        height: rowLabel.implicitHeight

        Text {
            id: rowLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: infoRow.label
            color: Theme.subtle
            font.family: Theme.mono
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2 * root.s
        }
        Text {
            anchors.right: parent.right
            anchors.baseline: rowLabel.baseline
            text: infoRow.value
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.hair
    }

    Column {
        id: body
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 13 * root.s
        anchors.leftMargin: 16 * root.s
        anchors.rightMargin: 16 * root.s
        spacing: 11 * root.s

        Row {
            spacing: 8 * root.s
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "videocam"
                fill: Webcam.streaming ? 1 : 0
                color: Theme.bridgeGlow
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "WEBCAM BRIDGE"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "This camera has no plain USB/UVC device apps can open directly, so Ryoku relays it through a virtual camera instead. This icon only shows while that relay is running."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.Medium
        }

        Divider {}

        Column {
            width: parent.width
            spacing: 8 * root.s

            InfoRow {
                label: "Status"
                value: Webcam.streaming ? "Streaming" : "Idle (watching for opens)"
            }
            InfoRow {
                label: "Device"
                value: "/dev/video32"
            }
            InfoRow {
                label: "Flip"
                value: Webcam.flip180 ? "180°" : "None"
            }
        }

        Divider {}

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Turn the camera off from the sidebar's Webcam quick toggle. Flip calibration lives in Ryoku Hub → Input → Camera."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.Medium
        }
    }
}
