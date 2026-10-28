import QtQuick
import "Singletons"

// keycap: flat warm tile, darker bottom lip for a hint of mechanical depth,
// glyph in JetBrains Mono. no gradient, no glassy sheen.
Rectangle {
    id: cap

    property string text: ""

    radius: Theme.radius
    implicitHeight: 25
    implicitWidth: Math.max(25, label.implicitWidth + 16)
    color: Theme.keyTop
    border.width: 1
    border.color: Theme.line

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 3
        radius: Theme.radius
        color: Theme.keyBot
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: cap.text
        color: Theme.cream
        font.family: Theme.mono
        font.pixelSize: 11
        font.weight: Font.Medium
    }
}
