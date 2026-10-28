import QtQuick
import "Singletons"

// Editorial kicker, the website's `.eyebrow`: a short vermillion tick, then a
// mono uppercase label, optionally led by a 力 mark. Sits above a Fraunces
// heading. One accent, wide tracking, quiet.
Row {
    id: eye

    property string text: ""
    property bool mark: true          // lead with the 力 seal glyph
    property color tick: Theme.sun
    property color labelColor: Theme.dim

    spacing: 10

    Rectangle {                        // the vermillion tick
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 1.5
        color: eye.tick
    }

    Text {
        visible: eye.mark
        anchors.verticalCenter: parent.verticalCenter
        text: "\u529b"                 // 力
        color: eye.tick
        font.family: Theme.fontJp
        font.pixelSize: 12
        font.weight: Font.Bold
        opacity: 0.9
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: eye.text
        color: eye.labelColor
        font.family: Theme.mono
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 3.2
        font.capitalization: Font.AllUppercase
    }
}
