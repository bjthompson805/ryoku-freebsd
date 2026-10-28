import QtQuick
import "Singletons"

// nav row = icon + label, colour follows state. the rail draws ONE sliding
// selector for the fill/bar, not one per button, so it reads as one moving
// accent instead of three boxed chips.
Item {
    id: btn

    property string label: ""
    property string icon: ""
    property bool soon: false
    property int badge: 0
    property bool selected: false
    signal clicked()

    implicitHeight: 44

    // hover highlight, aligned with the rail's selection pill. hidden on the
    // selected row (the slider already marks it). faint preview of where a
    // click would land.
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        radius: Theme.radius
        color: Theme.keyTop
        opacity: (hover.hovered && !btn.selected) ? 0.45 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 28
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: btn.icon
            size: 18
            tint: btn.selected ? Theme.ember : (hover.hovered ? Theme.cream : Theme.dim)
            Behavior on tint { ColorAnimation { duration: Theme.quick } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            color: btn.selected ? Theme.bright : (hover.hovered ? Theme.cream : Theme.subtle)
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: btn.selected ? Font.DemiBold : Font.Medium
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }
    }

    Text {
        visible: btn.soon
        anchors.right: parent.right
        anchors.rightMargin: 26
        anchors.verticalCenter: parent.verticalCenter
        text: "SOON"
        color: Theme.faint
        font.family: Theme.mono
        font.pixelSize: 9
        font.weight: Font.DemiBold
        font.letterSpacing: 1.5
    }

    Rectangle {
        visible: btn.badge > 0
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(18, bdg.implicitWidth + 12)
        height: 18
        radius: 9
        color: Theme.ember

        Text {
            id: bdg
            anchors.centerIn: parent
            text: "" + btn.badge
            color: Theme.onAccent
            font.family: Theme.font
            font.pixelSize: 10
            font.weight: Font.Bold
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: btn.clicked() }
}
