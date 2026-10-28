import QtQuick
import "Singletons"

// one switch row in a deck mode panel: the option's name and a line on what it
// costs or changes, with the switch on the right. the text is tappable too, but
// sits beside the switch, never under it, so a tap can't land on both.
Item {
    id: root

    property real s: 1
    property string label: ""
    property string hint: ""
    property bool checked: false
    signal toggled()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(col.implicitHeight, sw.height)

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: sw.left
        anchors.rightMargin: 12 * root.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2 * root.s

        Text {
            width: parent.width
            text: root.label
            wrapMode: Text.WordWrap
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11.5 * root.s
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: root.hint
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * root.s
        }

        TapHandler { onTapped: root.toggled() }
    }

    LinkToggle {
        id: sw
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        s: root.s
        on: root.checked
        onToggled: root.toggled()
    }
}
