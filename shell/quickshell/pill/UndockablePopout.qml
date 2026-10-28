pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Blobs
import "Singletons"
import "popouts"

// A shell bar popout that can be detached from the frame edge.
//
// While docked, it works exactly like Popout: hover/pin opens it from the bar
// edge, the blob melts out of the frame border, and it closes when the pointer
// leaves. An undock button (upper-left corner of the body) appears when the
// popout is open. Tapping it detaches the body into a free-floating island in
// the blob field -- identical in feel to the RecordHud. While floating:
//   · The undock button becomes a grip icon to signal moveability.
//   · An X button appears in the upper-right to close the island.
//   · The island can be dragged anywhere in the frame lip area.
//   · Reopening the popout (click/pin its bar trigger) returns to docked mode
//     immediately, resetting the float state.
//
// Shell.qml mask integration: while docked, use maskX/Y/W/H as for any Popout.
// While floating, use floatHudX/Y/W/H (the island body rect).
//
//   UndockablePopout {
//       id: myPop
//       group: blobGroup; frameThickness: 16; s: overlay.s
//       edge: "top"; openW: 300; openH: 400
//       pinned: root.popout === "myPop" && root.popoutMon === overlay.modelData.name
//       SomeContent {}
//   }
Item {
    id: root

    // ---- Popout passthrough properties ------------------------------------
    required property var group
    required property real frameThickness
    property real radius: Theme.radius
    property real smoothing: 30
    property string edge: "top"
    property string align: "center"
    property real alongCenter: -1
    property real openW: 300
    property real openH: 400
    property bool fullSpan: false
    property real hoverW: 0
    property real hoverH: 0
    property real s: 1
    property bool pinned: false
    property bool hoverOpen: true
    property bool triggerHovered: false
    property bool extraHold: false
    property bool active: true
    property int closeDelay: 0

    // ---- Float-specific interface -----------------------------------------
    property string barEdge: ""
    property real barBand: 0
    property real floatRadius: 17 * s

    // height reserved at the top of the body for the undock/grip/close
    // controls, so they get their own row instead of sitting on top of the
    // caller's content (e.g. a header icon/label in the content's corner).
    property real controlInset: 28 * s

    // true while the island is floating (detached from the edge).
    property bool floating: false

    // emitted when the floating island's X is tapped -- the caller should
    // unpin (e.g. root.popout = ""), the same way it wires up any other
    // popout's closeRequested, or the docked Popout reopens right behind it
    // (it's still pinned/active, so its own shouldOpen stays true).
    signal closeRequested()

    // input-mask rect while floating (union into shell.qml's barRegion).
    readonly property real floatHudX: island.hudX
    readonly property real floatHudY: island.hudY
    readonly property real floatHudW: root.floating && island.live ? island.hudW : 0
    readonly property real floatHudH: root.floating && island.live ? island.hudH : 0
    readonly property bool floatDragging: island.dragging

    // mask passthrough from the inner Popout (only meaningful while docked).
    readonly property real prog: dockedPop.prog
    readonly property real maskX: dockedPop.maskX
    readonly property real maskY: dockedPop.maskY
    readonly property real maskW: root.floating ? 0 : dockedPop.maskW
    readonly property real maskH: root.floating ? 0 : dockedPop.maskH
    readonly property real triggerX: dockedPop.triggerX
    readonly property real triggerY: dockedPop.triggerY
    readonly property real triggerW: dockedPop.triggerW
    readonly property real triggerH: dockedPop.triggerH
    property alias contentTopLeftRadius: dockedPop.contentTopLeftRadius
    property alias contentTopRightRadius: dockedPop.contentTopRightRadius
    property alias contentBottomLeftRadius: dockedPop.contentBottomLeftRadius
    property alias contentBottomRightRadius: dockedPop.contentBottomRightRadius

    anchors.fill: parent

    // Every UndockablePopout instance is a sibling of every other one, so
    // with no explicit z here, which one paints on top when two happen to
    // overlap is pure declaration-order coincidence -- a popout declared
    // later in shell.qml always wins, regardless of which is docked and
    // which is floating. A docked popout is only ever open for a moment
    // (the user is actively looking at it), so it should always beat a
    // floating island that's just sitting there -- but only other popout
    // siblings (default z 0): the bar itself sits at z:1, and a docked
    // popout must still stay under it, not cover its modules.
    z: dockedPop.heldOpen ? 0.5 : 0

    // Re-dock when the popout is reopened while floating.
    onPinnedChanged: {
        if (root.pinned && root.floating)
            root.floating = false;
    }

    // ---- Docked Popout ------------------------------------------------------
    Popout {
        id: dockedPop
        group: root.group
        frameThickness: root.frameThickness
        radius: root.radius
        smoothing: root.smoothing
        edge: root.edge
        align: root.align
        alongCenter: root.alongCenter
        openW: root.openW
        openH: root.openH + root.controlInset
        fullSpan: root.fullSpan
        hoverW: root.hoverW
        hoverH: root.hoverH
        s: root.s
        pinned: root.pinned
        hoverOpen: root.hoverOpen
        triggerHovered: root.triggerHovered
        extraHold: root.extraHold
        active: root.active && !root.floating
        closeDelay: root.closeDelay

        // content sits below the reserved control row.
        Item {
            id: dockedContentHolder
            x: 0
            y: root.controlInset
            width: root.openW
            height: root.openH
        }
    }

    // undock button: its own row above the content, visible when open. A
    // sibling of dockedPop, positioned from its plain (undeformed) maskX/Y,
    // NOT a child of it -- content inside dockedPop sits under the body
    // blob's melt-deform transform, which (strongest right at the frame
    // edge, exactly where this button sits) shifts the rendered position
    // away from the hit-test position, so hover/click never lined up with
    // what was drawn. Nothing here rides that transform, so both agree.
    Item {
        // bodyX/bodyY, not maskX/maskY -- the mask is deliberately extended
        // to the true screen edge to catch input over the "neck" the body
        // melts out of (see Popout.qml), which is not where the body is
        // actually drawn. bodyX/Y is the real visual top-left.
        //
        // The bar itself (z:1, a sibling of this popout's whole subtree, so
        // no local z here can out-rank it) paints above anything at/near
        // bodyY -- Bar.qml's own comment: "the bar only ever covers a
        // popout's neck, never its body," i.e. right at bodyY is the
        // boundary. Centering this row within controlInset left only ~2px
        // of clearance there, so the bar was winning the top half of the
        // button's input. Force real clearance instead of centering.
        x: dockedPop.bodyX + 6 * root.s
        y: dockedPop.bodyY + Math.max((root.controlInset - height) / 2, 10 * root.s)
        z: 10
        width: undockBtn.width + 4 * root.s
        height: undockBtn.height + 4 * root.s
        visible: dockedPop.heldOpen && !root.floating
        opacity: Math.max(0, Math.min(1, (dockedPop.prog - 0.5) / 0.4))
        Behavior on opacity { NumberAnimation { duration: Motion.effects } }

        Rectangle {
            id: undockBtn
            x: 4 * root.s
            y: 4 * root.s
            width: 20 * root.s
            height: 20 * root.s
            radius: 5 * root.s
            color: undockArea.containsMouse ? Theme.frameBg : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            GlyphIcon {
                anchors.centerIn: parent
                width: 12 * root.s
                height: 12 * root.s
                name: "undock"
                color: Theme.dim
                stroke: 1.7
            }
        }
        MouseArea {
            id: undockArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                // seed the island at its own computed dock position for this
                // edge/along-axis spot, not the docked popout's raw on-screen
                // position -- FloatingIsland continuously pulls px/py toward
                // dockX/dockY (with a slow drift animation) whenever it isn't
                // being dragged, so seeding anything else just means it
                // immediately drifts from our seed to its real resting spot.
                // Setting dockEdge/alongPx first, then reading dockX/dockY,
                // means the seed already IS the resting spot: no drift.
                var e = root.edge;
                island.dockEdge = e;
                island.alongPx = (e === "top" || e === "bottom") ? dockedPop.maskX : dockedPop.maskY;
                island.nearEdge = e;
                island.placed = true;
                island.px = island.dockX;
                island.py = island.dockY;
                root.floating = true;
            }
        }
    }

    // Children declared in UndockablePopout { ... } land below the control
    // row in the docked Popout body, exactly as they would in a bare
    // Popout { ... }.
    default property alias contentData: dockedContentHolder.data

    // ---- Floating island (active only while floating) -----------------------
    // Body width matches the docked popout's open width (content is
    // generally fixed-width regardless of which sections are showing).
    // Height does NOT reuse the docked popout's openH: once docked closes
    // (active: false while floating), its own content often collapses
    // internal sections via its own `open` prop tied to dockedPop.prog
    // dropping to 0, shrinking its implicitHeight -- and since openH stays
    // bound to that same (now-collapsing) instance, the floating body was
    // being sized from a popout that's in the middle of closing, clipping
    // whatever didn't fit. Size from the floating content's own real height
    // instead, once it's loaded.
    property real _floatW: root.openW + 2 * _floatPad
    property real _floatH: root._floatContentH + 2 * _floatPad + root.controlInset
    readonly property real _floatContentH: (root.floating && floatLoader.item) ? floatLoader.item.implicitHeight : root.openH
    readonly property real _floatPad: 12 * root.s

    // prog animation for the floating island (separate from docked Popout's
    // prog). Stays a live binding -- Behavior animates binding-driven changes
    // just as well as imperative ones, and an explicit re-assignment here
    // previously raced the (lazily-evaluated) _floatWantProg binding and
    // could latch _floatProg at its stale pre-toggle value permanently.
    //
    // Detaching shows content that was already fully open a moment ago (just
    // relocating, not opening fresh), so that transition is instant -- an
    // animated melt-in there only doubles up with the docked popout's own
    // closing animation and reads as "closes, then reopens". Re-docking still
    // melts back in smoothly, since that's a real close.
    readonly property real _floatWantProg: root.floating ? 1 : 0
    property real _floatProg: _floatWantProg
    Behavior on _floatProg { NumberAnimation { duration: root.floating ? 0 : 620; easing.type: Easing.InOutCubic } }

    FloatingIsland {
        id: island
        group: root.group
        s: root.s
        radius: root.floatRadius
        smoothing: root.smoothing
        barEdge: root.barEdge
        barBand: root.barBand
        bodyW: root._floatW
        bodyH: root._floatH
        live: root.floating
        dragEnabled: root.floating
        dockEdge: root.edge
        prog: root._floatProg

        onDragReleased: (_e) => {}

        // drag hitbox for the grip icon below (a constant offset from
        // island.px/py, same as the grip's own position -- see the note by
        // floatControls below for why the grip isn't what defines this
        // directly).
        handleX: 6 * root.s
        handleY: Math.max((root.controlInset - 24 * root.s) / 2, 10 * root.s)
        handleW: 24 * root.s
        handleH: 24 * root.s
    }

    // ---- Floating content layer ---------------------------------------------
    // Mirrors the Popout content at the island position while floating.
    Item {
        id: floatContent
        x: island.px
        y: island.py
        width: root._floatW
        height: root._floatH
        visible: root.floating && island.prog > 0.004
        opacity: root.floating ? Math.max(0, Math.min(1, (island.prog - 0.3) / 0.5)) : 0
        Behavior on opacity { NumberAnimation { duration: Motion.effects; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.effectsCurve } }
        transform: Matrix4x4 { matrix: island.deformMatrix }

        // Content area: a clone of the Popout's inner content at full size.
        // Callers provide content as children of this UndockablePopout; that
        // content lives in dockedPop when docked. While floating we render a
        // Loader that re-loads the same content component if the caller gives
        // us one via `floatingContent`, or falls back to a blank placeholder.
        // This design keeps a single content tree owned by dockedPop while
        // docked, and switches to a floatingContentComponent while floating.
        // See property `floatingContent` below.
        Item {
            x: root._floatPad; y: root._floatPad + root.controlInset
            width: root.openW; height: root._floatContentH
            clip: true

            Loader {
                id: floatLoader
                anchors.fill: parent
                sourceComponent: root.floating ? root.floatingContent : null
            }
        }
    }

    // Floating controls: siblings of floatContent, NOT children of it --
    // floatContent rides island.deformMatrix (the blob's melt wobble), which
    // shifts the rendered position away from the hit-test position (worst
    // right at the frame edge, exactly where these sit -- the same issue
    // fixed for the docked undock button above). Positioned from island.px/py
    // directly instead, which never carries that transform.
    readonly property real _floatCtrlOpacity: root.floating ? Math.max(0, Math.min(1, (island.prog - 0.3) / 0.5)) : 0

    // grip icon (upper-left, replaces the undock button).
    Item {
        x: island.px + 6 * root.s
        y: island.py + Math.max((root.controlInset - height) / 2, 10 * root.s)
        z: 10
        width: 24 * root.s; height: 24 * root.s
        visible: root.floating && island.prog > 0.004
        opacity: root._floatCtrlOpacity
        Behavior on opacity { NumberAnimation { duration: Motion.effects; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.effectsCurve } }
        Grid {
            anchors.centerIn: parent
            columns: 2
            rowSpacing: 3 * root.s
            columnSpacing: 3 * root.s
            Repeater {
                model: 6
                Rectangle {
                    width: 3 * root.s; height: 3 * root.s; radius: width / 2
                    color: floatGripArea.containsMouse ? Theme.cream : Theme.subtle
                }
            }
        }
        MouseArea {
            id: floatGripArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeAllCursor
            acceptedButtons: Qt.NoButton
        }
    }

    // close button (upper-right).
    Item {
        x: island.px + root._floatW - width - 6 * root.s
        y: island.py + Math.max((root.controlInset - height) / 2, 10 * root.s)
        z: 10
        width: 24 * root.s; height: 24 * root.s
        visible: root.floating && island.prog > 0.004
        opacity: root._floatCtrlOpacity
        Behavior on opacity { NumberAnimation { duration: Motion.effects; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.effectsCurve } }
        Rectangle {
            id: closeBtn
            anchors.fill: parent
            anchors.margins: 4 * root.s
            radius: 5 * root.s
            color: closeArea.containsMouse ? Theme.frameBg : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            GlyphIcon {
                anchors.centerIn: parent
                width: 11 * root.s; height: 11 * root.s
                name: "close"
                color: Theme.dim
                stroke: 1.7
            }
        }
        MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                // X means fully closed, not "back to docked" -- if the caller
                // is still pinned (root.popout still selecting this popout),
                // just clearing floating lets the docked Popout's own
                // shouldOpen (active && pinned) reopen it right back up. The
                // caller unpins in response to closeRequested (shell.qml sets
                // root.popout = "" the same way other popouts' close does).
                root.floating = false;
                root.closeRequested();
            }
        }
    }

    // Caller provides this component to render inside the floating island.
    // If null (default), the floating body shows blank. For popouts whose
    // content is side-effect-free to instantiate twice (most display widgets),
    // pass the same component as the docked content.
    property Component floatingContent: null
}
