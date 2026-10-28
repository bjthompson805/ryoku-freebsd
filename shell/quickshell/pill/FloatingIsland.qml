pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Blobs
import "Singletons"

// Reusable base for a dockable floating island living in the frame blob field.
// Manages: lip geometry, dock-edge tracking, drag-to-free, frame-bump approach
// animation, edge merge effect, nub-reveal, and the two BlobRects (body + bump).
// The caller sets `bodyW`/`bodyH` to its content size, feeds `group`, and reads
// back `hudX/Y/W/H` + `trigX/Y/W/H` + `dragging` for the Wayland input mask.
//
// Content is NOT placed here -- the caller positions its own Item at (px, py).
// This item `anchors.fill: parent` inside the overlay, matching RecordHud.
//
//   FloatingIsland {
//       id: island
//       group: blobGroup
//       s: overlay.s
//       barEdge: overlay.barPos
//       barBand: overlay.barBand
//       bodyW: content.implicitWidth + 20
//       bodyH: content.implicitHeight + 14
//       live: someCondition
//   }
Item {
    id: island

    required property var group
    property real s: 1
    property real radius: 17 * s
    property real smoothing: 30
    // bar thickens one edge -- that edge's lip is deeper.
    property string barEdge: ""
    property real barBand: 0

    // content box the caller drives.
    property real bodyW: 0
    property real bodyH: 0

    // drag handle rect (relative to px,py) -- cursor + actual drag only apply
    // here, not the whole body, so hovering content elsewhere doesn't show a
    // move cursor or start a drag. Defaults to a small top-left corner
    // matching most callers' grip icon placement; override for a grip that
    // moves (e.g. DelosIsland's, which reflows with orientation).
    property real handleX: 0
    property real handleY: 0
    property real handleW: 24 * s
    property real handleH: 24 * s
    // set false to remove the blob from the shared field (island is gone).
    property bool live: true

    readonly property int moveDur: 560
    readonly property int meltDur: 620
    readonly property int mergeDur: 1700

    anchors.fill: parent

    // --- lip geometry ---------------------------------------------------------
    readonly property real baseLip: Math.max(0, Config.frameBorder - 50)
    function lipFor(e) { return island.baseLip + (e === island.barEdge ? island.barBand : 0); }
    readonly property real lipT: island.lipFor("top")
    readonly property real lipB: island.lipFor("bottom")
    readonly property real lipL: island.lipFor("left")
    readonly property real lipR: island.lipFor("right")

    // --- dock state -----------------------------------------------------------
    property string dockEdge: "bottom"
    property real alongPx: 0
    property bool placed: false
    readonly property bool dragging: dragH.active
    property bool hidden: false

    onWidthChanged: island.reposition()
    onHeightChanged: island.reposition()
    // Default seed: centred on the bottom edge. Override by setting dockEdge /
    // alongPx before `placed` goes true, or from Config in the subtype.
    function reposition() {
        if (island.placed || island.width <= 0)
            return;
        island.alongPx = (island.width - island.bodyW) / 2;
        island.px = island.dockX;
        island.py = island.dockY;
        island.placed = true;
    }

    // --- reveal / melt (0 = in border, 1 = fully out) ------------------------
    property real prog: 0
    Behavior on prog { NumberAnimation { duration: island.meltDur; easing.type: Easing.InOutCubic } }
    readonly property bool nubRevealed: bodyHov.hovered || edgeHov.hovered

    // --- orientation (vertical when a side edge is nearest while dragging) ---
    readonly property real orientThreshold: 220 * island.s
    readonly property real orientRefW: 210 * island.s
    readonly property real orientGap: island.nearEdge === "left"  ? (island.px - island.lipL)
                                    : (island.width - island.lipR) - (island.px + island.orientRefW)
    // subtypes may override `vertical` via a Binding (e.g. DelosIsland keeps the
    // current orientation while dragging to avoid layout flips mid-grab).
    property bool vertical: island.dragging
        ? ((island.nearEdge === "left" || island.nearEdge === "right") && island.orientGap < island.orientThreshold)
        : (island.dockEdge === "left" || island.dockEdge === "right")

    property bool layoutVertical: false
    property real reorientFade: 1
    Behavior on reorientFade { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    onVerticalChanged: island.reorientFade = (island.layoutVertical === island.vertical) ? 1 : 0
    onReorientFadeChanged: {
        if (island.reorientFade <= 0.02 && island.layoutVertical !== island.vertical) {
            island.layoutVertical = island.vertical;
            island.reorientFade = 1;
        }
    }
    Component.onCompleted: island.layoutVertical = island.vertical

    // --- dock position --------------------------------------------------------
    readonly property real dockX: island.dockEdge === "left"   ? island.lipL
                                : island.dockEdge === "right"  ? (island.width - island.lipR - island.bodyW)
                                : Math.max(island.lipL, Math.min(island.width - island.lipR - island.bodyW, island.alongPx))
    readonly property real dockY: island.dockEdge === "top"    ? island.lipT
                                : island.dockEdge === "bottom" ? (island.height - island.lipB - island.bodyH)
                                : Math.max(island.lipT, Math.min(island.height - island.lipB - island.bodyH, island.alongPx))

    property real px: 0
    property real py: 0
    Behavior on px { enabled: !island.dragging; NumberAnimation { duration: island.mergeDur; easing.type: Easing.InOutCubic } }
    Behavior on py { enabled: !island.dragging; NumberAnimation { duration: island.mergeDur; easing.type: Easing.InOutCubic } }
    // idle/docked: px,py track the dock and animate toward it.
    Binding { target: island; property: "px"; value: island.dockX; when: !island.dragging; restoreMode: Binding.RestoreNone }
    Binding { target: island; property: "py"; value: island.dockY; when: !island.dragging; restoreMode: Binding.RestoreNone }
    onPxChanged: island.settleEdge()
    onPyChanged: island.settleEdge()

    // --- input-mask rects exposed to shell.qml --------------------------------
    readonly property real hudX: island.px
    readonly property real hudY: island.py
    readonly property real hudW: island.bodyW
    readonly property real hudH: island.bodyH
    // reveal trigger: wider/deeper while tucked so a flick to the edge pops it.
    readonly property bool tucked: island.hidden && !island.nubRevealed
    readonly property real trigReach: island.tucked ? 46 * island.s : 18 * island.s
    readonly property real trigPad:   island.tucked ? 44 * island.s : 0
    readonly property real trigDepth: island.lipFor(island.dockEdge) + island.trigReach
    readonly property real trigX: island.dockEdge === "right"  ? (island.width  - island.trigDepth)
                                : island.dockEdge === "left"   ? 0
                                : (island.dockX - island.trigPad)
    readonly property real trigY: island.dockEdge === "bottom" ? (island.height - island.trigDepth)
                                : island.dockEdge === "top"    ? 0
                                : (island.dockY - island.trigPad)
    readonly property real trigW: (island.dockEdge === "left" || island.dockEdge === "right") ? island.trigDepth : (island.bodyW + 2 * island.trigPad)
    readonly property real trigH: (island.dockEdge === "top"  || island.dockEdge === "bottom") ? island.trigDepth : (island.bodyH + 2 * island.trigPad)

    // --- edge proximity / approach (for frame-bump merge) --------------------
    readonly property real gapT: island.py - island.lipT
    readonly property real gapB: (island.height - island.lipB) - (island.py + island.bodyH)
    readonly property real gapL: island.px - island.lipL
    readonly property real gapR: (island.width  - island.lipR) - (island.px + island.bodyW)
    function gapOf(e) { return e === "top" ? island.gapT : e === "bottom" ? island.gapB : e === "left" ? island.gapL : island.gapR; }
    readonly property string rawNearEdge: {
        var m = Math.min(island.gapT, island.gapB, island.gapL, island.gapR);
        return m === island.gapT ? "top" : m === island.gapB ? "bottom" : m === island.gapL ? "left" : "right";
    }
    property string nearEdge: "bottom"
    // hysteresis: keep the current edge until another is clearly closer.
    function settleEdge() {
        if (island.rawNearEdge === island.nearEdge)
            return;
        if (island.gapOf(island.rawNearEdge) < island.gapOf(island.nearEdge) - 30 * island.s)
            island.nearEdge = island.rawNearEdge;
    }
    readonly property real nearGap:    Math.max(0, island.gapOf(island.nearEdge))
    readonly property real nearLip:    island.lipFor(island.nearEdge)
    readonly property real threshold:  90 * island.s
    readonly property real approach:   Math.max(0, Math.min(1, 1 - island.nearGap / island.threshold))
    readonly property real pull:       island.approach * island.approach
    // both surfaces reach for each other: island covers half the gap, frame bump the other.
    readonly property real islandReach: (island.nearGap / 2 + island.nearLip + island.smoothing) * island.pull
    readonly property real bumpReach:   (island.nearGap / 2 + island.smoothing) * island.pull
    readonly property real extT: island.nearEdge === "top"    ? island.islandReach : 0
    readonly property real extB: island.nearEdge === "bottom" ? island.islandReach : 0
    readonly property real extL: island.nearEdge === "left"   ? island.islandReach : 0
    readonly property real extR: island.nearEdge === "right"  ? island.islandReach : 0

    // --- face rect (visible during melt/reveal from docked edge) -------------
    readonly property bool vDock: island.dockEdge === "left" || island.dockEdge === "right"
    readonly property real faceW: island.vDock ? island.bodyW * island.prog : island.bodyW
    readonly property real faceH: island.vDock ? island.bodyH : island.bodyH * island.prog
    readonly property real faceX: island.dockEdge === "right"  ? (island.px + island.bodyW - island.faceW) : island.px
    readonly property real faceY: island.dockEdge === "bottom" ? (island.py + island.bodyH - island.faceH) : island.py

    // --- frame bump geometry -------------------------------------------------
    readonly property bool bumpVert: island.nearEdge === "top" || island.nearEdge === "bottom"
    readonly property real bumpLen:  island.bumpReach + island.nearLip + island.smoothing
    readonly property real bumpX:    island.nearEdge === "right"  ? (island.width  - island.lipR - island.bumpReach)
                                   : island.nearEdge === "left"   ? -island.smoothing
                                   : island.px
    readonly property real bumpY:    island.nearEdge === "bottom" ? (island.height - island.lipB - island.bumpReach)
                                   : island.nearEdge === "top"    ? -island.smoothing
                                   : island.py

    // --- blob rects -----------------------------------------------------------
    BlobRect {
        id: bodyBlob
        group: island.live ? island.group : null
        stiffness: 110
        damping: 15
        deformScale: 0.00003
        x: island.faceX - island.extL
        y: island.faceY - island.extT
        implicitWidth:  island.faceW + island.extL + island.extR
        implicitHeight: island.faceH + island.extT + island.extB
        topLeftRadius:     (island.extT > 0 || island.extL > 0) ? 0 : island.radius
        topRightRadius:    (island.extT > 0 || island.extR > 0) ? 0 : island.radius
        bottomLeftRadius:  (island.extB > 0 || island.extL > 0) ? 0 : island.radius
        bottomRightRadius: (island.extB > 0 || island.extR > 0) ? 0 : island.radius
    }

    BlobRect {
        id: frameBump
        group: (island.live && island.nearGap > 2 && island.bumpReach > 0.5) ? island.group : null
        stiffness: 110
        damping: 15
        deformScale: 0.00003
        x: island.bumpX
        y: island.bumpY
        implicitWidth:  island.bumpVert ? island.bodyW : island.bumpLen
        implicitHeight: island.bumpVert ? island.bumpLen : island.bodyH
        topLeftRadius:     (island.nearEdge === "top"    || island.nearEdge === "left")   ? 0 : island.radius
        topRightRadius:    (island.nearEdge === "top"    || island.nearEdge === "right")  ? 0 : island.radius
        bottomLeftRadius:  (island.nearEdge === "bottom" || island.nearEdge === "left")   ? 0 : island.radius
        bottomRightRadius: (island.nearEdge === "bottom" || island.nearEdge === "right")  ? 0 : island.radius
    }

    // deformMatrix for callers that want content to flex with the blob.
    readonly property alias deformMatrix: bodyBlob.deformMatrix

    // edge hover strip: keeps a hidden nub pop-able by hovering the frame edge.
    Item {
        x: island.trigX
        y: island.trigY
        width: island.trigW
        height: island.trigH
        HoverHandler { id: edgeHov }
    }

    // body hover: used by RecordHud/DelosIsland to hold revealHeld open.
    // Exposed so the caller can chain its own logic onto bodyHov.hovered.
    // No cursor override here -- that's the handle area's job below -- so
    // hovering content elsewhere in the body doesn't show a move cursor.
    readonly property alias bodyHovered: bodyHov.hovered

    Item {
        id: _bodyHovArea
        x: island.px
        y: island.py
        width: island.bodyW
        height: island.bodyH
        // gated by live: this exists purely for RecordHud/DelosIsland's
        // hold-open-on-hover logic, which only matters while the island is
        // actually showing. Left ungated, it sits active at the island's
        // rest position even while a caller has nothing floating yet (e.g.
        // UndockablePopout while docked), where it can overlap and steal
        // hover from the caller's own docked-state controls.
        HoverHandler { id: bodyHov; enabled: island.live }
    }

    // handle area: the only place the move cursor shows and drag starts.
    Item {
        id: _handleArea
        x: island.px + island.handleX
        y: island.py + island.handleY
        width: island.handleW
        height: island.handleH
        // gated the same as the drag itself -- otherwise this area stays live
        // (invisibly) even while docked, at the island's rest position, which
        // can overlap a caller's own docked-state control (e.g.
        // UndockablePopout's undock button) and steal its hover/cursor.
        HoverHandler { id: handleHov; enabled: island.dragEnabled; cursorShape: Qt.SizeAllCursor }

        DragHandler {
            id: dragH
            target: null
            dragThreshold: 8
            enabled: island.dragEnabled
            cursorShape: Qt.SizeAllCursor
            property real sx: 0
            property real sy: 0
            property real ax: 0
            property real ay: 0
            onActiveChanged: {
                if (dragH.active) {
                    dragH.sx = island.px;
                    dragH.sy = island.py;
                    dragH.ax = dragH.centroid.scenePosition.x;
                    dragH.ay = dragH.centroid.scenePosition.y;
                } else {
                    var e = island.rawNearEdge;
                    island.nearEdge = e;
                    island.alongPx = (e === "top" || e === "bottom") ? island.px : island.py;
                    island.dockEdge = e;
                    island.dragReleased(e);
                }
            }
            onCentroidChanged: {
                if (!dragH.active)
                    return;
                island.px = Math.max(island.lipL, Math.min(island.width  - island.lipR - island.bodyW, dragH.sx + (dragH.centroid.scenePosition.x - dragH.ax)));
                island.py = Math.max(island.lipT, Math.min(island.height - island.lipB - island.bodyH, dragH.sy + (dragH.centroid.scenePosition.y - dragH.ay)));
            }
        }
    }

    // caller enables/disables dragging (RecordHud: when active; UndockablePopout: when undocked).
    property bool dragEnabled: true

    // emitted on drag release so callers can persist dock position etc.
    signal dragReleased(string edge)
}
