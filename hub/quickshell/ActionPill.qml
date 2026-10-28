import QtQuick
import "Singletons"

// compact ghost pill for inline row actions (Install, Remove), smaller than the
// page-level HubButton. `danger` tints the hover toward fault red.
Item {
    id: pill

    property string label: ""
    property string icon: ""
    property bool danger: false
    signal clicked()

    readonly property color accent: danger ? Theme.bad : Theme.ember

    implicitWidth: row.implicitWidth + 22
    implicitHeight: 28

    scale: tap.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: hover.hovered ? Theme.keyTop : "transparent"
        border.width: 1
        border.color: hover.hovered ? pill.accent : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.quick } }
        Behavior on border.color { ColorAnimation { duration: Theme.quick } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Icon {
            visible: pill.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: pill.icon
            size: 13
            weight: 1.8
            tint: hover.hovered ? pill.accent : Theme.cream
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            color: hover.hovered ? Theme.bright : Theme.cream
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: pill.clicked() }
}
