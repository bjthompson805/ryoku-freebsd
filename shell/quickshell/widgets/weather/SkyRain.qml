pragma ComponentBehavior: Bound
import QtQuick

/**
 * Rain: a grey cloud over slanted streaks falling on one shared phase, spread
 * across the width by the golden ratio so they look random without any RNG (which
 * the Quickshell JS engine forbids). Clipped to the sky so streaks never spill out
 * of the widget.
 */
Item {
    id: sky

    property bool isDay: true
    property bool animate: true
    readonly property int n: 16
    clip: true

    property real phase: 0
    NumberAnimation on phase {
        running: sky.animate
        from: 0; to: 1; duration: 1100; loops: Animation.Infinite
    }

    Cloud {
        width: sky.width * 0.72
        height: sky.height * 0.4
        anchors.horizontalCenter: parent.horizontalCenter
        y: sky.height * 0.06
        tint: "#c4ccdf"
        solid: 0.95
    }

    Repeater {
        model: sky.n
        Rectangle {
            required property int index
            readonly property real fx: (index * 0.6180339) % 1
            readonly property real off: (index * 0.382) % 1
            readonly property real len: sky.height * 0.17
            readonly property real span: sky.height + len
            width: Math.max(2, sky.width * 0.007)
            height: len
            radius: width / 2
            antialiasing: true
            rotation: 14
            transformOrigin: Item.Center
            color: Qt.rgba(0.62, 0.76, 1, 0.82)
            x: sky.width * (0.06 + fx * 0.88)
            y: ((sky.phase + off) % 1) * span - len + sky.height * 0.28
        }
    }
}
