import QtQuick
import "Singletons"

// The website's brutalist card: a SHARP-cornered surface with a hairline border
// and a hard offset shadow (a solid black rectangle pushed down-right, no blur).
// Depth from the offset, not a soft glow. Put content inside; it fills the face.
Item {
    id: panel

    property color surface: Theme.bgTop
    property color line: Theme.lineStrong
    property int step: Theme.shadowStepLg     // offset distance
    property color shadowColor: Theme.shadow
    property real borderWidth: Theme.border
    default property alias content: face.data

    // reserve room for the offset so the shadow isn't clipped by a parent
    implicitWidth: 200 + step
    implicitHeight: 120 + step

    // hard offset shadow
    Rectangle {
        x: panel.step
        y: panel.step
        width: face.width
        height: face.height
        color: panel.shadowColor
        antialiasing: false
    }

    // the sharp bordered face
    Rectangle {
        id: face
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: panel.step
        anchors.bottomMargin: panel.step
        color: panel.surface
        radius: 0
        border.width: panel.borderWidth
        border.color: panel.line
        antialiasing: false
    }
}
