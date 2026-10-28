pragma ComponentBehavior: Bound
import QtQuick
import "."

// NumberField + a search "jump to me" highlight, for the WidgetsPage fields
// searchIndex.js can deep-link to.
NumberField {
    id: root
    // shared with a searchIndex.js entry's `highlight` field -- see
    // HighlightFlash.qml.
    property string highlightId: ""
    HighlightFlash { target: root; highlightId: root.highlightId }
}
