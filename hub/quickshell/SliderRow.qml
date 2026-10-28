import QtQuick
import "Singletons"

// coarse "feel" control: label, slider, readout. for values tuned by eye over a
// range (opacity, shadow strength, melt) where the exact number matters less
// than what it looks like. modified(value) fires live as the knob moves.
Item {
    id: root

    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0.01
    property int decimals: 2
    property bool percent: false
    // shared with a searchIndex.js entry's `highlight` field -- see
    // HighlightFlash.qml.
    property string highlightId: ""

    signal modified(real value)

    implicitWidth: 320
    implicitHeight: 38

    HighlightFlash { target: root; highlightId: root.highlightId }

    readonly property string readout: root.percent
        ? Math.round(root.value * 100) + "%"
        : root.value.toFixed(root.decimals)

    Text {
        id: lbl
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 116
        elide: Text.ElideRight
        text: root.label
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 14
        font.weight: Font.Medium
    }

    Text {
        id: val
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 42
        horizontalAlignment: Text.AlignRight
        text: root.readout
        color: Theme.bright
        font.family: Theme.mono
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Slider {
        anchors.left: lbl.right
        anchors.right: val.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        from: root.from
        to: root.to
        step: root.step
        value: root.value
        onMoved: (v) => root.modified(v)
    }
}
