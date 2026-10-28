pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "Singletons"

// bar content riding one of the frame's thickened edges, drawn in the frame's
// own scene: no separate program, no seam. the composition and the module
// look follow Config.barStyle: noctalia (dot pills) and caelestia (rounded
// cell strip) are the carried reference dialects; aegis (flat modules with
// hairline accent underlines) and stele (engraved bracket cells) are ours.
//   the row is launcher glyph + workspaces + title left, the clock centred,
//   now-playing + status + tray + power right. triptych groups the three into
//   rounded islands on the band, with now-playing joining the centred clock.
// a wheel over bare band nudges the sink volume, narrated by the OSD.
Item {
    id: bar

    required property real s
    property string position: "top"
    // the band the frame edge swelled by; module pills size against it.
    property real band: 0
    required property var trayWindow

    signal popoutRequested(string name, real center)
    signal hoverPopoutRequested(string name, real center, bool hovered)

    readonly property real moduleSpan: Math.round(bar.band * 0.76)
    readonly property bool triptych: Config.barStyle === "triptych"
    readonly property bool noctalia: Config.barStyle === "noctalia"
    readonly property bool nacre: Config.barStyle === "nacre"
    readonly property bool inir: Config.barStyle === "inir"
    readonly property bool aurora: Config.barStyle === "aurora"
    readonly property bool angel: Config.barStyle === "angel"
    // the flat iNiR-ported skins: a flush full-width bar painting its own
    // background (TUI / glass / brutalist), no frame band, no lobes.
    readonly property bool flatBar: inir || aurora || angel
    // triptych wraps each cluster in a transparent hugger and shell.qml grows a
    // matching frame lobe under it, so the bar dips between the three; every
    // other skin keeps the hugger invisible and the plain straight band.
    readonly property real islandPad: 10 * bar.s
    readonly property real edgeMargin: (bar.triptych ? 12 : 24) * bar.s
    // each cluster hugger's rect in overlay coords (the bar sits at the overlay
    // origin), so shell.qml can fuse a blob lobe beneath it.
    readonly property real leftX: bar.nacre ? (nacreLoader.item ? nacreLoader.item.leftX : 0) : leftIsland.x
    readonly property real leftW: bar.nacre ? (nacreLoader.item ? nacreLoader.item.leftW : 0) : leftIsland.width
    readonly property real centreX: bar.nacre ? (nacreLoader.item ? nacreLoader.item.centreX : 0) : centreIsland.x
    readonly property real centreW: bar.nacre ? (nacreLoader.item ? nacreLoader.item.centreW : 0) : centreIsland.width
    readonly property real rightX: bar.nacre ? (nacreLoader.item ? nacreLoader.item.rightX : 0) : rightIsland.x
    readonly property real rightW: bar.nacre ? (nacreLoader.item ? nacreLoader.item.rightW : 0) : rightIsland.width

    // noctalia's right island grew a net-speed readout ahead of status; on
    // narrower screens the full row (that plus a horizontal now-playing) can
    // outgrow the gap beside the centred clock. decide from quantities that
    // never depend on the outcome -- BarMedia.naturalWidth is its width as
    // laid out in the right island regardless of whether it ends up shown
    // there, and every other module here is sized independently of it -- so
    // bouncing the module to the left island from this can't feed back into
    // its own condition.
    readonly property real rightAvailable: Math.max(0, (bar.width - bar.centreW) / 2 - bar.edgeMargin - 16 * bar.s)
    // how many of the row's other modules actually lay out (Row skips
    // invisible/inactive children entirely, so the gap count has to match).
    readonly property int rightOtherCount: (bar.noctalia && Config.barShowNetSpeed ? 1 : 0)
        + (Config.barShowStatus ? 1 : 0)
        + (Config.barShowWeather && Weather.available ? 1 : 0)
        + (hTray.count > 0 ? 1 : 0)
        + 1 // power, always shown
    readonly property real rightFixedWidth: (bar.noctalia && Config.barShowNetSpeed ? netSpeedLoader.width : 0)
        + (Config.barShowStatus ? statusMod.width : 0)
        + (Config.barShowWeather && Weather.available ? weatherMod.width : 0)
        + (hTray.count > 0 ? trayMod.width : 0)
        + hPowerMod.width
        + rightRow.spacing * Math.max(0, bar.rightOtherCount - 1)
    // hMedia.naturalWidth is just its own Row content; the BarModule chrome
    // around it (mediaMod's padding) costs width whichever way it lays out,
    // and it costs one more row-spacing gap against whatever follows it.
    readonly property real mediaFullWidth: hMedia.naturalWidth + 2 * mediaMod.padX
    readonly property bool mediaShown: Config.barShowMedia && Media.present
    readonly property bool mediaCramped: bar.noctalia && bar.mediaShown
        && (bar.rightFixedWidth + bar.mediaFullWidth + (bar.rightOtherCount > 0 ? rightRow.spacing : 0) > bar.rightAvailable)
    // the bell's along-axis centre (from the status cluster), so the toast
    // popout can grow from the bell like the inbox does. -1 when the status
    // cluster is hidden (no bell), so the toast falls back to the bar end.
    readonly property real bellCenter: bar.nacre
        ? (nacreLoader.item ? nacreLoader.item.bellCenter : -1)
        : bar.flatBar
        ? (flatLoader.item ? flatLoader.item.bellCenter : -1)
        : (Config.barShowStatus ? hStatus.bellCenter : -1)

    property int seedWsId: -1
    readonly property int activeWsId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : seedWsId

    // quickshell's refreshWorkspaces parses nothing out of this Hyprland's
    // IPC, so the focused workspace stays null on a fresh instance until the
    // first event. seed once from hyprctl; events own it from the first switch.
    Process {
        running: true
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { bar.seedWsId = JSON.parse(text).id; } catch (e) {}
            }
        }
    }

    readonly property var sink: Pipewire.defaultAudioSink
    function nudgeVolume(steps) {
        if (!sink || !sink.audio)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + steps * 0.03));
    }
    WheelHandler {
        onWheel: (w) => bar.nudgeVolume(w.angleDelta.y > 0 ? 1 : -1)
    }

    Item {
        id: face
        anchors.fill: parent
        visible: !bar.nacre && !bar.flatBar
        enabled: !bar.nacre && !bar.flatBar

        // ---- left island: seal + workspaces + title --------------------
        Rectangle {
            id: leftIsland
            anchors.left: parent.left
            anchors.leftMargin: bar.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: leftRow.implicitWidth + (bar.triptych ? 2 * bar.islandPad : 0)
            color: "transparent"

            Row {
                id: leftRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: bar.triptych ? bar.islandPad : 0
                spacing: 8 * bar.s

                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    width: bar.moduleSpan
                    filled: false
                    onTapped: Spawn.spawn(["ryoku-shell", "launcher"])

                    BrandMark {
                        size: 11 * bar.s
                    }
                }

                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    padX: (Config.barStyle === "noctalia" || bar.triptych) ? 10 * bar.s : (Config.barStyle === "stele" ? 7 * bar.s : 4 * bar.s)
                    interactive: false

                    BarWorkspaces {
                        s: bar.s
                        activeWsId: bar.activeWsId
                    }
                }

                // Loader, not a plain visible: toggle -- see the matching
                // comment on netSpeedLoader below: triptych/caelestia/aegis/
                // stele reuse this same leftRow but never show this module.
                // sits ahead of the agent-usage module, between it and the
                // workspaces module.
                Loader {
                    id: statsLoader
                    anchors.verticalCenter: parent.verticalCenter
                    visible: active
                    active: bar.noctalia && Config.barShowStats
                    sourceComponent: statsModuleComp
                }

                Loader {
                    id: agentUsageLoader
                    anchors.verticalCenter: parent.verticalCenter
                    visible: active
                    active: bar.noctalia && Config.barShowAgentUsage
                    sourceComponent: agentUsageModuleComp
                }

                // now-playing, bounced here from the right island when the
                // noctalia right side can't fit it beside the centred clock
                // (bar.mediaCramped) -- rather than just shrinking in place,
                // it relocates to sit just before the title. icon-only here
                // too: the left island has no equivalent of rightAvailable
                // capping its width, so a bounced module stays icon-sized
                // rather than risking the same overflow on the other side of
                // the clock that bouncing it was meant to fix.
                BarReveal {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    dropWhenClosed: true
                    shown: bar.mediaCramped

                    BarModule {
                        id: mediaModLeft
                        s: bar.s
                        height: bar.moduleSpan
                        onTapped: hMediaLeft.toggle()
                        onWheeled: (steps) => bar.nudgeVolume(steps)
                        onHoveredChanged: bar.hoverPopoutRequested("media", mediaModLeft.mapToItem(null, mediaModLeft.width / 2, mediaModLeft.height / 2).x, mediaModLeft.hovered)

                        BarMedia {
                            id: hMediaLeft
                            s: bar.s
                            vertical: true
                        }
                    }
                }

                BarTitle {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    maxWidth: (bar.triptych ? 240 : 340) * bar.s
                    label: Config.barShowTitle && ToplevelManager.activeToplevel ? (ToplevelManager.activeToplevel.title || "") : ""
                    iconSource: Config.barShowTitle && ToplevelManager.activeToplevel ? Apps.iconForClass(ToplevelManager.activeToplevel.appId, ToplevelManager.activeToplevel.title) : ""
                    onRequestPopout: (name, center) => bar.popoutRequested(name, center)
                }
            }
        }

        // ---- centre island: clock, and now-playing on triptych ----------
        Rectangle {
            id: centreIsland
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: centerRow.implicitWidth + (bar.triptych ? 2 * bar.islandPad : 0)
            color: "transparent"

            Row {
                id: centerRow
                anchors.centerIn: parent
                spacing: 0

                BarModule {
                    id: clockMod
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    padX: 13 * bar.s
                    onTapped: bar.popoutRequested("calendar", clockMod.mapToItem(null, clockMod.width / 2, clockMod.height / 2).x)

                    BarClock {
                        s: bar.s
                    }
                }

                BarReveal {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    gap: 8 * bar.s
                    shown: bar.triptych && Config.barShowMedia && Media.present

                    BarModule {
                        id: mediaCenter
                        s: bar.s
                        height: bar.moduleSpan
                        onTapped: hMediaCenter.toggle()
                        onWheeled: (steps) => bar.nudgeVolume(steps)
                        onHoveredChanged: bar.hoverPopoutRequested("media", mediaCenter.mapToItem(null, mediaCenter.width / 2, mediaCenter.height / 2).x, mediaCenter.hovered)

                        BarMedia {
                            id: hMediaCenter
                            s: bar.s
                        }
                    }
                }
            }
        }

        // ---- right island: now-playing (other skins) + status + tray + power
        Rectangle {
            id: rightIsland
            anchors.right: parent.right
            anchors.rightMargin: bar.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: rightRow.implicitWidth + (bar.triptych ? 2 * bar.islandPad : 0)
            color: "transparent"

            Row {
                id: rightRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: bar.triptych ? bar.islandPad : 0
                spacing: 8 * bar.s

                // hidden (rather than shrunk) once bar.mediaCramped bounces it
                // to the left island instead -- see leftRow above.
                BarReveal {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    dropWhenClosed: true
                    shown: !bar.triptych && Config.barShowMedia && Media.present && !bar.mediaCramped

                    BarModule {
                        id: mediaMod
                        s: bar.s
                        height: bar.moduleSpan
                        onTapped: hMedia.toggle()
                        onWheeled: (steps) => bar.nudgeVolume(steps)
                        onHoveredChanged: bar.hoverPopoutRequested("media", mediaMod.mapToItem(null, mediaMod.width / 2, mediaMod.height / 2).x, mediaMod.hovered)

                        BarMedia {
                            id: hMedia
                            s: bar.s
                        }
                    }
                }

                // Loader, not a plain visible: toggle: triptych/caelestia/aegis/stele
                // reuse this same shared branch and never show these modules, but a
                // plain visible:false still instantiates the module underneath,
                // leaving SysStats/NetSpeed polling forever for nothing.
                Loader {
                    id: netSpeedLoader
                    anchors.verticalCenter: parent.verticalCenter
                    // Loader keeps its last-loaded width after unloading (item
                    // going null doesn't reset it), so without this the Row
                    // still reserves its stale width once toggled off.
                    visible: active
                    active: bar.noctalia && Config.barShowNetSpeed
                    sourceComponent: netSpeedModuleComp
                }

                BarModule {
                    id: statusMod
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    visible: Config.barShowStatus
                    interactive: false

                    BarStatus {
                        id: hStatus
                        s: bar.s
                        onRequestPopout: (name, center) => bar.popoutRequested(name, center)
                    }
                }

                BarModule {
                    id: weatherMod
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    visible: Config.barShowWeather && Weather.available
                    interactive: false

                    BarWeather {
                        s: bar.s
                        onRequestPopout: (name, center) => bar.popoutRequested(name, center)
                    }
                }

                BarModule {
                    id: trayMod
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    visible: hTray.count > 0
                    padX: 11 * bar.s
                    interactive: false

                    BarTray {
                        id: hTray
                        s: bar.s
                        trayWindow: bar.trayWindow
                        menuEdgeY: bar.height
                    }
                }

                BarModule {
                    id: hPowerMod
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    padX: 10 * bar.s
                    onTapped: bar.popoutRequested("power", hPowerMod.mapToItem(null, hPowerMod.width / 2, hPowerMod.height / 2).x)

                    MaterialIcon {
                        text: "power_settings_new"
                        color: Theme.verm
                        font.pixelSize: 14 * bar.s
                    }
                }
            }
        }
    }

    // Stats/net-speed modules for the shared right island and the agent-usage
    // module for the shared left island (nacre and the flat skins already
    // load their own copies lazily further down): kept as Components so
    // triptych/caelestia/aegis/stele, which reuse these same rows but never
    // show these modules, don't instantiate SysStats/NetSpeed/AgentUsage
    // either.
    Component {
        id: netSpeedModuleComp
        BarModule {
            s: bar.s
            height: bar.moduleSpan
            padX: 6 * bar.s
            interactive: false

            BarNetSpeed { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
        }
    }
    Component {
        id: statsModuleComp
        BarModule {
            s: bar.s
            height: bar.moduleSpan
            padX: 6 * bar.s
            interactive: false

            BarStats {
                s: bar.s
                onRequestPopout: (name, center) => bar.popoutRequested(name, center)
            }
        }
    }
    Component {
        id: agentUsageModuleComp
        BarModule {
            s: bar.s
            height: bar.moduleSpan
            padX: 6 * bar.s
            interactive: false

            BarAgentUsage {
                s: bar.s
                onRequestPopout: (name, center) => bar.popoutRequested(name, center)
            }
        }
    }

    // ---- nacre: three frosted capsules riding a flat, straight band. loaded
    // only when the skin is active, so the five other skins pay nothing for it.
    Loader {
        id: nacreLoader
        anchors.fill: parent
        active: bar.nacre
        sourceComponent: nacreComp
    }
    Component {
        id: nacreComp
        Item {
            id: nacreFace

            readonly property real capPad: 12 * bar.s
            readonly property real edge: 16 * bar.s
            // the bell's centre, published up so the toast grows from it.
            readonly property real bellCenter: Config.barShowStatus ? nStatus.bellCenter : -1
            // a side capsule must not reach the centred centre capsule: cap the
            // width each side may take, so the title elides instead of overlapping.
            readonly property real sideMax: Math.max(0, (nacreFace.width - nCentreCap.width) / 2 - nacreFace.edge - 14 * bar.s)
            // cluster rects, published up so shell.qml grows a blob lobe under
            // each (the triptych mechanic): the frame dips between them and the
            // wallpaper shows in the gaps.
            readonly property real leftX: nLeftCap.x
            readonly property real leftW: nLeftCap.width
            readonly property real centreX: nCentreCap.x
            readonly property real centreW: nCentreCap.width
            readonly property real rightX: nRightCap.x
            readonly property real rightW: nRightCap.width

            // left capsule: seal, now-playing, title.
            Rectangle {
                id: nLeftCap
                readonly property real titleMax: Math.max(0, nacreFace.sideMax - 2 * nacreFace.capPad - nSeal.width - nLeftRow.spacing - (nMediaReveal.visible ? nMediaReveal.width + nLeftRow.spacing : 0))
                anchors.left: parent.left
                anchors.leftMargin: 0
                anchors.top: parent.top
                height: parent.height
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 0
                bottomRightRadius: height / 3
                color: "transparent"
                // no width Behavior of its own: the title and the now-playing
                // reveal already ease their widths, and a second ease here made
                // the frame lobe chase them and trail the text.
                width: nLeftRow.implicitWidth + 2 * nacreFace.capPad

                Row {
                    id: nLeftRow
                    anchors.centerIn: parent
                    spacing: 6 * bar.s

                    BarModule {
                        id: nSeal
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        height: bar.moduleSpan
                        width: bar.moduleSpan
                        filled: false
                        onTapped: Spawn.spawn(["ryoku-shell", "launcher"])
                        BrandMark { size: 11 * bar.s }
                    }
                    BarReveal {
                        id: nMediaReveal
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        dropWhenClosed: true
                        shown: Config.barShowMedia && Media.present

                        BarModule {
                            id: nMediaMod
                            s: bar.s
                            height: bar.moduleSpan
                            padX: 8 * bar.s
                            onTapped: nMedia.toggle()
                            onWheeled: (steps) => bar.nudgeVolume(steps)
                            onHoveredChanged: bar.hoverPopoutRequested("media", nMediaMod.mapToItem(null, nMediaMod.width / 2, nMediaMod.height / 2).x, nMediaMod.hovered)
                            BarMedia { id: nMedia; s: bar.s; vertical: true }
                        }
                    }
                    BarTitle {
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        maxWidth: nLeftCap.titleMax
                        label: Config.barShowTitle && ToplevelManager.activeToplevel ? (ToplevelManager.activeToplevel.title || "") : ""
                        iconSource: Config.barShowTitle && ToplevelManager.activeToplevel ? Apps.iconForClass(ToplevelManager.activeToplevel.appId, ToplevelManager.activeToplevel.title) : ""
                        onRequestPopout: (name, center) => bar.popoutRequested(name, center)
                    }
                }
            }

            // centre capsule: clock, workspaces, system stats.
            Rectangle {
                id: nCentreCap
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                height: parent.height
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: height / 3
                bottomRightRadius: height / 3
                color: "transparent"
                width: nCentreRow.implicitWidth + 2 * nacreFace.capPad
                Behavior on width { NumberAnimation { duration: Motion.spatial; easing.type: Easing.OutCubic } }

                Row {
                    id: nCentreRow
                    anchors.centerIn: parent
                    spacing: 10 * bar.s

                    BarModule {
                        id: nClockMod
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        height: bar.moduleSpan
                        padX: 8 * bar.s
                        onTapped: bar.popoutRequested("calendar", nClockMod.mapToItem(null, nClockMod.width / 2, nClockMod.height / 2).x)
                        BarClock { s: bar.s }
                    }
                    BarModule {
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        height: bar.moduleSpan
                        padX: 6 * bar.s
                        interactive: false
                        BarWorkspaces { s: bar.s; activeWsId: bar.activeWsId }
                    }
                    BarModule {
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        height: bar.moduleSpan
                        padX: 6 * bar.s
                        interactive: false
                        BarStats { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                    }
                    BarModule {
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        height: bar.moduleSpan
                        padX: 6 * bar.s
                        visible: Config.barShowNetSpeed
                        interactive: false
                        BarNetSpeed { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                    }
                    BarModule {
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        height: bar.moduleSpan
                        padX: 6 * bar.s
                        visible: Config.barShowAgentUsage
                        interactive: false
                        BarAgentUsage { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                    }
                }
            }

            // right capsule: status glyphs, tray.
            Rectangle {
                id: nRightCap
                anchors.right: parent.right
                anchors.rightMargin: 0
                anchors.top: parent.top
                height: parent.height
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: height / 3
                bottomRightRadius: 0
                color: "transparent"
                width: nRightRow.implicitWidth + 2 * nacreFace.capPad
                Behavior on width { NumberAnimation { duration: Motion.spatial; easing.type: Easing.OutCubic } }

                Row {
                    id: nRightRow
                    anchors.centerIn: parent
                    spacing: 6 * bar.s

                    BarModule {
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        height: bar.moduleSpan
                        padX: 8 * bar.s
                        visible: Config.barShowStatus
                        interactive: false
                        BarStatus { id: nStatus; s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                    }
                    BarModule {
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        height: bar.moduleSpan
                        padX: 8 * bar.s
                        visible: Config.barShowWeather && Weather.available
                        interactive: false
                        BarWeather { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                    }
                    BarModule {
                        anchors.verticalCenter: parent.verticalCenter
                        s: bar.s
                        height: bar.moduleSpan
                        padX: 8 * bar.s
                        visible: nTray.count > 0
                        interactive: false
                        BarTray { id: nTray; s: bar.s; trayWindow: bar.trayWindow; menuEdgeY: bar.height }
                    }
                }
            }
        }
    }

    // ---- flat iNiR skins: a flush full-width bar carrying borderless modules
    // (inir TUI, aurora glass, angel brutalist). loaded only when active, so the
    // other skins pay nothing for it.
    Loader {
        id: flatLoader
        anchors.fill: parent
        active: bar.flatBar
        sourceComponent: flatComp
    }
    Component {
        id: flatComp
        Item {
            id: flatFace

            readonly property real edge: 16 * bar.s
            // the visible bell's centre, so the toast grows from it like the inbox.
            readonly property real bellCenter: Config.barShowStatus ? flatStatus.bellCenter : -1

            // a hairline cell divider; the TUI feel is inir's alone, so the other
            // two flat skins hide it and the Row drops the gap.
            component Sep: Rectangle {
                visible: bar.inir
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, bar.s)
                height: Math.round(bar.moduleSpan * 0.62)
                color: Qt.alpha(Theme.border, 0.7)
            }

            // full-width flush surface. inir: flat opaque TUI panel; aurora:
            // translucent glass the wallpaper shows through; angel: opaque with a
            // heavy base border and a bright inset top edge (the brutalist glow).
            Rectangle {
                id: flatBg
                anchors.fill: parent
                readonly property color surf: Config.matchWallpaper ? Wallust.surface : Config.surfaceColor
                readonly property color deep: Config.matchWallpaper ? Wallust.base : Config.surfaceColor
                // aurora reads as a lit glass pane: a top-down translucency gradient
                // (denser up top where the light catches, clearer below) keeps the
                // modules legible and stops it collapsing into inir's flat panel on a
                // dark wallpaper. inir and angel are flat, so both stops resolve to
                // one solid tone.
                gradient: Gradient {
                    GradientStop { position: 0; color: bar.aurora ? Qt.alpha(flatBg.surf, 0.62) : (bar.angel ? flatBg.deep : flatBg.surf) }
                    GradientStop { position: 1; color: bar.aurora ? Qt.alpha(flatBg.surf, 0.44) : (bar.angel ? flatBg.deep : flatBg.surf) }
                }

                Rectangle { // aurora glass edge: a crisp lit highlight along the top
                    visible: bar.aurora
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: Math.max(1, 2 * bar.s)
                    color: Qt.alpha(Theme.cream, 0.3)
                }
                Rectangle { // angel inset top glow
                    visible: bar.angel
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: Math.max(1, 2 * bar.s)
                    color: Qt.alpha(Theme.brand, 0.6)
                }
                Rectangle { // base border: inir hairline, aurora subtle, angel heavy
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: bar.angel ? Math.max(2, 3 * bar.s) : Math.max(1, bar.s)
                    color: bar.angel ? Theme.lineStrong : Qt.alpha(Theme.border, bar.aurora ? 0.55 : 1.0)
                }
            }

            // ---- left cluster: seal, workspaces, stats, media ----
            Row {
                anchors.left: parent.left
                anchors.leftMargin: flatFace.edge
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6 * bar.s

                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    width: bar.moduleSpan
                    filled: false
                    onTapped: Spawn.spawn(["ryoku-shell", "launcher"])
                    BrandMark { size: 11 * bar.s }
                }
                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    padX: 6 * bar.s
                    interactive: false
                    BarWorkspaces { s: bar.s; activeWsId: bar.activeWsId }
                }
                Sep {}
                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    padX: 8 * bar.s
                    interactive: false
                    BarStats { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                }
                Sep { visible: bar.inir && Config.barShowNetSpeed }
                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    padX: 8 * bar.s
                    visible: Config.barShowNetSpeed
                    interactive: false
                    BarNetSpeed { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                }
                // angel only here -- inir/aurora's left cluster is already
                // crowded (workspaces, stats, net-speed, media), so their
                // agent-usage module rides the right cluster instead, below.
                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    padX: 8 * bar.s
                    visible: bar.angel && Config.barShowAgentUsage
                    interactive: false
                    BarAgentUsage { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                }
                Sep { visible: bar.inir && Config.barShowMedia && Media.present }
                BarReveal {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    dropWhenClosed: true
                    shown: Config.barShowMedia && Media.present
                    BarModule {
                        id: flatMediaMod
                        s: bar.s
                        height: bar.moduleSpan
                        onTapped: flatMedia.toggle()
                        onWheeled: (steps) => bar.nudgeVolume(steps)
                        onHoveredChanged: bar.hoverPopoutRequested("media", flatMediaMod.mapToItem(null, flatMediaMod.width / 2, flatMediaMod.height / 2).x, flatMediaMod.hovered)
                        BarMedia { id: flatMedia; s: bar.s }
                    }
                }
            }

            // ---- centre: clock ----
            BarModule {
                id: flatClockMod
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                s: bar.s
                height: bar.moduleSpan
                padX: 13 * bar.s
                onTapped: bar.popoutRequested("calendar", flatClockMod.mapToItem(null, flatClockMod.width / 2, flatClockMod.height / 2).x)
                BarClock { s: bar.s }
            }

            // ---- right cluster: status, tray ----
            Row {
                anchors.right: parent.right
                anchors.rightMargin: flatFace.edge
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6 * bar.s

                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    visible: Config.barShowStatus
                    interactive: false
                    BarStatus { id: flatStatus; s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                }
                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    visible: Config.barShowWeather && Weather.available
                    interactive: false
                    BarWeather { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                }
                // inir/aurora only -- angel keeps its copy on the left
                // cluster, above; inir/aurora's left is the crowded one.
                Sep { visible: bar.inir && Config.barShowAgentUsage }
                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    visible: (bar.inir || bar.aurora) && Config.barShowAgentUsage
                    interactive: false
                    BarAgentUsage { s: bar.s; onRequestPopout: (name, center) => bar.popoutRequested(name, center) }
                }
                Sep { visible: bar.inir && flatTray.count > 0 }
                BarModule {
                    anchors.verticalCenter: parent.verticalCenter
                    s: bar.s
                    height: bar.moduleSpan
                    visible: flatTray.count > 0
                    padX: 11 * bar.s
                    interactive: false
                    BarTray { id: flatTray; s: bar.s; trayWindow: bar.trayWindow; menuEdgeY: bar.height }
                }
            }
        }
    }
}
