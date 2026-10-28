pragma Singleton
import QtQuick
import Quickshell

// live dock state of the delos island, shared from the overlay (which owns the
// island) to the reserve window: they are separate layer-shell windows, so the
// window reserve reads this to follow the island's edge and thickness as it is
// dragged, hidden, or reoriented. in-memory only; the persisted seed is
// Config.islandEdge / islandAlong / islandHidden.
Singleton {
    id: root

    // delos is the live bar style (else the reserve keeps its plain-bar zone).
    property bool active: false
    // the edge the island is fused to: "top" | "bottom" | "left" | "right".
    property string edge: "top"
    // perpendicular extent at that edge, frame lip included: the reserve claims
    // exactly this so tiles tuck against the island wherever it sits.
    property real thickness: 0
    // centre along the docked edge in overlay coords, so a popout can grow from
    // the island's current spot; -1 falls back to the edge centre.
    property real along: -1
    // tucked to a nub: the reserve shrinks to the nub depth.
    property bool hidden: false
}
