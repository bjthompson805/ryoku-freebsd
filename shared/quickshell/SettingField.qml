pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// labelled free-text field: label on the left, a CommitField box on the
// right (see CommitField.qml for the commit/checkmark behaviour), mirroring
// NumberField / Dropdown so it sits cleanly among the other setting rows.
Item {
    id: root

    property string label: ""
    property string value: ""
    property string placeholder: ""
    property real fieldWidth: 200
    // shared with a searchIndex.js entry's `highlight` field -- see
    // HighlightFlash.qml. Only meaningful under the Hub, the sole current
    // symlink consumer of this shared component; HighlightFlash.qml and its
    // HubHighlight singleton live in the Hub's own quickshell dir, resolved
    // the same implicit-sibling way CommitField already is below.
    property string highlightId: ""

    signal committed(string value)

    implicitWidth: 320
    implicitHeight: 38

    HighlightFlash { target: root; highlightId: root.highlightId }

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - box.width - 14
        elide: Text.ElideRight
        text: root.label
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 14
        font.weight: Font.Medium
    }

    CommitField {
        id: box
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.fieldWidth
        value: root.value
        placeholder: root.placeholder
        onCommitted: (t) => root.committed(t)
    }
}
