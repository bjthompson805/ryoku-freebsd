pragma ComponentBehavior: Bound
import QtQuick
import "."

// NumberField + a search "jump to me" highlight, for the WidgetsPage fields
// searchIndex.js can deep-link to. A thin subtype rather than baking
// HighlightFlash into the shared NumberField.qml itself: NumberField is
// symlinked into ryovm too, which has no HighlightFlash.qml/HubHighlight
// singleton to resolve it against. Kept Hub-only, alongside HighlightFlash
// itself.
NumberField {
    id: root
    // shared with a searchIndex.js entry's `highlight` field -- see
    // HighlightFlash.qml.
    property string highlightId: ""
    HighlightFlash { target: root; highlightId: root.highlightId }
}
