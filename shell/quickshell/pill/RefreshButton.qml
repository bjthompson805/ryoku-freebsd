import QtQuick
import "Singletons"

// a manual "do it now" glyph button: lights up on hover and spins while its
// action is in flight. sized to sit pinned top-right of a popout header.
Item {
    id: root

    property real s: 1
    property bool spinning: false

    signal clicked()

    width: 18 * s
    height: 18 * s

    MaterialIcon {
        anchors.centerIn: parent
        text: "refresh"
        fill: 1
        color: area.containsMouse ? Theme.cream : Theme.subtle
        font.pixelSize: 14 * root.s

        RotationAnimation on rotation {
            running: root.spinning
            from: 0
            to: 360
            duration: 700
            loops: Animation.Infinite
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
