import QtQuick
import "Singletons"

// one live-activity chip = accent label + optional value/dot. status by
// default. `clickable` makes it an entry point (stash chip opens its surface
// this way). width collapses to 0 when `active` is false -> the strip folds
// shut around whatever's actually live.
Item {
    id: root

    property real s: 1
    property bool active: true
    property string label: ""
    property string value: ""
    property color accent: Theme.dim
    property bool dot: false
    property real dotOpacity: 1
    property bool clickable: false

    signal activated()

    readonly property bool lit: clickable && area.containsMouse

    width: active ? chipRow.implicitWidth + 14 * s : 0
    height: 22 * s
    opacity: active ? 1 : 0
    visible: opacity > 0.01
    scale: active ? 1 : 0.8

    Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.lit ? Theme.frameBg : Theme.tileBg
        border.width: 1
        border.color: Qt.alpha(root.accent, root.lit ? 0.55 : 0.28)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    }

    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5 * root.s

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.dot
            width: 7 * root.s
            height: 7 * root.s
            // dot squares off into a stop icon on hover so it reads as a
            // clickable control that ends the recording.
            radius: root.lit ? 1.5 * root.s : width / 2
            color: root.accent
            opacity: root.lit ? 1 : root.dotOpacity
            Behavior on radius { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root.accent
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Bold
            font.letterSpacing: 0.8 * root.s
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.value.length > 0
            text: root.value
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -3 * root.s
        enabled: root.clickable && root.active
        hoverEnabled: root.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
