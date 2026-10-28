//@ pragma UseQApplication
// threaded render loop: the blob melt is a per-frame spring (plugin/blobrect.cpp)
// plus scene-graph animations; threaded is vsync-locked and frees the GUI thread, so
// the spring gets regular frame deltas and never stutters behind layout/JS. (basic
// idled ~5% cheaper on NVIDIA with the island's live MultiEffects in the scene, but
// smoothness wins and blobs snap to rest when idle.)
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Ryoku.Blobs
import "Singletons"
import "popouts"

// the ryoku shell surface. per monitor, the layer-shell windows are:
//   reserve      = zero-content top strip, mapped only for a TOP bar, claiming
//                  its exclusive zone so tiled windows sit below the band.
//   sideReserve  = the same for a bottom/left/right bar's own edge.
//   overlay      = full-screen transparent Overlay layer: the rounded frame,
//                  the bar riding one edge, and every summoned surface as an
//                  edge popout growing from the bar (see popouts/). never moves
//                  windows; grows in place.
//   OsdWindow    = the volume/brightness OSD, top-centre below the bar.
//
// input routing = the overlay window mask: the bar strip and open popout bodies
// catch clicks, the rest of the screen clicks through. a modal (keyboard) popout
// clears the mask so a backdrop press dismisses; keyboard focus is taken on
// demand so Escape closes it.
ShellRoot {
    id: root

    property string peekMon: ""

    // which edge popout (mixer/power) is pinned by IPC, and on which
    // monitor. hover is the usual trigger; this is the keybind path.
    property string popout: ""
    property string popoutMon: ""
    // voiceShow with the dictation service off: the popout says so instead of
    // drawing a wave that would record nothing.
    property bool voiceOff: false
    // along-axis centre of the bar icon that opened the current popout (window
    // coords), so the popout blob grows from that icon on whatever edge the bar
    // sits. set by togglePopoutAt from the bar's click.
    property real popoutCenter: 0

    // media hover popout: the now-playing module drives this while hovered,
    // feeding its centre. distinct from the clicked `popout` above so hover
    // and click never clobber each other.
    property string hoverPopout: ""
    property string hoverPopoutMon: ""
    property real hoverPopoutCenter: 0
    // which pane each sidebar shows. tab taps set it; the stash IPC jumps the
    // left sidebar straight to its stash pane. "" = the sidebar's first pane.
    property string sidebarLeftPane: ""
    property string sidebarRightPane: ""

    // popouts that need the keyboard (search / password fields). while one of
    // these is the pinned popout, the overlay grabs the keyboard the way an open
    // surface does and hands it back on close; the pointer-only popouts and
    // voice stay keyboardFocus None.
    readonly property var kbPopouts: ["clipboard", "link", "keyring", "sidebarLeft", "sidebarRight", "calendar"]
    property string prevPopout: ""
    onPopoutChanged: {
        if (kbPopouts.indexOf(prevPopout) >= 0 && kbPopouts.indexOf(popout) < 0)
            restoreFocus();
        // dismissing the keyring popout cancels the pending prompt (a no-op if the
        // daemon already cleared it via keyringHide).
        if (prevPopout === "keyring" && popout !== "keyring")
            Keyring.dismiss();
        prevPopout = popout;
    }

    function refresh() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    Component.onCompleted: {
        refresh();
        Vibrance.restore();
        Devices.probePanelBrightness();
        // re-arm the durable idle inhibitor for the persisted flag. on a
        // shell reload the external inhibitor is usually still up (lives
        // outside this process), so "start" = idempotent confirm; "stop"
        // clears a stray when Keep-Awake is off.
        root.syncCaffeine(Flags.keepAwake ? "start" : "stop");
        // re-arm the Lid Sleep override the same way: "start" holds it when
        // the user turned sleep-on-lid-close off, "stop" is a no-op otherwise.
        root.syncLidSleep(Flags.lidSleep ? "stop" : "start");
        // re-assert Game Mode if it persisted on. relogin brings Hyprland
        // up fresh from the lua config, so the compositor tuning has to be
        // re-applied (start is idempotent and preserves the saved WiFi
        // value). only "start", never "stop": a reload is expensive and the
        // desktop already sits in its normal config when game mode is off.
        if (Flags.gameMode)
            root.syncGameMode("start");
    }

    Binding {
        target: Notifs
        property: "dnd"
        value: Flags.dndActive
    }

    // pill weather units from the config: "auto" follows the locale. WeatherCore
    // (the shared base Weather.qml extends) is deliberately config-agnostic --
    // it only knows "" | "C" | "F" -- so the translation from Config's
    // "auto"/"celsius"/"fahrenheit" happens here, same as launcher/shell.qml's
    // equivalent Binding.
    Binding {
        target: Weather
        property: "unitOverride"
        value: Config.weatherUnit === "celsius" ? "C" : Config.weatherUnit === "fahrenheit" ? "F" : ""
    }

    PanelWindow {
        id: inhibitWin
        visible: Flags.keepAwake && Flags.keepAwakeScreen
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "pill-inhibit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; left: true }
        IdleInhibitor { window: inhibitWin; enabled: Flags.keepAwake && Flags.keepAwakeScreen }
    }

    // keyboard-return bounce. the pill overlay never unmaps, and dropping an
    // Exclusive grab on a mapped layer strands the keyboard (the window looks
    // active but can't type; focus dispatches don't recover it). this 1x1 helper
    // takes the grab and unmaps, which makes Hyprland hand the keyboard back.
    property bool kbBounce: false
    Timer {
        id: kbBounceTimer
        interval: 90
        onTriggered: root.kbBounce = false
    }
    PanelWindow {
        id: kbBounceWin
        visible: root.kbBounce
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "pill-kbbounce"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; left: true }
    }

    // in-shell polkit authentication agent: themed, names the exact
    // privileged command. Registers itself; nothing to gate on here.
    PolkitPrompt {}

    // Keep-Awake's durable hold lives outside the shell so it survives a
    // reload/restart: ryoku-cmd-caffeine owns hypridle, independent of our
    // lifetime. the Wayland IdleInhibitor above dies with the pill on every
    // respawn; this bridge keeps Keep-Awake unbroken across the swap. every
    // surface toggle just flips Flags.keepAwake.
    readonly property string caffeineScript: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/ryoku-cmd-caffeine"

    function syncCaffeine(action) {
        Spawn.spawn([root.caffeineScript, action]);
    }

    Connections {
        target: Flags
        function onKeepAwakeChanged() {
            root.syncCaffeine(Flags.keepAwake ? "start" : "stop");
        }
        function onKeepAwakeScreenChanged() {
            if (Flags.keepAwake)
                caffeineOptionSync.restart();
        }
    }

    // the scripts read their options from flags.json, so a re-apply waits out
    // Flags' atomic write instead of racing it and reading the value it is
    // replacing. the restart also folds a burst of taps into one re-apply.
    Timer {
        id: caffeineOptionSync
        interval: 250
        onTriggered: root.syncCaffeine("start")
    }

    KeepAwakeGuard {}

    // game mode's compositor + WiFi tuning lives outside the shell, same
    // shape as Keep-Awake. ryoku-cmd-game-mode drives hyprctl and
    // NetworkManager so the tuning survives a shell reload and re-applies
    // after a relogin. DND is the shell's own (handled in Flags); deck
    // toggle just flips Flags.gameMode.
    readonly property string gameModeScript: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/ryoku-cmd-game-mode"

    function syncGameMode(action) {
        Spawn.spawn([root.gameModeScript, action]);
    }

    Connections {
        target: Flags
        function onGameModeChanged() {
            root.syncGameMode(Flags.gameMode ? "start" : "stop");
        }
        function onGameModeVisualsChanged() { gameOptionSync.restart(); }
        function onGameModeTearingChanged() { gameOptionSync.restart(); }
        function onGameModeWifiChanged() { gameOptionSync.restart(); }
    }

    // same wait-for-the-write as caffeineOptionSync. reapply is a no-op unless
    // Game Mode is on; the DND option is applied by Flags itself.
    Timer {
        id: gameOptionSync
        interval: 250
        onTriggered: root.syncGameMode("reapply")
    }

    // Lid Sleep: on (default) leaves the kernel's lid behaviour alone. off
    // asks ryoku-cmd-lid-sleep to set hw.acpi.lid_switch_state=NONE, same
    // durable-outside-the-shell shape as Keep-Awake/Game-Mode above.
    readonly property string lidSleepScript: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/ryoku-cmd-lid-sleep"

    function syncLidSleep(action) {
        Spawn.spawn([root.lidSleepScript, action]);
    }

    Connections {
        target: Flags
        function onLidSleepChanged() {
            root.syncLidSleep(Flags.lidSleep ? "stop" : "start");
        }
    }

    // only these raw events change what the pill renders (per-monitor
    // active workspace, minimized toplevels, monitor hotplug). everything
    // else (window drags, resizes, title spam) MUST NOT trigger the triple
    // model refresh: three Hyprland IPC round-trips a pop.
    readonly property var refreshEvents: ({
        workspace: true, workspacev2: true,
        createworkspace: true, createworkspacev2: true,
        destroyworkspace: true, destroyworkspacev2: true,
        moveworkspace: true, moveworkspacev2: true,
        renameworkspace: true, activespecial: true,
        focusedmon: true, focusedmonv2: true,
        openwindow: true, closewindow: true,
        movewindow: true, movewindowv2: true,
        fullscreen: true,
        monitoradded: true, monitoraddedv2: true, monitorremoved: true
    })

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // a workspace switch fires several whitelisted events at once;
            // Qt.callLater dedups them to one refresh (three IPC calls) per turn.
            if (root.refreshEvents[event.name])
                Qt.callLater(root.refresh);
        }
    }

    // pulse the kbBounce helper so a dismissed keyboard popout hands the keyboard back.
    function restoreFocus() {
        root.kbBounce = true;
        kbBounceTimer.restart();
    }

    function peek(mon) {
        root.peekMon = root.peekMon === mon ? "" : mon;
    }

    // a stash install hitting a sudo/polkit prompt asks the deck to step
    // aside so the prompt (a window beneath our keyboard grab) takes focus
    // instead of landing behind the open deck.
    Connections {
        target: Stash
        function onAuthStepAside() { root.popout = ""; }
    }

    // pin/unpin an edge popout (mixer/power) on a monitor. re-issuing the
    // same one clears it. hover opens them on its own; this is the
    // IPC/keybind path.
    function togglePopout(mon, name) {
        if (root.popout === name && root.popoutMon === mon) {
            root.popout = "";
            return;
        }
        // unpin the old popout before moving the anchor: a pinned popout tracks
        // popoutCenter live, so writing the new centre first teleports the old
        // body along the bar instead of letting it melt where it opened.
        root.popout = "";
        root.popoutMon = mon;
        root.popoutCenter = -1;   // keybind/IPC: no owning icon, so centre on the bar
        root.popout = name;
    }

    // open a popout at a bar icon: record the icon's along-axis centre so the
    // blob grows from the icon on any bar edge.
    function togglePopoutAt(mon, name, center) {
        if (root.popout === name && root.popoutMon === mon) {
            root.popout = "";
            return;
        }
        root.popout = "";         // same unpin-first order as togglePopout
        root.popoutMon = mon;
        root.popoutCenter = center;
        root.popout = name;
    }

    // media hover popout: open at the module's centre; on unhover a short grace
    // lets the pointer cross the bar edge to the body, whose own hover latch
    // then holds the popout open for the transport buttons.
    Timer {
        id: hoverPopoutClose
        interval: 160
        onTriggered: { root.hoverPopout = ""; root.hoverPopoutMon = ""; }
    }
    function setHoverPopout(mon, name, center, hovered) {
        if (hovered) {
            hoverPopoutClose.stop();
            root.hoverPopoutCenter = center;
            root.hoverPopoutMon = mon;
            root.hoverPopout = name;
        } else if (root.hoverPopout === name && root.hoverPopoutMon === mon) {
            hoverPopoutClose.restart();
        }
    }

    IpcHandler {
        target: "pill"
        function mixer(mon: string): void { root.togglePopout(mon, "mixer"); }
        function calendar(mon: string): void { root.togglePopout(mon, "calendar"); }
        function power(mon: string): void { root.togglePopout(mon, "power"); }
        function link(mon: string): void { root.togglePopout(mon, "link"); }
        function inbox(mon: string): void { root.togglePopout(mon, "inbox"); }
        function battery(mon: string): void { root.togglePopout(mon, "battery"); }
        // status-cluster quick popouts (the compact hover panels; a keybind can
        // also pin one). distinct from the deep surfaces above; side bar only.
        function network(mon: string): void { root.togglePopout(mon, "network"); }
        function bluetooth(mon: string): void { root.togglePopout(mon, "bluetooth"); }
        function batteryPopout(mon: string): void { root.togglePopout(mon, "battery"); }
        function clipboard(mon: string): void { root.togglePopout(mon, "clipboard"); }
        function stash(mon: string): void {
            Config.sidebarLeftTab = "stash";
            Config.persist();
            root.sidebarLeftPane = "stash";
            root.popoutMon = mon;
            root.popout = "sidebarLeft";
        }
        // stash-send <file>: open the left sidebar's stash pane and jump straight
        // to its LocalSend picker, so the file manager can hand a file to the send
        // flow. sets the popout directly (not toggle) so it never closes it.
        function stashSend(mon: string, file: string): void {
            Config.sidebarLeftTab = "stash";
            Config.persist();
            root.sidebarLeftPane = "stash";
            root.popoutMon = mon;
            root.popout = "sidebarLeft";
            Stash.openSendPicker(file);
        }
        // deck-era names, repointed to the left stash sidebar (Super+D binds
        // and the file manager still call these).
        function toolkit(mon: string): void { root.togglePopout(mon, "sidebarLeft"); }
        function utilities(mon: string): void { root.togglePopout(mon, "sidebarLeft"); }
        function workspaces(mon: string): void { root.togglePopout(mon, "workspaces"); }
        function sidebarLeft(mon: string): void { root.togglePopout(mon, "sidebarLeft"); }
        function sidebarRight(mon: string): void { root.togglePopout(mon, "sidebarRight"); }
        function keyringPrompt(payload: string): void {
            Keyring.apply(payload);
            var m = Keyring.mon !== "" ? Keyring.mon
                : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
            root.popout = "";
            root.popoutMon = m;
            root.popoutCenter = -1;
            root.popout = "keyring";
        }
        function keyringHide(): void {
            // daemon-driven teardown (unlock resolved). clear() first so the
            // popout's dismiss (onPopoutChanged) can't cancel the resolved prompt.
            Keyring.clear();
            if (root.popout === "keyring")
                root.popout = "";
        }
        function voiceShow(mon: string): void { root.voiceOff = false; root.popout = ""; root.popoutMon = mon; root.popoutCenter = -1; root.popout = "voice"; }
        function voiceOff(mon: string): void { root.voiceOff = true; root.popout = ""; root.popoutMon = mon; root.popoutCenter = -1; root.popout = "voice"; }
        function voiceHide(): void { if (root.popout === "voice") root.popout = ""; }
        function peek(mon: string): void { root.peek(mon); }
        function hide(): void { root.popout = ""; }
        // toggle an enabled plugin's frame popout by id (leader menu / keybind).
        function pluginPopout(mon: string, id: string): void { root.togglePopout(mon, "plugin:" + id); }
        function backlight(pct: string): void { Devices.reportPanelBrightness(parseInt(pct, 10)); }
    }

    // The daemon writes surface commands to this socket to toggle pill surfaces
    // without spawning a `qs ipc call` client on the keybind hot path. The pill
    // is a persistent component, so the socket is up whenever the daemon needs
    // it; a miss makes the daemon fall back to the qs client.
    readonly property string pillSockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-pill.sock"

    // runPillCommand mirrors the IpcHandler above for the socket fast path:
    // "<fn> <mon> [arg]" runs the same surface toggle. Returns false on an
    // unknown command so the daemon falls back to the qs client.
    function runPillCommand(line) {
        var parts = line.trim().split(" ");
        var fn = parts[0];
        var mon = parts.length > 1 ? parts[1] : "";
        switch (fn) {
        case "battery": case "mixer": case "power":
            root.togglePopout(mon, fn); return true;
        case "network": case "bluetooth": case "calendar": case "clipboard": case "link": case "inbox": case "workspaces": case "sidebarLeft": case "sidebarRight":
            root.togglePopout(mon, fn); return true;
        case "toolkit": case "utilities":
            root.togglePopout(mon, "sidebarLeft"); return true;
        case "stash":
            Config.sidebarLeftTab = "stash"; Config.persist();
            root.sidebarLeftPane = "stash"; root.popoutMon = mon; root.popout = "sidebarLeft"; return true;
        case "batteryPopout":
            root.togglePopout(mon, "battery"); return true;
        case "pluginPopout":
            root.togglePopout(mon, "plugin:" + (parts.length > 2 ? parts[2] : ""));
            return true;
        case "backlight":
            Devices.reportPanelBrightness(parseInt(mon, 10)); return true;
        case "voiceShow":
            root.voiceOff = false; root.popout = ""; root.popoutMon = mon; root.popoutCenter = -1; root.popout = "voice"; return true;
        case "voiceOff":
            root.voiceOff = true; root.popout = ""; root.popoutMon = mon; root.popoutCenter = -1; root.popout = "voice"; return true;
        case "voiceHide":
            if (root.popout === "voice") root.popout = "";
            return true;
        case "peek":
            root.peek(mon); return true;
        case "hide":
            root.popout = ""; return true;
        default:
            return false;
        }
    }

    SocketServer {
        active: true
        path: root.pillSockPath
        handler: Socket {
            id: cmdSock
            parser: SplitParser {
                onRead: line => cmdSock.write((root.runPillCommand(line) ? "ok" : "err") + "\n")
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserve
            required property var modelData
            readonly property real s: (modelData ? modelData.height / 1080 : 1) * Math.max(0.7, Math.min(1.6, Config.fontScale))
            readonly property string barPos: Config.barEnabled ? (Config.barPosition === "bottom" ? "bottom" : "top") : ""
            readonly property bool barTop: barPos === "top"
            readonly property bool delos: Config.barStyle === "delos"
            readonly property string rEdge: delos ? IslandDock.edge : barPos
            // a TOP bar reserves the visible bar strip (frame edge + band, the
            // same numbers as the overlay's barVisibleH) so tiles tuck right
            // against it. bottom/left/right bars reserve their own edge in
            // sideReserve; with no island there is nothing else to reserve at
            // the top, so this window only maps for a top bar.
            readonly property real barBand: Config.barHeight * s
            readonly property real barVisibleH: Math.max(0, Config.effectiveFrameBorder - 50) + barBand
            readonly property real zone: delos ? Math.max(0, IslandDock.thickness) : barVisibleH

            screen: modelData
            visible: rEdge === "top"
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: zone
            aboveWindows: true

            anchors { top: true; left: true; right: true }
            implicitHeight: zone

            mask: emptyReserve
            Region { id: emptyReserve }
        }
    }

    // a bottom/left/right bar claims its own edge strip, independent of the
    // island reserve above (which keeps owning the top).
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: sideReserve
            required property var modelData
            readonly property real s: (modelData ? modelData.height / 1080 : 1) * Math.max(0.7, Math.min(1.6, Config.fontScale))
            readonly property string barPos: Config.barEnabled ? (Config.barPosition === "bottom" ? "bottom" : "top") : ""
            readonly property bool delos: Config.barStyle === "delos"
            readonly property string rEdge: delos ? IslandDock.edge : barPos
            readonly property bool active: rEdge === "bottom" || rEdge === "left" || rEdge === "right"
            // a vertical band needs room for stacked content; floor it at 30.
            readonly property real minBand: rEdge === "left" || rEdge === "right" ? 30 : 0
            readonly property real zone: delos ? Math.max(0, IslandDock.thickness) : (Math.max(0, Config.effectiveFrameBorder - 50) + Math.max(Config.barHeight, minBand) * s)

            screen: modelData
            visible: active
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: active ? zone : 0
            aboveWindows: true

            anchors {
                top: rEdge === "left" || rEdge === "right"
                bottom: rEdge !== "top"
                left: rEdge !== "right"
                right: rEdge !== "left"
            }
            implicitHeight: rEdge === "bottom" ? zone : 100
            implicitWidth: zone

            mask: emptySideReserve
            Region { id: emptySideReserve }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData
            readonly property real s: (modelData ? modelData.height / 1080 : 1) * Math.max(0.7, Math.min(1.6, Config.fontScale))

            // bar mode: the frame's chosen edge swells into a band carrying
            // the options (Bar.qml). inverted rect is oversized 50px (its
            // anchors.margins), so the on-screen edge is border - 50; the
            // bar adds `barBand` inside that.
            readonly property string barPos: !Config.barEnabled ? "" : (delos ? IslandDock.edge : (Config.barPosition === "bottom" ? "bottom" : "top"))
            readonly property bool barTop: barPos === "top"
            readonly property bool barBottom: barPos === "bottom"
            readonly property bool barLeft: barPos === "left"
            readonly property bool barRight: barPos === "right"
            readonly property bool barVertical: barLeft || barRight
            readonly property bool triptych: Config.barStyle === "triptych"
            readonly property bool delos: Config.barStyle === "delos"
            readonly property bool nacre: Config.barStyle === "nacre"
            readonly property bool inir: Config.barStyle === "inir"
            readonly property bool aurora: Config.barStyle === "aurora"
            readonly property bool angel: Config.barStyle === "angel"
            // inir/aurora/angel are flat frame-off bars ported from iNiR: the Bar
            // paints its own flush, full-width background (TUI / translucent glass /
            // brutalist) instead of riding the frame band, so the frame grows no
            // band under them and no lobes. They read as a flat edge-to-edge bar
            // and are meant for frame-off.
            readonly property bool flatBar: inir || aurora || angel
            // triptych and nacre both keep a hairline top edge and grow three
            // blob lobes under the module clusters, so the bar dips between them
            // (organic dips). the dips persist whether the frame is on or off --
            // the toggle strips only the screen border ring, never the bar top --
            // and a popout fuses into that persistent hairline, melting cleanly.
            readonly property bool triptychLobes: barTop && (triptych || nacre) && !monFullscreen
            readonly property real frameTopVisible: Math.max(0, Config.effectiveFrameBorder - 50)
            // a vertical band needs room for stacked content; floor it at 30.
            readonly property real barBand: Math.max(Config.barHeight, barVertical ? 30 : 0) * s
            readonly property real barVisibleH: frameTopVisible + barBand

            // the two sidebars: full-height panels that melt out of the left and
            // right frame edges (fullSpan), each fusing into the top and bottom
            // frame so a whole side swells open with no gap. the top/bottom gaps
            // become the content inset, so it clears a bar and the bottom frame.
            readonly property bool sidebarLeftOn: Config.sidebarLeftEnabled
            readonly property bool sidebarRightOn: Config.sidebarRightEnabled
            readonly property real sidebarW: Config.sidebarWidth * s
            readonly property real sidebarTopGap: (barTop ? barVisibleH : frameTopVisible) + 14 * s
            readonly property real sidebarBotGap: (barBottom ? barVisibleH : frameTopVisible) + 14 * s
            readonly property real sidebarCornerW: Config.sidebarCornerSize * s
            readonly property real sidebarCornerH: Config.sidebarCornerSize * s

            // drag-to-stash trigger: a thin masked band down the left frame edge
            // that opens the sidebar when a file is flung at the edge (a
            // HoverHandler is dead while a drag grabs the pointer, so this DropArea
            // catches it); the board's own DropArea takes the actual drop. Kept a
            // thin sliver inside Hyprland's gaps_out ring (18px) so it never reaches
            // window content: a corner-width band swallowed every click down the
            // whole left edge.
            readonly property real leftEdgeStripW: 12
            readonly property bool leftDragActive: overlay.sidebarLeftOn && !overlay.monFullscreen &&
                (leftEdgeDrop.containsDrag || sidebarLeftContent.dragActive)
            onLeftDragActiveChanged: if (overlay.leftDragActive) {
                Config.sidebarLeftTab = "stash";
                Config.persist();
                root.sidebarLeftPane = "stash";
            }

            // touch edge-swipe: a finger dragging in from the very left/right
            // edge opens that sidebar, for touchscreens with no mouse. wider
            // than leftEdgeStripW (a finger is far less precise than a
            // pointer) but still kept inside Hyprland's gaps_out ring (18px,
            // decoration.lua) so it can't swallow a touch meant for window
            // content just past the edge. the distance threshold (not the
            // strip width) is scaled by `s` -- it's a gesture-size judgment
            // call, not a fixed compositor gap.
            readonly property real edgeSwipeStripW: 16
            readonly property real edgeSwipeThreshold: 36 * s

            // a keyboard-needing popout (clipboard/link/keyring/deck/workspaces)
            // pinned on this monitor: grabs the keyboard for text entry.
            readonly property bool kbPopout: root.popoutMon === modelData.name
                && root.kbPopouts.indexOf(root.popout) >= 0
            readonly property bool modal: kbPopout

            // true once any undockable popout on this monitor has detached
            // into a floating island. A floating popout is meant to coexist
            // with using the rest of the desktop (like RecordHud/DelosIsland,
            // which never grab at all) rather than stay modal -- so the
            // click-away focus grab below must not hold onto input just
            // because root.popout is still set for bookkeeping (re-dock,
            // masking). Without this, hovering a sidebar corner elsewhere on
            // screen stopped registering until an unrelated click cleared
            // the grab.
            readonly property bool anyPopoutFloating: mixerPop.floating || powerPop.floating
                || networkPop.floating || batteryPop.floating || displayPop.floating
                || resourcesPop.floating || weatherPop.floating
                || netSpeedPop.floating || agentUsagePop.floating || windowInfoPop.floating
                || bluetoothPop.floating || calendarPop.floating || mediaPop.floating
                || clipboardPop.floating || inboxPop.floating

            // true when this monitor's visible workspace holds a fullscreen
            // window. Fullscreen owns the id -> fullscreen map (hyprctl-backed,
            // fork-proof); the monitor -> active workspace hop stays event-driven.
            readonly property bool monFullscreen: {
                var mons = Hyprland.monitors.values;
                for (var i = 0; i < mons.length; i++)
                    if (mons[i].name === modelData.name)
                        return mons[i].activeWorkspace ? (Fullscreen.byWs[mons[i].activeWorkspace.id] === true) : false;
                return false;
            }

            onMonFullscreenChanged: if (monFullscreen) {
                if (root.popoutMon === modelData.name) root.popout = "";
                if (root.peekMon === modelData.name) root.peekMon = "";
            }

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // None, not OnDemand: this layer is always mapped, so OnDemand would
            // hold the keyboard after a popout closes and a launched window can't type.
            WlrLayershell.keyboardFocus: kbPopout ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "pill"

            anchors { top: true; left: true; right: true; bottom: true }

            // recHud.dragging widens the mask to the whole surface: the island
            // clamps at the frame lips, so the pointer can slide off its rect
            // mid-drag; losing the region there kills the grab and the island
            // snaps home while the button is still held.
            mask: monFullscreen ? hiddenRegion
                : ((modal || recHud.dragging || delosIsland.dragging
                    || mixerPop.floatDragging || powerPop.floatDragging || networkPop.floatDragging
                    || batteryPop.floatDragging || displayPop.floatDragging
                    || resourcesPop.floatDragging || weatherPop.floatDragging || netSpeedPop.floatDragging
                    || agentUsagePop.floatDragging || windowInfoPop.floatDragging || bluetoothPop.floatDragging
                    || calendarPop.floatDragging || mediaPop.floatDragging || clipboardPop.floatDragging
                    || inboxPop.floatDragging) ? fullRegion : barRegion)

            // the bar band's input strip, per edge.
            readonly property real barMaskX: barRight ? width - barVisibleH : 0
            readonly property real barMaskY: barBottom ? height - barVisibleH : 0
            readonly property real barMaskW: barVertical ? barVisibleH : width
            readonly property real barMaskH: barVertical ? height : barVisibleH
            // true when (x, y) (overlay-window coords) falls on the bar's input
            // strip. the dismiss backdrop leaves every press here to the bar, so
            // the bar stays fully usable under a popout -- the way caelestia's
            // drawer region starts past the bar (x: bar.clampedWidth) and never
            // overlaps the taskbar with the dismiss surface.
            function inBarStrip(x, y) {
                return Config.barEnabled
                    && x >= barMaskX && x < barMaskX + barMaskW
                    && y >= barMaskY && y < barMaskY + barMaskH;
            }
            Region { id: hiddenRegion }
            Region {
                id: fullRegion
                width: overlay.width
                height: overlay.height
            }
            Region {
                id: barRegion
                // bar strip catches input for its options; the edge popouts
                // keep their hover triggers and bodies so mixer/power still open.
                // with a top bar the island drops out of the band, so the grab
                // extends over the panel (toast actions stay clickable); other
                // edges keep the island's own regions.
                x: overlay.barMaskX
                y: overlay.barMaskY
                width: (Config.barEnabled && !overlay.delos) ? overlay.barMaskW : 0
                height: (Config.barEnabled && !overlay.delos) ? overlay.barMaskH : 0
                Region { x: mixerPop.triggerX; y: mixerPop.triggerY; width: mixerPop.triggerW; height: mixerPop.triggerH }
                Region { x: mixerPop.maskX; y: mixerPop.maskY; width: mixerPop.maskW; height: mixerPop.maskH }
                Region { x: mixerPop.floatHudX; y: mixerPop.floatHudY; width: mixerPop.floatHudW; height: mixerPop.floatHudH }
                Region { x: powerPop.triggerX; y: powerPop.triggerY; width: powerPop.triggerW; height: powerPop.triggerH }
                Region { x: powerPop.maskX; y: powerPop.maskY; width: powerPop.maskW; height: powerPop.maskH }
                Region { x: powerPop.floatHudX; y: powerPop.floatHudY; width: powerPop.floatHudW; height: powerPop.floatHudH }
                Region { x: networkPop.maskX; y: networkPop.maskY; width: networkPop.maskW; height: networkPop.maskH }
                Region { x: networkPop.floatHudX; y: networkPop.floatHudY; width: networkPop.floatHudW; height: networkPop.floatHudH }
                Region { x: batteryPop.maskX; y: batteryPop.maskY; width: batteryPop.maskW; height: batteryPop.maskH }
                Region { x: batteryPop.floatHudX; y: batteryPop.floatHudY; width: batteryPop.floatHudW; height: batteryPop.floatHudH }
                Region { x: displayPop.maskX; y: displayPop.maskY; width: displayPop.maskW; height: displayPop.maskH }
                Region { x: displayPop.floatHudX; y: displayPop.floatHudY; width: displayPop.floatHudW; height: displayPop.floatHudH }
                Region { x: bluetoothPop.maskX; y: bluetoothPop.maskY; width: bluetoothPop.maskW; height: bluetoothPop.maskH }
                Region { x: bluetoothPop.floatHudX; y: bluetoothPop.floatHudY; width: bluetoothPop.floatHudW; height: bluetoothPop.floatHudH }
                Region { x: windowInfoPop.maskX; y: windowInfoPop.maskY; width: windowInfoPop.maskW; height: windowInfoPop.maskH }
                Region { x: windowInfoPop.floatHudX; y: windowInfoPop.floatHudY; width: windowInfoPop.floatHudW; height: windowInfoPop.floatHudH }
                Region { x: calendarPop.maskX; y: calendarPop.maskY; width: calendarPop.maskW; height: calendarPop.maskH }
                Region { x: calendarPop.floatHudX; y: calendarPop.floatHudY; width: calendarPop.floatHudW; height: calendarPop.floatHudH }
                Region { x: clipboardPop.maskX; y: clipboardPop.maskY; width: clipboardPop.maskW; height: clipboardPop.maskH }
                Region { x: clipboardPop.floatHudX; y: clipboardPop.floatHudY; width: clipboardPop.floatHudW; height: clipboardPop.floatHudH }
                Region { x: linkPop.maskX; y: linkPop.maskY; width: linkPop.maskW; height: linkPop.maskH }
                Region { x: inboxPop.maskX; y: inboxPop.maskY; width: inboxPop.maskW; height: inboxPop.maskH }
                Region { x: inboxPop.floatHudX; y: inboxPop.floatHudY; width: inboxPop.floatHudW; height: inboxPop.floatHudH }
                Region { x: voicePop.maskX; y: voicePop.maskY; width: voicePop.maskW; height: voicePop.maskH }
                Region { x: keyringPop.maskX; y: keyringPop.maskY; width: keyringPop.maskW; height: keyringPop.maskH }
                Region { x: workspacesPop.maskX; y: workspacesPop.maskY; width: workspacesPop.maskW; height: workspacesPop.maskH }
                Region { x: mediaPop.maskX; y: mediaPop.maskY; width: mediaPop.maskW; height: mediaPop.maskH }
                Region { x: mediaPop.floatHudX; y: mediaPop.floatHudY; width: mediaPop.floatHudW; height: mediaPop.floatHudH }
                Region { x: toastPop.maskX; y: toastPop.maskY; width: toastPop.maskW; height: toastPop.maskH }
                // the compact right-side popouts (net-speed, weather,
                // resources, agent-usage) used to be pure display with no
                // mask entry needed, but now all carry an undock button.
                Region { x: netSpeedPop.maskX; y: netSpeedPop.maskY; width: netSpeedPop.maskW; height: netSpeedPop.maskH }
                Region { x: netSpeedPop.floatHudX; y: netSpeedPop.floatHudY; width: netSpeedPop.floatHudW; height: netSpeedPop.floatHudH }
                Region { x: weatherPop.maskX; y: weatherPop.maskY; width: weatherPop.maskW; height: weatherPop.maskH }
                Region { x: weatherPop.floatHudX; y: weatherPop.floatHudY; width: weatherPop.floatHudW; height: weatherPop.floatHudH }
                Region { x: resourcesPop.maskX; y: resourcesPop.maskY; width: resourcesPop.maskW; height: resourcesPop.maskH }
                Region { x: resourcesPop.floatHudX; y: resourcesPop.floatHudY; width: resourcesPop.floatHudW; height: resourcesPop.floatHudH }
                Region { x: agentUsagePop.maskX; y: agentUsagePop.maskY; width: agentUsagePop.maskW; height: agentUsagePop.maskH }
                Region { x: agentUsagePop.floatHudX; y: agentUsagePop.floatHudY; width: agentUsagePop.floatHudW; height: agentUsagePop.floatHudH }
                Region { x: pluginPops.maskTrigX; y: pluginPops.maskTrigY; width: pluginPops.maskTrigW; height: pluginPops.maskTrigH }
                Region { x: pluginPops.maskBodyX; y: pluginPops.maskBodyY; width: pluginPops.maskBodyW; height: pluginPops.maskBodyH }
                Region { x: recHud.hudX; y: recHud.hudY; width: ((Recorder.active || Recorder.chooserOpen) && recHud.prog > 0.25) ? recHud.hudW : 0; height: ((Recorder.active || Recorder.chooserOpen) && recHud.prog > 0.25) ? recHud.hudH : 0 }
                Region { x: recHud.trigX; y: recHud.trigY; width: Recorder.active ? recHud.trigW : 0; height: Recorder.active ? recHud.trigH : 0 }
                Region { x: delosIsland.hudX; y: delosIsland.hudY; width: (overlay.delos && delosIsland.prog > 0.25) ? delosIsland.hudW : 0; height: (overlay.delos && delosIsland.prog > 0.25) ? delosIsland.hudH : 0 }
                Region { x: delosIsland.trigX; y: delosIsland.trigY; width: overlay.delos ? delosIsland.trigW : 0; height: overlay.delos ? delosIsland.trigH : 0 }
                Region { x: 0; y: 0; width: (overlay.sidebarLeftOn && !overlay.monFullscreen) ? overlay.sidebarCornerW : 0; height: (overlay.sidebarLeftOn && !overlay.monFullscreen) ? overlay.sidebarCornerH : 0 }
                Region { x: 0; y: 0; width: (overlay.sidebarLeftOn && !overlay.monFullscreen) ? overlay.leftEdgeStripW : 0; height: (overlay.sidebarLeftOn && !overlay.monFullscreen) ? overlay.height : 0 }
                Region { x: 0; y: 0; width: (overlay.sidebarLeftOn && !overlay.monFullscreen) ? overlay.edgeSwipeStripW : 0; height: (overlay.sidebarLeftOn && !overlay.monFullscreen) ? overlay.height : 0 }
                Region { x: sidebarLeftPop.maskX; y: sidebarLeftPop.maskY; width: sidebarLeftPop.maskW; height: sidebarLeftPop.maskH }
                Region { x: (overlay.width - overlay.sidebarCornerW); y: 0; width: (overlay.sidebarRightOn && !overlay.monFullscreen) ? overlay.sidebarCornerW : 0; height: (overlay.sidebarRightOn && !overlay.monFullscreen) ? overlay.sidebarCornerH : 0 }
                Region { x: (overlay.width - overlay.edgeSwipeStripW); y: 0; width: (overlay.sidebarRightOn && !overlay.monFullscreen) ? overlay.edgeSwipeStripW : 0; height: (overlay.sidebarRightOn && !overlay.monFullscreen) ? overlay.height : 0 }
                Region { x: sidebarRightPop.maskX; y: sidebarRightPop.maskY; width: sidebarRightPop.maskW; height: sidebarRightPop.maskH }
            }

            MouseArea {
                anchors.fill: parent
                enabled: overlay.modal
                acceptedButtons: Qt.AllButtons
                onPressed: (mouse) => {
                    // a press on the bar strip belongs to the bar (its icons take
                    // their own clicks, the band is inert), so it never dismisses.
                    // only a true backdrop press dismisses the modal popout.
                    if (overlay.inBarStrip(mouse.x, mouse.y)) return;
                    if (!overlay.kbPopout) return;
                    // sidebars are in kbPopouts (below), so this backdrop is
                    // "enabled" the whole time either is open. normally that's
                    // fine -- a press on the sidebar's own content should hit
                    // that content first (higher z) and never reach this
                    // backdrop at all. but for TOUCH specifically, a bare
                    // TapHandler (the toggle tiles, the tab-rail icons) does
                    // not reliably block this MouseArea's synthesized-mouse-
                    // from-touch press the way a MouseArea nested inside a
                    // MouseArea would (confirmed live: a tap that visibly
                    // toggled Tablet Mode or switched tabs ALSO fired this
                    // handler) -- while Calendar's day cells (MouseArea) and
                    // the notifications ListView (Flickable's own grab) do
                    // block it, which is why only those felt "safe." rather
                    // than trust "did something else already consume this,"
                    // check position directly against the open sidebar's own
                    // mask rect, which shell.qml already computes precisely.
                    if (root.popout === "sidebarLeft" &&
                        mouse.x >= sidebarLeftPop.maskX && mouse.x < sidebarLeftPop.maskX + sidebarLeftPop.maskW &&
                        mouse.y >= sidebarLeftPop.maskY && mouse.y < sidebarLeftPop.maskY + sidebarLeftPop.maskH)
                        return;
                    if (root.popout === "sidebarRight" &&
                        mouse.x >= sidebarRightPop.maskX && mouse.x < sidebarRightPop.maskX + sidebarRightPop.maskW &&
                        mouse.y >= sidebarRightPop.maskY && mouse.y < sidebarRightPop.maskY + sidebarRightPop.maskH)
                        return;
                    root.popout = "";
                }
            }

            FocusScope {
                id: focusScope
                anchors.fill: parent
                focus: overlay.kbPopout
                // whole shell hides while a window is fullscreen.
                visible: !overlay.monFullscreen

                Keys.onEscapePressed: if (overlay.kbPopout) root.popout = "";

                // frame and pill share one blob field, so the pill reads
                // as the frame swelling open at top-centre, not a bar on top.
                BlobGroup {
                    id: blobGroup
                    color: Config.matchWallpaper ? Wallust.surface : Config.surfaceColor
                    borderColor: Config.matchWallpaper ? Wallust.border : Config.lockedBorderColor
                    borderWidth: 1.5
                    smoothing: Config.frameSmoothing
                    shadowStrength: Config.shadowStrength
                    shadowSize: Config.shadowSize
                }

                BlobInvertedRect {
                    // rounded screen border, sits in Hyprland's gaps_out
                    // ring. oversized 50px so the outer edge clips
                    // off-screen and only the inner (window) edge shows;
                    // borders grow to keep the hole at gaps_out.
                    anchors.fill: parent
                    anchors.margins: -50
                    group: blobGroup
                    radius: overlay.nacre ? 0 : Config.frameRadius
                    borderTop: overlay.nacre ? Config.frameBorder : ((overlay.barTop && !overlay.triptych && !overlay.delos && !overlay.flatBar) ? (Config.effectiveFrameBorder + overlay.barBand) : Config.effectiveFrameBorder)
                    borderBottom: (overlay.barBottom && !overlay.delos && !overlay.flatBar) ? (Config.effectiveFrameBorder + overlay.barBand) : Config.effectiveFrameBorder
                    borderLeft: (overlay.barLeft && !overlay.delos) ? (Config.effectiveFrameBorder + overlay.barBand) : Config.effectiveFrameBorder
                    borderRight: (overlay.barRight && !overlay.delos) ? (Config.effectiveFrameBorder + overlay.barBand) : Config.effectiveFrameBorder
                    opacity: Config.frameOpacity
                    visible: !overlay.monFullscreen
                }

                // triptych lobes: fused into the hairline top edge under each
                // module cluster (the Bar exposes their rects), so the frame
                // dips between the three instead of one straight band.
                BlobRect {
                    group: blobGroup
                    visible: overlay.triptychLobes
                    x: topBar.x
                    y: topBar.y
                    implicitWidth: overlay.triptychLobes ? (topBar.leftX + topBar.leftW) : 0
                    implicitHeight: overlay.triptychLobes ? overlay.barVisibleH : 0
                    topLeftRadius: 0
                    topRightRadius: 0
                    bottomLeftRadius: 0
                    bottomRightRadius: Math.min(16 * overlay.s, overlay.barBand / 2)
                    deformScale: 0.000015
                    sinks: false
                }
                BlobRect {
                    group: blobGroup
                    visible: overlay.triptychLobes
                    x: topBar.x + topBar.centreX
                    y: topBar.y
                    implicitWidth: overlay.triptychLobes ? topBar.centreW : 0
                    implicitHeight: overlay.triptychLobes ? overlay.barVisibleH : 0
                    topLeftRadius: 0
                    topRightRadius: 0
                    bottomLeftRadius: Math.min(16 * overlay.s, overlay.barBand / 2)
                    bottomRightRadius: Math.min(16 * overlay.s, overlay.barBand / 2)
                    deformScale: 0.000015
                    sinks: false
                }
                BlobRect {
                    group: blobGroup
                    visible: overlay.triptychLobes
                    x: topBar.x + topBar.rightX
                    y: topBar.y
                    implicitWidth: overlay.triptychLobes ? (topBar.width - topBar.rightX) : 0
                    implicitHeight: overlay.triptychLobes ? overlay.barVisibleH : 0
                    topLeftRadius: 0
                    topRightRadius: 0
                    bottomLeftRadius: Math.min(16 * overlay.s, overlay.barBand / 2)
                    bottomRightRadius: 0
                    deformScale: 0.000015
                    sinks: false
                }

                // options ride the thickened frame top, drawn in the
                // frame's own scene so there's no separate program, no seam.
                Bar {
                    id: topBar
                    // the bar rides ABOVE the popouts: a popout blob fuses to the
                    // frame edge and grows inward through the band (Popout.qml),
                    // so the band strip must paint on top or the neck would hide
                    // the bar modules it grows from. content insets above the band,
                    // so the bar only ever covers a popout's neck, never its body.
                    z: 1
                    visible: Config.barEnabled && !overlay.monFullscreen && !overlay.delos
                    x: overlay.barMaskX
                    y: overlay.barMaskY
                    width: overlay.barMaskW
                    height: overlay.barMaskH
                    s: overlay.s
                    position: overlay.barPos
                    band: overlay.barBand
                    trayWindow: overlay
                    onPopoutRequested: (name, center) => root.togglePopoutAt(overlay.modelData.name, name, center)
                    onHoverPopoutRequested: (name, center, hovered) => root.setHoverPopout(overlay.modelData.name, name, center, hovered)
                }

                // mixer popout: on a side bar the volume status icon owns it --
                // hovering that icon opens the mixer at its centre; on a
                // top/bottom or absent bar it stays the left-centre frame
                // feature on the thin lip.
                UndockablePopout {
                    id: mixerPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "mixer" && root.popoutMon === overlay.modelData.name
                    openW: mixerContent.implicitWidth
                    openH: mixerContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    Mixer {
                        id: mixerContent
                        s: overlay.s
                        open: mixerPop.prog > 0.5
                    }

                    floatingContent: Component {
                        Mixer {
                            s: overlay.s
                            open: mixerPop.floating
                        }
                    }
                }

                // power popout: on a side bar it grows from the bar's inner
                // edge right at the power button; else the right-centre frame
                // feature.
                UndockablePopout {
                    id: powerPop
                    group: blobGroup
                    frameThickness: overlay.delos ? overlay.frameTopVisible : overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.delos ? "top" : overlay.barPos
                    align: overlay.delos ? "end" : "center"
                    alongCenter: overlay.delos ? -1 : root.popoutCenter
                    hoverOpen: false
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "power" && root.popoutMon === overlay.modelData.name
                    openW: powerContent.implicitWidth
                    openH: powerContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    PowerPanel {
                        id: powerContent
                        s: overlay.s
                        open: powerPop.prog > 0.5
                        heroTopLeftRadius: powerPop.contentTopLeftRadius
                        heroTopRightRadius: powerPop.contentTopRightRadius
                        onCloseRequested: { powerPop.floating = false; root.popout = ""; }
                    }

                    floatingContent: Component {
                        PowerPanel {
                            s: overlay.s
                            open: powerPop.floating
                            onCloseRequested: { powerPop.floating = false; root.popout = ""; }
                        }
                    }
                }

                // status-icon popouts (side bar only): each owned by its status
                // cluster icon -- hovering the icon opens it at the icon's centre,
                // fused to the bar like the mixer. the deep surfaces (Link,
                // battery) stay the click target for the full view.
                UndockablePopout {
                    id: networkPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "network" && root.popoutMon === overlay.modelData.name
                    openW: netContent.implicitWidth
                    openH: netContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    NetworkPopout {
                        id: netContent
                        s: overlay.s
                        open: networkPop.prog > 0.5
                    }

                    floatingContent: Component {
                        NetworkPopout {
                            s: overlay.s
                            open: networkPop.floating
                        }
                    }
                }

                UndockablePopout {
                    id: batteryPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "battery" && root.popoutMon === overlay.modelData.name
                    openW: batContent.implicitWidth
                    openH: batContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    BatteryPopout {
                        id: batContent
                        s: overlay.s
                        open: batteryPop.prog > 0.5
                    }

                    floatingContent: Component {
                        BatteryPopout {
                            s: overlay.s
                            open: batteryPop.floating
                        }
                    }
                }

                // display popout: opened from the bar's display module (next
                // to volume) -- laptop panel backlight, screen vibrance, and
                // any external ddc monitor's brightness.
                UndockablePopout {
                    id: displayPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "display" && root.popoutMon === overlay.modelData.name
                    openW: displayContent.implicitWidth
                    openH: displayContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    DisplayPopout {
                        id: displayContent
                        s: overlay.s
                        open: displayPop.prog > 0.5
                    }

                    floatingContent: Component {
                        DisplayPopout {
                            s: overlay.s
                            open: displayPop.floating
                        }
                    }
                }

                // resources popout: opened from the Nacre stats module, the CPU /
                // memory / temp readout grows from the bar edge at the module.
                UndockablePopout {
                    id: resourcesPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "resources" && root.popoutMon === overlay.modelData.name
                    openW: resContent.implicitWidth
                    openH: resContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    ResourcesPopout {
                        id: resContent
                        s: overlay.s
                        open: resourcesPop.prog > 0.5
                    }

                    floatingContent: Component {
                        ResourcesPopout {
                            s: overlay.s
                            open: resourcesPop.floating
                        }
                    }
                }

                // weather popout: opened from the bar's weather module, the
                // current reading + hourly strip + daily forecast grows from
                // the bar edge at the module.
                UndockablePopout {
                    id: weatherPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "weather" && root.popoutMon === overlay.modelData.name
                    openW: wxContent.implicitWidth
                    openH: wxContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    WeatherPopout {
                        id: wxContent
                        s: overlay.s
                        open: weatherPop.prog > 0.5
                    }

                    floatingContent: Component {
                        WeatherPopout {
                            s: overlay.s
                            open: weatherPop.floating
                        }
                    }
                }

                // net-speed popout: opened from the bar's net-speed module, the
                // download / upload readout grows from the bar edge at the module.
                UndockablePopout {
                    id: netSpeedPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "netspeed" && root.popoutMon === overlay.modelData.name
                    openW: netSpeedContent.implicitWidth
                    openH: netSpeedContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    NetSpeedPopout {
                        id: netSpeedContent
                        s: overlay.s
                        open: netSpeedPop.prog > 0.5
                    }

                    floatingContent: Component {
                        NetSpeedPopout {
                            s: overlay.s
                            open: netSpeedPop.floating
                        }
                    }
                }

                // agent-usage popout: opened from the bar's agent-usage module,
                // Claude Code's session/weekly rate-limit percentages grow from
                // the bar edge at the module.
                UndockablePopout {
                    id: agentUsagePop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "agentusage" && root.popoutMon === overlay.modelData.name
                    openW: agentUsageContent.implicitWidth
                    openH: agentUsageContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    AgentUsagePopout {
                        id: agentUsageContent
                        s: overlay.s
                        open: agentUsagePop.prog > 0.5
                    }

                    floatingContent: Component {
                        AgentUsagePopout {
                            s: overlay.s
                            open: agentUsagePop.floating
                        }
                    }
                }

                // window-info popout: opened from the bar's title module, the
                // focused window's class/workspace/geometry and the process
                // behind it grow from the bar edge at the title.
                UndockablePopout {
                    id: windowInfoPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "windowinfo" && root.popoutMon === overlay.modelData.name
                    openW: windowInfoContent.implicitWidth
                    openH: windowInfoContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    WindowInfoPopout {
                        id: windowInfoContent
                        s: overlay.s
                        open: windowInfoPop.prog > 0.5
                    }

                    floatingContent: Component {
                        WindowInfoPopout {
                            s: overlay.s
                            open: windowInfoPop.floating
                        }
                    }
                }

                UndockablePopout {
                    id: bluetoothPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "bluetooth" && root.popoutMon === overlay.modelData.name
                    openW: btContent.implicitWidth
                    openH: btContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    BluetoothPopout {
                        id: btContent
                        s: overlay.s
                        open: bluetoothPop.prog > 0.5
                    }

                    floatingContent: Component {
                        BluetoothPopout {
                            s: overlay.s
                            open: bluetoothPop.floating
                        }
                    }
                }

                // calendar popout: opened from the clock module on the bar, the
                // month calendar grows from the bar edge at the clock.
                UndockablePopout {
                    id: calendarPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "calendar" && root.popoutMon === overlay.modelData.name
                    openW: calContent.implicitWidth
                    openH: calContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    CalendarPopout {
                        id: calContent
                        s: overlay.s
                        open: calendarPop.prog > 0.5
                    }

                    floatingContent: Component {
                        CalendarPopout {
                            s: overlay.s
                            open: calendarPop.floating
                        }
                    }
                }

                // media hover popout: hovering the now-playing module grows a
                // compact transport (elapsed line + prev/play/next) from the bar
                // edge at the module; the body's hover latch keeps it open for
                // the buttons. gated off while a clicked popout is up.
                UndockablePopout {
                    id: mediaPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    closeDelay: 140  // hover-intent: crossing the border rim never flickers it shut
                    alongCenter: root.hoverPopoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen && (root.popout === "" || overlay.anyPopoutFloating)
                    triggerHovered: root.hoverPopout === "media" && root.hoverPopoutMon === overlay.modelData.name
                    openW: mediaContent.implicitWidth
                    openH: mediaContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand

                    MediaPopout {
                        id: mediaContent
                        s: overlay.s
                        open: mediaPop.prog > 0.5
                    }

                    floatingContent: Component {
                        MediaPopout {
                            s: overlay.s
                            open: mediaPop.floating
                        }
                    }
                }

                // clipboard popout: Super+V grows the clipboard search/history
                // from the bar edge. a keyboard popout (see kbPopouts).
                UndockablePopout {
                    id: clipboardPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "clipboard" && root.popoutMon === overlay.modelData.name
                    openW: clipContent.implicitWidth
                    openH: clipContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    ClipboardPopout {
                        id: clipContent
                        s: overlay.s
                        open: clipboardPop.prog > 0.5
                        onCloseRequested: { clipboardPop.floating = false; root.popout = ""; }
                    }

                    floatingContent: Component {
                        ClipboardPopout {
                            s: overlay.s
                            open: clipboardPop.floating
                            onCloseRequested: { clipboardPop.floating = false; root.popout = ""; }
                        }
                    }
                }

                // link popout: the deep wifi/bluetooth surface, from the bar
                // edge. a keyboard popout (wifi password).
                Popout {
                    id: linkPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "link" && root.popoutMon === overlay.modelData.name
                    openW: linkContent.implicitWidth
                    openH: linkContent.implicitHeight

                    LinkPopout {
                        id: linkContent
                        s: overlay.s
                        open: linkPop.prog > 0.5
                        onCloseRequested: root.popout = ""
                    }
                }

                // inbox popout: the notification centre (the bell), from the bar
                // edge. pointer-only, dismisses via the focus grab.
                UndockablePopout {
                    id: inboxPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "inbox" && root.popoutMon === overlay.modelData.name
                    openW: inboxContent.implicitWidth
                    openH: inboxContent.implicitHeight
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                    onCloseRequested: root.popout = ""

                    InboxPopout {
                        id: inboxContent
                        s: overlay.s
                        open: inboxPop.prog > 0.5
                        onCloseRequested: { inboxPop.floating = false; root.popout = ""; }
                    }

                    floatingContent: Component {
                        InboxPopout {
                            s: overlay.s
                            open: inboxPop.floating
                            onCloseRequested: { inboxPop.floating = false; root.popout = ""; }
                        }
                    }
                }

                // notification toasts: grow from the bar edge at the bell (like
                // the inbox), auto-open while a popup is live and melt shut when
                // it expires. clicking opens the full inbox at the bell. defers
                // to any clicked popout so it never fights the inbox; hidden on
                // fullscreen and when the bar is off (no bell to grow from).
                Popout {
                    id: toastPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    align: "end"
                    hoverOpen: false
                    s: overlay.s
                    active: Config.barEnabled && !overlay.monFullscreen && (root.popout === "" || overlay.anyPopoutFloating)
                    pinned: Notifs.popups.length > 0
                    openW: toastContent.implicitWidth
                    openH: toastContent.implicitHeight

                    ToastPopout {
                        id: toastContent
                        s: overlay.s
                        open: toastPop.prog > 0.5
                        onOpenCenter: root.togglePopoutAt(overlay.modelData.name, "inbox", topBar.bellCenter)
                    }
                }


                // voice popout: the dictation overlay. grabs nothing (excluded
                // from the focus grab below) so dictation lands in the focused app.
                Popout {
                    id: voicePop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "voice" && root.popoutMon === overlay.modelData.name
                    openW: voiceContent.implicitWidth
                    openH: voiceContent.implicitHeight

                    VoicePopout {
                        id: voiceContent
                        s: overlay.s
                        off: root.voiceOff
                        open: voicePop.prog > 0.5
                        onCloseRequested: root.popout = ""
                    }
                }

                // keyring popout: the secret-service password prompt. a keyboard
                // popout; dismissing it cancels the prompt (onPopoutChanged).
                Popout {
                    id: keyringPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "keyring" && root.popoutMon === overlay.modelData.name
                    openW: keyringContent.implicitWidth
                    openH: keyringContent.implicitHeight

                    KeyringPopout {
                        id: keyringContent
                        s: overlay.s
                        open: keyringPop.prog > 0.5
                        onCloseRequested: root.popout = ""
                    }
                }

                // workspaces popout (Super+Tab): the switcher, from the bar edge.
                // pointer-only (drag is hand-tracked inside the surface).
                Popout {
                    id: workspacesPop
                    group: blobGroup
                    frameThickness: overlay.barVisibleH
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: overlay.barPos
                    hoverOpen: false
                    alongCenter: root.popoutCenter
                    s: overlay.s
                    active: !overlay.monFullscreen
                    pinned: root.popout === "workspaces" && root.popoutMon === overlay.modelData.name
                    openW: workspacesContent.implicitWidth
                    openH: workspacesContent.implicitHeight

                    WorkspacesPopout {
                        id: workspacesContent
                        s: overlay.s
                        screenName: overlay.modelData.name
                        open: workspacesPop.prog > 0.5
                        onCloseRequested: root.popout = ""
                    }
                }

                // LEFT sidebar (Stash): a corner hotspot at the top-left plus
                // the panel that melts out of the left edge. the corner carries
                // only a HoverHandler (clickless) so a bar click falls through; a
                // deliberate hover arms it, or a click when clickless is off.
                Item {
                    id: sidebarLeftCorner
                    z: 3
                    visible: overlay.sidebarLeftOn && !overlay.monFullscreen
                    x: 0
                    y: 0
                    width: overlay.sidebarCornerW
                    height: overlay.sidebarCornerH
                    property bool armed: false
                    onVisibleChanged: if (!visible) armed = false
                    // the pointer must reach the very corner (where it clamps when
                    // flung there), not just enter the region, so grazing the top
                    // frame near the corner never arms the sidebar.
                    readonly property real reach: 6 * overlay.s
                    readonly property bool atCorner: leftHov.hovered &&
                        leftHov.point.position.x <= sidebarLeftCorner.reach &&
                        leftHov.point.position.y <= sidebarLeftCorner.reach
                    onAtCornerChanged: {
                        if (atCorner) sidebarLeftIntent.restart();
                        else { sidebarLeftIntent.stop(); sidebarLeftCorner.armed = false; }
                    }
                    Timer { id: sidebarLeftIntent; interval: 150; onTriggered: sidebarLeftCorner.armed = true }
                    HoverHandler { id: leftHov; enabled: Config.sidebarClickless }
                    TapHandler {
                        enabled: !Config.sidebarClickless
                        onTapped: root.togglePopout(overlay.modelData.name, "sidebarLeft")
                    }
                }
                // drag intake down the whole left frame edge + corner: a file
                // dragged here opens the sidebar so the stash board is there to
                // drop onto (a HoverHandler is dead during a grab). the board's
                // own DropArea takes drops over it; this catches the edge itself.
                DropArea {
                    id: leftEdgeDrop
                    x: 0
                    y: 0
                    width: (overlay.sidebarLeftOn && !overlay.monFullscreen) ? overlay.leftEdgeStripW : 0
                    height: (overlay.sidebarLeftOn && !overlay.monFullscreen) ? overlay.height : 0
                    onDropped: (drop) => { for (var i = 0; i < drop.urls.length; i++) Stash.addUrl(drop.urls[i]); drop.accept(); }
                }
                // touch edge-swipe: a finger dragging in from anywhere down the
                // left edge opens this sidebar, same open call the corner tap
                // and IPC path already use. acceptedDevices excludes mouse/
                // trackpad, so an ordinary pointer drag at the edge (a window
                // resize, a trackpad workspace swipe) can never trip it -- only
                // a genuine touch can. fires once the finger crosses
                // edgeSwipeThreshold, not on release, so it reads as an
                // immediate reveal rather than a laggy gesture.
                Item {
                    id: sidebarLeftSwipe
                    visible: overlay.sidebarLeftOn && !overlay.monFullscreen
                    x: 0
                    y: 0
                    width: overlay.edgeSwipeStripW
                    height: overlay.height
                    property bool triggered: false
                    DragHandler {
                        target: null
                        acceptedDevices: PointerDevice.TouchScreen
                        onActiveChanged: if (active) sidebarLeftSwipe.triggered = false
                        onTranslationChanged: {
                            if (!active || sidebarLeftSwipe.triggered || translation.x < overlay.edgeSwipeThreshold)
                                return;
                            sidebarLeftSwipe.triggered = true;
                            if (!(root.popout === "sidebarLeft" && root.popoutMon === overlay.modelData.name))
                                root.togglePopout(overlay.modelData.name, "sidebarLeft");
                        }
                    }
                }
                // the bar rides above every popout's body (topBar: z 1, see the
                // comment there), which for most popouts only ever covers their
                // thin neck -- but a full-span sidebar's body runs right through
                // the bar's own strip, so wherever the two overlap the bar wins
                // the pointer and the sidebar's own body/edgeGap HoverHandlers
                // underneath never see it, dropping `hovered` and closing the
                // sidebar out from under a pointer sitting on/around a bar icon
                // (e.g. power) even though it's still over the open panel. the
                // corner hotspot (z 3) compounds it: its own hit square
                // (sidebarCornerSize, ~34px scaled) is much bigger than the
                // tight sub-zone that actually arms it (reach, ~6px scaled), so
                // its z 3 alone shadows everything underneath across that whole
                // outer ring too, not just its tight core.
                // covers 0..sidebarTopGap: the same inset SidebarFeatures/System
                // give their own content (topInset) to clear the bar, so this
                // band never overlaps a real interactive element underneath --
                // z 4 (above the corner) would otherwise steal hover from the
                // sidebar's own buttons/icons (killing their cursor/glow) if it
                // reached any further down, which is why this does NOT just
                // blanket the whole column. hover-only, invisible, and gated to
                // matter only once already open, so it can never be what opens
                // the sidebar fresh, and the corner's own arm/open bookkeeping
                // underneath is no longer needed by the time it's live.
                Item {
                    id: sidebarLeftBarGap
                    z: 4
                    x: 0
                    y: 0
                    width: sidebarLeftPop.maskX + sidebarLeftPop.maskW
                    height: overlay.sidebarTopGap
                    HoverHandler { id: sidebarLeftBarGapHH; enabled: sidebarLeftPop.heldOpen }
                }
                Popout {
                    id: sidebarLeftPop
                    group: blobGroup
                    frameThickness: overlay.frameTopVisible
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: "left"
                    hoverOpen: false
                    closeDelay: 300
                    s: overlay.s
                    active: overlay.sidebarLeftOn && !overlay.monFullscreen && (root.popout === "" || root.popout === "sidebarLeft" || overlay.anyPopoutFloating)
                    triggerHovered: (Config.sidebarClickless && sidebarLeftCorner.armed) || overlay.leftDragActive
                    extraHold: sidebarLeftBarGapHH.hovered
                    pinned: root.popout === "sidebarLeft" && root.popoutMon === overlay.modelData.name
                    fullSpan: true
                    openW: overlay.sidebarW
                    openH: overlay.height

                    Sidebar {
                        id: sidebarLeftContent
                        s: overlay.s
                        topInset: overlay.sidebarTopGap
                        botInset: overlay.sidebarBotGap
                        open: sidebarLeftPop.prog > 0.5
                        panes: Config.sidebarLeftPanes
                        pane: root.sidebarLeftPane
                        onPaneSelected: (k) => root.sidebarLeftPane = k
                    }
                }

                // RIGHT sidebar (System): mirror on the top-right corner + edge.
                Item {
                    id: sidebarRightCorner
                    z: 3
                    visible: overlay.sidebarRightOn && !overlay.monFullscreen
                    x: overlay.width - overlay.sidebarCornerW
                    y: 0
                    width: overlay.sidebarCornerW
                    height: overlay.sidebarCornerH
                    property bool armed: false
                    onVisibleChanged: if (!visible) armed = false
                    // mirror of the left: only the extreme top-right corner arms it.
                    readonly property real reach: 6 * overlay.s
                    readonly property bool atCorner: rightHov.hovered &&
                        rightHov.point.position.x >= (sidebarRightCorner.width - sidebarRightCorner.reach) &&
                        rightHov.point.position.y <= sidebarRightCorner.reach
                    onAtCornerChanged: {
                        if (atCorner) sidebarRightIntent.restart();
                        else { sidebarRightIntent.stop(); sidebarRightCorner.armed = false; }
                    }
                    Timer { id: sidebarRightIntent; interval: 150; onTriggered: sidebarRightCorner.armed = true }
                    HoverHandler { id: rightHov; enabled: Config.sidebarClickless }
                    TapHandler {
                        enabled: !Config.sidebarClickless
                        onTapped: root.togglePopout(overlay.modelData.name, "sidebarRight")
                    }
                }
                // touch edge-swipe: mirror of sidebarLeftSwipe above, on the
                // right edge (translation.x negative = dragging inward/left).
                Item {
                    id: sidebarRightSwipe
                    visible: overlay.sidebarRightOn && !overlay.monFullscreen
                    x: overlay.width - overlay.edgeSwipeStripW
                    y: 0
                    width: overlay.edgeSwipeStripW
                    height: overlay.height
                    property bool triggered: false
                    DragHandler {
                        target: null
                        acceptedDevices: PointerDevice.TouchScreen
                        onActiveChanged: if (active) sidebarRightSwipe.triggered = false
                        onTranslationChanged: {
                            if (!active || sidebarRightSwipe.triggered || translation.x > -overlay.edgeSwipeThreshold)
                                return;
                            sidebarRightSwipe.triggered = true;
                            if (!(root.popout === "sidebarRight" && root.popoutMon === overlay.modelData.name))
                                root.togglePopout(overlay.modelData.name, "sidebarRight");
                        }
                    }
                }
                // mirror of sidebarLeftBarGap above -- see that comment for why
                // this is needed at all.
                Item {
                    id: sidebarRightBarGap
                    z: 4
                    x: sidebarRightPop.maskX
                    y: 0
                    width: overlay.width - x
                    height: overlay.sidebarTopGap
                    HoverHandler { id: sidebarRightBarGapHH; enabled: sidebarRightPop.heldOpen }
                }
                Popout {
                    id: sidebarRightPop
                    group: blobGroup
                    frameThickness: overlay.frameTopVisible
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    edge: "right"
                    hoverOpen: false
                    closeDelay: 300
                    s: overlay.s
                    active: overlay.sidebarRightOn && !overlay.monFullscreen && (root.popout === "" || root.popout === "sidebarRight" || overlay.anyPopoutFloating)
                    triggerHovered: Config.sidebarClickless && sidebarRightCorner.armed
                    extraHold: sidebarRightBarGapHH.hovered
                    pinned: root.popout === "sidebarRight" && root.popoutMon === overlay.modelData.name
                    fullSpan: true
                    openW: overlay.sidebarW
                    openH: overlay.height

                    SidebarSystem {
                        s: overlay.s
                        topInset: overlay.sidebarTopGap
                        botInset: overlay.sidebarBotGap
                        open: sidebarRightPop.prog > 0.5
                        panes: Config.sidebarRightPanes
                        pane: root.sidebarRightPane
                        onPaneSelected: (k) => root.sidebarRightPane = k
                        onDismiss: { if (root.popout === "sidebarRight" && root.popoutMon === overlay.modelData.name) root.popout = ""; }
                        onClipboardRequested: root.togglePopout(overlay.modelData.name, "clipboard")
                    }
                }

                HyprlandFocusGrab {
                    active: root.popout !== "" && root.popoutMon === overlay.modelData.name && !overlay.kbPopout && root.popout !== "voice" && !overlay.anyPopoutFloating
                    windows: [overlay]
                    onCleared: if (root.popoutMon === overlay.modelData.name) root.popout = ""
                }

                // plugin frame popouts: every enabled plugin whose host is
                // a frame popout, fused into the same blob field as Mixer/Power.
                PluginPopouts {
                    id: pluginPops
                    group: blobGroup
                    s: overlay.s
                    active: !overlay.monFullscreen
                    frameThickness: 16
                    radius: Config.frameRadius
                    smoothing: Config.frameSmoothing
                    pinnedId: (root.popoutMon === overlay.modelData.name && root.popout.indexOf("plugin:") === 0)
                              ? root.popout.substring(7) : ""
                    onUnpinRequested: {
                        if (root.popout.indexOf("plugin:") === 0 && root.popoutMon === overlay.modelData.name)
                            root.popout = "";
                    }
                }

                RecordHud {
                    id: recHud
                    group: blobGroup
                    s: overlay.s
                    smoothing: Config.frameSmoothing
                    barEdge: (Config.barEnabled && !overlay.monFullscreen) ? overlay.barPos : ""
                    barBand: overlay.barBand
                }

                DelosIsland {
                    id: delosIsland
                    group: blobGroup
                    s: overlay.s
                    smoothing: Config.frameSmoothing
                    active: overlay.delos && Config.barEnabled && !overlay.monFullscreen
                    trayWindow: overlay
                    onPopoutRequested: (name) => root.togglePopoutAt(overlay.modelData.name, name, delosIsland.alongCentre)
                    onHoverPopoutRequested: (name, hovered) => root.setHoverPopout(overlay.modelData.name, name, delosIsland.alongCentre, hovered)
                }

            }
        }
    }

    // volume / brightness OSD, re-homed from the floating pill into its own
    // small bottom-centre layer window, just above the bar.
    Variants {
        model: Quickshell.screens
        OsdWindow {}
    }

    // persistent region-capture boundary shown while a region recording runs.
    Variants {
        model: Quickshell.screens
        RegionOverlay {}
    }

    // the self-view is a recording companion: when the last capture stops, clear
    // it so it does not linger. a plain mirror toggled on with no recording just
    // stays until toggled off (no active transition to clear it).
    Connections {
        target: Recorder
        function onActiveChanged() {
            if (!Recorder.active)
                Camera.active = false;
        }
    }

    // draggable, shaped webcam bubble; stays across workspaces, captured by the recorder.
    Variants {
        model: Quickshell.screens
        CameraOverlay {}
    }

}
