pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Singletons"

// Draggable recording control that lives in the frame's blob field. At rest it
// is fused to a frame edge; grab the 6-dot handle to pull it into a floating
// island. As it nears an edge, the island and a matching frame bump reach for
// each other and merge; let go and it drifts to the nearest edge. On a side
// edge it turns vertical. Hide tucks it to a small nub that hovering pops back
// out. It melts into the frame when recording ends. Nothing snaps.
//
// The layout / drag / blob geometry lives in FloatingIsland; this file only
// adds the recorder-specific show/hide logic, content, and audio toggles.
Item {
    id: hud

    required property var group
    property real s: 1
    property real radius: 17 * s
    property real smoothing: 30
    property string barEdge: ""
    property real barBand: 0

    anchors.fill: parent

    property bool hidden: false
    Binding { target: island; property: "hidden"; value: hud.hidden }

    // --- reveal + melt -------------------------------------------------------
    property bool revealHeld: false
    readonly property bool revealed: island.bodyHovered || island.nubRevealed
    readonly property bool tucked:   hud.hidden && !hud.revealHeld
    onRevealedChanged: {
        if (hud.revealed) { revealGrace.stop(); hud.revealHeld = true; }
        else revealGrace.restart();
    }
    Timer { id: revealGrace; interval: 260; onTriggered: hud.revealHeld = false }

    readonly property real nubProg: 0.14
    readonly property real wantProg: {
        if (Recorder.anyActive) return (!hud.hidden || hud.revealHeld) ? 1 : hud.nubProg;
        return (Recorder.chooserOpen || hud.starting) ? 1 : 0;
    }
    property real prog: hud.wantProg
    Behavior on prog { NumberAnimation { duration: island.meltDur; easing.type: Easing.InOutCubic } }
    readonly property bool live: hud.prog > 0.002
    visible: hud.live

    Binding { target: island; property: "prog"; value: hud.prog }
    Binding { target: island; property: "live"; value: hud.live }

    // --- chooser state -------------------------------------------------------
    property bool starting: false
    property bool optDesktopAudio: false
    property bool optMic: false
    function recordArgs() {
        var a = [];
        if (hud.optDesktopAudio) a.push("--with-desktop-audio");
        if (hud.optMic) a.push("--with-microphone-audio");
        return a;
    }
    function startQuick() {
        Recorder.chooserOpen = false;
        if (Recorder.regionGeom !== "") {
            var a = ["--region", "--geometry", Recorder.regionGeom];
            if (hud.optDesktopAudio) a.push("--with-desktop-audio");
            if (hud.optMic) a.push("--with-microphone-audio");
            Recorder.start(a);
        } else {
            hud.starting = true;
            quickTimer.restart();
        }
    }
    Timer { id: quickTimer; interval: 420; onTriggered: { Recorder.start(hud.recordArgs()); hud.starting = false; } }
    function launchRyomotion() {
        Recorder.chooserOpen = false;
        Spawn.spawn(["sh", "-c",
            "command -v ryomotion >/dev/null 2>&1 && exec ryomotion --edit || notify-send 'Ryomotion' 'Not installed yet'"]);
    }
    function startStudio() {
        Recorder.chooserOpen = false;
        Recorder.startStudio(hud.optDesktopAudio, hud.optMic, Recorder.regionGeom);
    }

    // 6-dot drag handle, shared by the active-recording and chooser layouts.
    component GripDots: Item {
        id: grip
        property real s: 1
        width: 16 * grip.s
        height: 20 * grip.s
        Grid {
            anchors.centerIn: parent
            columns: 2
            rowSpacing: 3 * grip.s
            columnSpacing: 3 * grip.s
            Repeater {
                model: 6
                Rectangle {
                    width: 3 * grip.s
                    height: 3 * grip.s
                    radius: width / 2
                    color: gripHov.hovered ? Theme.cream : Theme.subtle
                }
            }
        }
        HoverHandler { id: gripHov; cursorShape: Qt.SizeAllCursor }
    }

    // labelled action tile for the chooser (icon + short caption).
    component Action: Rectangle {
        id: act
        property real s: 1
        property string glyph: ""
        property string label: ""
        property color tint: Theme.cream
        property bool primary: false
        signal tapped()
        implicitWidth: aRow.implicitWidth + 14 * act.s
        implicitHeight: 26 * act.s
        radius: 7 * act.s
        color: aHov.hovered ? Theme.frameBg
            : act.primary ? Qt.rgba(Theme.vermLit.r, Theme.vermLit.g, Theme.vermLit.b, 0.16) : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Row {
            id: aRow
            anchors.centerIn: parent
            spacing: 5 * act.s
            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * act.s
                height: 14 * act.s
                name: act.glyph
                color: act.tint
                stroke: 1.7
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: act.label
                color: act.tint
                font.family: Theme.mono
                font.pixelSize: 9.5 * act.s
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8 * act.s
            }
        }
        HoverHandler { id: aHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: act.tapped() }
    }

    // --- geometry re-exports for shell.qml's input mask ----------------------
    readonly property alias hudX:     island.hudX
    readonly property alias hudY:     island.hudY
    readonly property alias hudW:     island.hudW
    readonly property alias hudH:     island.hudH
    readonly property alias trigX:    island.trigX
    readonly property alias trigY:    island.trigY
    readonly property alias trigW:    island.trigW
    readonly property alias trigH:    island.trigH
    readonly property alias dragging: island.dragging

    // content size drives island body (after content items are declared, QML
    // resolves forward references so referencing grid/chooserGrid here is fine).
    readonly property real curW: (Recorder.anyActive || hud.starting) ? grid.implicitWidth  : chooserGrid.implicitWidth
    readonly property real curH: (Recorder.anyActive || hud.starting) ? grid.implicitHeight : chooserGrid.implicitHeight

    FloatingIsland {
        id: island
        group: hud.group
        s: hud.s
        radius: hud.radius
        smoothing: hud.smoothing
        barEdge: hud.barEdge
        barBand: hud.barBand
        bodyW: hud.curW + 20 * hud.s
        bodyH: hud.curH + 14 * hud.s
        dragEnabled: Recorder.anyActive || Recorder.chooserOpen
        dockEdge: "bottom"
        onDragReleased: (_e) => {}

        Behavior on bodyW { NumberAnimation { duration: island.moveDur; easing.type: Easing.InOutCubic } }
        Behavior on bodyH { NumberAnimation { duration: island.moveDur; easing.type: Easing.InOutCubic } }
    }

    // --- content item --------------------------------------------------------
    Item {
        id: content
        x: island.px
        y: island.py
        width: island.bodyW
        height: island.bodyH
        opacity: island.reorientFade * Math.max(0, Math.min(1, (hud.prog - 0.25) / 0.5))
        transform: Matrix4x4 { matrix: island.deformMatrix }

        // only one grid is visible at a time; track whichever grip is live so
        // the drag hitbox (in FloatingIsland) stays under it.
        Binding { target: island; property: "handleX"; value: grid.visible ? grid.x + gripInGrid.x : chooserGrid.x + gripInChooser.x }
        Binding { target: island; property: "handleY"; value: grid.visible ? grid.y + gripInGrid.y : chooserGrid.y + gripInChooser.y }
        Binding { target: island; property: "handleW"; value: grid.visible ? gripInGrid.width : gripInChooser.width }
        Binding { target: island; property: "handleH"; value: grid.visible ? gripInGrid.height : gripInChooser.height }

        Grid {
            id: grid
            visible: Recorder.anyActive || hud.starting
            anchors.centerIn: parent
            columns: island.layoutVertical ? 1 : 99
            rowSpacing: 7 * hud.s
            columnSpacing: 8 * hud.s
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            GripDots { id: gripInGrid; s: hud.s }

            Rectangle {
                width: 9 * hud.s
                height: 9 * hud.s
                radius: width / 2
                color: Recorder.paused ? Theme.faint : Theme.vermLit
                opacity: Recorder.paused ? 1 : Recorder.pulse
            }

            Text {
                text: Recorder.elapsedText
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * hud.s
                font.features: { "tnum": 1 }
            }

            RecordButton { visible: Recorder.canPause; s: hud.s; glyph: Recorder.paused ? "play" : "pause"; tint: Theme.cream; onTapped: Recorder.togglePause() }
            RecordButton { s: hud.s; glyph: "stop"; tint: Theme.vermLit; onTapped: Recorder.studioActive ? Recorder.stopStudio() : Recorder.stop() }
            RecordButton { s: hud.s; glyph: hud.sinkMuted ? "speaker-off" : "speaker"; tint: hud.sinkMuted ? Theme.faint : Theme.cream; onTapped: hud.toggleSink() }
            RecordButton { s: hud.s; glyph: hud.micMuted ? "mic-off" : "mic"; tint: hud.micMuted ? Theme.faint : Theme.cream; onTapped: hud.toggleMic() }
            RecordButton { s: hud.s; glyph: "compress"; tint: Theme.subtle; onTapped: hud.hidden = !hud.hidden }
        }

        Grid {
            id: chooserGrid
            anchors.centerIn: parent
            visible: Recorder.chooserOpen && !Recorder.anyActive && !hud.starting
            columns: island.layoutVertical ? 1 : 99
            rowSpacing: 7 * hud.s
            columnSpacing: 6 * hud.s
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            GripDots { id: gripInChooser; s: hud.s }

            RecordButton { s: hud.s; glyph: Recorder.regionGeom !== "" ? "region" : "monitor"; tint: Recorder.regionGeom !== "" ? Theme.cream : Theme.subtle; onTapped: { if (Recorder.regionGeom !== "") Recorder.regionGeom = ""; else Recorder.pickRegion(); } }
            RecordButton { s: hud.s; glyph: hud.optDesktopAudio ? "speaker" : "speaker-off"; tint: hud.optDesktopAudio ? Theme.cream : Theme.subtle; onTapped: hud.optDesktopAudio = !hud.optDesktopAudio }
            RecordButton { s: hud.s; glyph: hud.optMic ? "mic" : "mic-off"; tint: hud.optMic ? Theme.cream : Theme.subtle; onTapped: hud.optMic = !hud.optMic }
            RecordButton { s: hud.s; glyph: "webcam"; tint: Camera.active ? Theme.cream : Theme.subtle; onTapped: Camera.toggle() }

            Rectangle {
                width: (island.layoutVertical ? 18 : 1) * hud.s
                height: (island.layoutVertical ? 1 : 18) * hud.s
                radius: 0.5 * hud.s
                color: Theme.subtle
                opacity: 0.35
            }

            Action { s: hud.s; glyph: "record"; label: "Quick"; tint: Theme.vermLit; primary: true; onTapped: hud.startQuick() }
            Action { s: hud.s; glyph: "film";   label: "Studio"; onTapped: hud.startStudio() }
            Action { s: hud.s; glyph: "folder"; label: "Edit";   onTapped: hud.launchRyomotion() }

            RecordButton { s: hud.s; glyph: "close"; tint: Theme.subtle; onTapped: Recorder.chooserOpen = false }
        }
    }

    // tucked cue: a record dot pulses on the nub.
    Rectangle {
        readonly property real cx: island.faceX + island.faceW / 2
        readonly property real cy: island.faceY + island.faceH / 2
        width: 8 * hud.s
        height: 8 * hud.s
        radius: width / 2
        x: cx - width / 2
        y: cy - height / 2
        color: Recorder.paused ? Theme.faint : Theme.vermLit
        opacity: Recorder.anyActive ? Math.max(0, 1 - hud.prog / 0.5) * (Recorder.paused ? 0.9 : Recorder.pulse) : 0
        visible: opacity > 0.01
    }

    readonly property bool sinkMuted: !!(Audio.sink   && Audio.sink.audio   && Audio.sink.audio.muted)
    readonly property bool micMuted:  !!(Audio.source && Audio.source.audio && Audio.source.audio.muted)
    function toggleSink() { if (Audio.sink   && Audio.sink.audio)   Audio.sink.audio.muted   = !Audio.sink.audio.muted; }
    function toggleMic()  { if (Audio.source && Audio.source.audio) Audio.source.audio.muted = !Audio.source.audio.muted; }
}
