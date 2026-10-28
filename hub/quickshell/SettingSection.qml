import QtQuick
import "Singletons"

// titled group: mono caps header + hairline, controls stacked below. how the hub
// breaks shell knobs into scannable groups instead of one long list.
Column {
    id: sec

    property string title: ""
    default property alias items: body.data
    property string description: ""
    // shared with a searchIndex.js entry's `highlight` field, or an "Open
    // <page>" cross-link's target id, so HubHighlight.trigger(id) can find
    // and flash this whole group -- see HighlightFlash.qml. Prefer wiring a
    // single row's own highlightId (ToggleRow/SliderRow/etc.) when one
    // specific control is the real target; use this for a group-level id
    // only when no single row is "the" setting.
    property string highlightId: ""

    spacing: 14

    HighlightFlash { target: sec; highlightId: sec.highlightId }

    Item {
        width: sec.width
        height: 16

        Text {
            id: head
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: sec.title
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 2
        }

        Rectangle {
            anchors.left: head.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Theme.lineSoft
        }
    }

    Text {
        width: sec.width
        visible: sec.description !== ""
        text: sec.description
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12
        lineHeight: 1.3
    }

    Column {
        id: body
        width: sec.width
        spacing: 16
    }
}
