pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "Singletons"

// the delos bar: the whole bar collapsed into one floating island in the
// frame's blob field. fused to a frame edge at rest, drag the grip to pull it
// off; a frame bump reaches for it as it nears an edge; let go and it drifts
// back. tap the grip to tuck to a nub that hovering pops back out. carries the
// modules from Config.islandModules; publishes its live dock state to IslandDock
// so the window reserve follows it. Nothing snaps.
//
// Floating geometry, drag, and blob logic live in FloatingIsland.
Item {
    id: hud

    required property var group
    property real s: 1
    property bool active: true
    property real radius: Config.islandRadius * s
    property real smoothing: 30
    // delos never pre-thickens an edge (the island is the bar).
    property real barBand: 0
    property string barEdge: ""

    // 12h hour for the vertical clock module.
    function hh12(d) {
        var h = d.getHours() % 12;
        if (h === 0) h = 12;
        return (h < 10 ? "0" : "") + h;
    }

    readonly property int activeWsId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    required property var trayWindow

    signal popoutRequested(string name)
    signal hoverPopoutRequested(string name, bool hovered)

    anchors.fill: parent

    property bool hidden: false
    // keep island.hidden in sync so FloatingIsland's nub/trigger logic reads it.
    Binding { target: island; property: "hidden"; value: hud.hidden }

    // --- reveal + melt -------------------------------------------------------
    property bool revealHeld: false
    readonly property bool revealed: island.bodyHovered || island.nubRevealed
    readonly property bool tucked: hud.hidden && !hud.revealHeld
    onRevealedChanged: {
        if (hud.revealed) { revealGrace.stop(); hud.revealHeld = true; }
        else revealGrace.restart();
    }
    Timer { id: revealGrace; interval: 260; onTriggered: hud.revealHeld = false }

    readonly property real nubProg: 0.14
    readonly property real wantProg: !hud.active ? 0 : ((!hud.hidden || hud.revealHeld) ? 1 : hud.nubProg)
    property real prog: hud.wantProg
    Behavior on prog { NumberAnimation { duration: island.meltDur; easing.type: Easing.InOutCubic } }
    readonly property bool live: hud.active && hud.prog > 0.002
    visible: hud.live

    Binding { target: island; property: "prog"; value: hud.prog }
    Binding { target: island; property: "live"; value: hud.live }

    // --- geometry re-exports for shell.qml's input mask ----------------------
    readonly property alias hudX:     island.hudX
    readonly property alias hudY:     island.hudY
    readonly property alias hudW:     island.hudW
    readonly property alias hudH:     island.hudH
    // delos has whole-edge trigger while tucked; override the strip here.
    readonly property real trigX: island.dockEdge === "right"  ? (island.width  - island.trigDepth)
                                : island.dockEdge === "left"   ? 0
                                : (island.tucked ? 0 : (island.dockX - island.trigPad))
    readonly property real trigY: island.dockEdge === "bottom" ? (island.height - island.trigDepth)
                                : island.dockEdge === "top"    ? 0
                                : (island.tucked ? 0 : (island.dockY - island.trigPad))
    readonly property real trigW: (island.dockEdge === "left" || island.dockEdge === "right") ? island.trigDepth
                                : (island.tucked ? island.width  : (island.hudW + 2 * island.trigPad))
    readonly property real trigH: (island.dockEdge === "top"  || island.dockEdge === "bottom") ? island.trigDepth
                                : (island.tucked ? island.height : (island.hudH + 2 * island.trigPad))
    readonly property alias dragging: island.dragging

    // --- publish live dock state to IslandDock reserve -----------------------
    readonly property real fullExtent: (island.dockEdge === "left" || island.dockEdge === "right") ? island.bodyW : island.bodyH
    readonly property real reserveThickness: island.lipFor(island.dockEdge) + (hud.hidden ? hud.fullExtent * hud.nubProg : hud.fullExtent)
    readonly property real alongCentre: (island.dockEdge === "left" || island.dockEdge === "right") ? (island.py + island.bodyH / 2) : (island.px + island.bodyW / 2)
    Binding { target: IslandDock; property: "active";    value: hud.active }
    Binding { target: IslandDock; property: "edge";      value: island.dockEdge }
    Binding { target: IslandDock; property: "thickness"; value: hud.active ? hud.reserveThickness : 0 }
    Binding { target: IslandDock; property: "along";     value: hud.alongCentre }
    Binding { target: IslandDock; property: "hidden";    value: hud.hidden }

    // write dock position back so it survives a restart.
    function persistDock() {
        Config.islandEdge   = island.dockEdge;
        Config.islandAlong  = island.alongPx;
        Config.islandHidden = hud.hidden;
        Config.persist();
    }

    // --- FloatingIsland (all geometry, drag, blobs) --------------------------
    FloatingIsland {
        id: island
        group: hud.group
        s: hud.s
        radius: hud.radius
        smoothing: hud.smoothing
        barEdge: hud.barEdge
        barBand: hud.barBand
        dockEdge: "top"
        dragEnabled: true

        // delos orientation does not flip mid-drag: keep layoutVertical during drag
        // so a grab at the threshold never reflowing the content under the pointer.
        vertical: island.dragging ? island.layoutVertical : (island.dockEdge === "left" || island.dockEdge === "right")

        // body size driven from grid content, animated.
        property real _targetW: grid.implicitWidth  + 22 * hud.s
        property real _targetH: grid.implicitHeight + 13 * hud.s
        Behavior on _targetW { NumberAnimation { duration: island.moveDur; easing.type: Easing.InOutCubic } }
        Behavior on _targetH { NumberAnimation { duration: island.moveDur; easing.type: Easing.InOutCubic } }
        Binding { target: island; property: "bodyW"; value: island._targetW }
        Binding { target: island; property: "bodyH"; value: island._targetH }

        // seed dock from Config on first layout (overrides FloatingIsland.reposition).
        Component.onCompleted: {
            island.dockEdge = Config.islandEdge;
            hud.hidden      = Config.islandHidden;
            island.nearEdge = island.dockEdge;
        }
        onWidthChanged: {
            if (island.placed || island.width <= 0)
                return;
            island.alongPx = Config.islandAlong >= 0 ? Config.islandAlong
                : (island.vertical ? (island.height - island.bodyH) / 2 : (island.width - island.bodyW) / 2);
            island.px = island.dockX;
            island.py = island.dockY;
            island.placed = true;
        }
        onHeightChanged: {
            if (island.placed || island.width <= 0)
                return;
            island.alongPx = Config.islandAlong >= 0 ? Config.islandAlong
                : (island.vertical ? (island.height - island.bodyH) / 2 : (island.width - island.bodyW) / 2);
            island.px = island.dockX;
            island.py = island.dockY;
            island.placed = true;
        }

        onDragReleased: (_e) => hud.persistDock()
    }

    onHiddenChanged: hud.persistDock()

    // --- module components ---------------------------------------------------
    SystemClock { id: clock; precision: SystemClock.Minutes }

    Component { id: wsComp; BarWorkspaces { s: hud.s; activeWsId: hud.activeWsId; vertical: island.layoutVertical; enabled: false } }
    Component {
        id: clockComp
        Grid {
            columns: island.layoutVertical ? 1 : 2
            rowSpacing: 2 * hud.s
            columnSpacing: 7 * hud.s
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            Rectangle { width: 7 * hud.s; height: 7 * hud.s; radius: width / 2; color: Theme.sun }
            Text {
                text: island.layoutVertical
                    ? (Config.clock24h ? clock.date.toLocaleTimeString(Qt.locale("en_US"), "HH") : hud.hh12(clock.date))
                        + "\n" + clock.date.toLocaleTimeString(Qt.locale("en_US"), "mm")
                    : (Config.clock24h ? clock.date.toLocaleTimeString(Qt.locale("en_US"), "HH:mm") : clock.date.toLocaleTimeString(Qt.locale("en_US"), "h:mm AP"))
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 0.88
                color: Theme.bright
                font.family: Theme.mono
                font.pixelSize: 14 * hud.s
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                font.features: ({ "tnum": 1 })
            }
            TapHandler { onTapped: hud.popoutRequested("calendar") }
        }
    }
    Component {
        id: dateComp
        Grid {
            columns: island.layoutVertical ? 1 : 2
            rowSpacing: 2 * hud.s
            columnSpacing: 6 * hud.s
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            Rectangle { visible: !island.layoutVertical; width: Math.max(1, hud.s); height: 11 * hud.s; color: Theme.hair }
            Text {
                text: island.layoutVertical
                    ? (clock.date.toLocaleDateString(Qt.locale("en_US"), "ddd") + "\n" + clock.date.toLocaleDateString(Qt.locale("en_US"), "d") + "\n" + clock.date.toLocaleDateString(Qt.locale("en_US"), "MMM")).toUpperCase()
                    : clock.date.toLocaleDateString(Qt.locale("en_US"), "ddd d MMM").toUpperCase()
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.0
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: 9.5 * hud.s
                font.weight: Font.Medium
                font.letterSpacing: 2
            }
            TapHandler { onTapped: hud.popoutRequested("calendar") }
        }
    }
    Component {
        id: mediaComp
        Item {
            visible: Media.present
            implicitWidth:  island.layoutVertical ? vIcon.implicitWidth  : (Media.present ? med.implicitWidth  : 0)
            implicitHeight: island.layoutVertical ? vIcon.implicitHeight : med.implicitHeight
            BarMedia { id: med; s: hud.s; visible: !island.layoutVertical }
            MaterialIcon { id: vIcon; anchors.centerIn: parent; visible: island.layoutVertical; text: "music_note"; color: Theme.cream; font.pixelSize: 15 * hud.s }
            HoverHandler { id: medHov; onHoveredChanged: hud.hoverPopoutRequested("media", medHov.hovered) }
            TapHandler { onTapped: Media.toggle() }
            onVisibleChanged: if (!visible) hud.hoverPopoutRequested("media", false)
        }
    }
    Component { id: titleComp;  BarTitle  { s: hud.s; maxWidth: 220 * hud.s; label: Config.barShowTitle && ToplevelManager.activeToplevel ? (ToplevelManager.activeToplevel.title || "") : ""; iconSource: Config.barShowTitle && ToplevelManager.activeToplevel ? Apps.iconForClass(ToplevelManager.activeToplevel.appId, ToplevelManager.activeToplevel.title) : ""; onRequestPopout: (name, center) => hud.popoutRequested(name) } }
    Component { id: statusComp; BarStatus  { s: hud.s; vertical: island.layoutVertical; onRequestPopout: (name, center) => hud.popoutRequested(name) } }
    Component { id: trayComp;   BarTray    { s: hud.s; vertical: island.layoutVertical; trayWindow: hud.trayWindow; menuEdgeY: island.py + island.bodyH } }

    // --- content item --------------------------------------------------------
    Item {
        id: content
        x: island.px
        y: island.py
        width: island.bodyW
        height: island.bodyH
        opacity: island.reorientFade * Math.max(0, Math.min(1, (hud.prog - 0.6) / 0.35))
        transform: Matrix4x4 { matrix: island.deformMatrix }
        HoverHandler { id: bodyHov }

        // the grip reflows with orientation/module changes -- track its real
        // position so the drag hitbox (in FloatingIsland) stays under it.
        Binding { target: island; property: "handleX"; value: grid.x + gripItem.x }
        Binding { target: island; property: "handleY"; value: grid.y + gripItem.y }
        Binding { target: island; property: "handleW"; value: gripItem.width }
        Binding { target: island; property: "handleH"; value: gripItem.height }

        Grid {
            id: grid
            anchors.centerIn: parent
            columns: island.layoutVertical ? 1 : 99
            rowSpacing: 8 * hud.s
            columnSpacing: 12 * hud.s
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            // grip: only drag handle; tap tucks to nub.
            Item {
                id: gripItem
                width: 14 * hud.s
                height: 16 * hud.s
                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    rowSpacing: 3 * hud.s
                    columnSpacing: 3 * hud.s
                    Repeater {
                        model: 6
                        Rectangle {
                            width: 3 * hud.s
                            height: 3 * hud.s
                            radius: width / 2
                            color: gripHov.hovered ? Theme.cream : Theme.dim
                        }
                    }
                }
                HoverHandler { id: gripHov; cursorShape: Qt.SizeAllCursor }
                TapHandler { onTapped: hud.hidden = !hud.hidden }
            }

            Repeater {
                model: Config.islandModules
                Loader {
                    required property var modelData
                    enabled: !island.dragging
                    sourceComponent: modelData === "workspaces" ? wsComp
                        : modelData === "clock"  ? clockComp
                        : modelData === "date"   ? dateComp
                        : modelData === "media"  ? mediaComp
                        : modelData === "title"  ? titleComp
                        : modelData === "status" ? statusComp
                        : modelData === "tray"   ? trayComp
                        : null
                }
            }
        }
    }

    // tucked cue dot.
    Rectangle {
        readonly property real cx: island.faceX + island.faceW / 2
        readonly property real cy: island.faceY + island.faceH / 2
        width: 7 * hud.s
        height: 7 * hud.s
        radius: width / 2
        x: cx - width / 2
        y: cy - height / 2
        color: Theme.brand
        opacity: hud.active ? Math.max(0, 1 - hud.prog / 0.5) * 0.9 : 0
        visible: opacity > 0.01
    }
}
