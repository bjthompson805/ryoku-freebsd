pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// screen recording state + control. drives ryoku-cmd-screenrecord
// (wf-recorder) and reconciles against the live process, so a failed launch
// or an external stop can't strand the UI. the strip chip + the utilities
// Record card share this one source of truth.
Singleton {
    id: root

    property bool active: false
    // the sidebar Record button opens the floating island in its pre-record
    // chooser, where the capture toggles and the Quick / Edit actions live.
    property bool chooserOpen: false
    property int startedAt: 0
    property int elapsedSec: 0
    property real pulse: 1
    readonly property string elapsedText: fmt(elapsedSec)

    // full path: ~/.config/hypr/scripts isn't on the shell's PATH, a bare name
    // wouldn't resolve and recording would silently never start.
    readonly property string script: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/ryoku-cmd-screenrecord"

    // region capture: the box the user drew as "WxH+X+Y" (logical coords),
    // "" = full monitor. slurp must launch detached (a managed Process gets its
    // session killed before it can grab the seat), so it writes the box to a state
    // file the FileView reads back -- QML (the overlay) and the recorder script
    // then share one geometry. regionPicking gates it so a fresh pick applies but a
    // stale file left from a past session does not.
    property string regionGeom: ""
    property bool regionPicking: false
    readonly property string regionFilePath: (Quickshell.env("RYOKU_STATE_PATH") || (Quickshell.env("HOME") + "/.local/state/ryoku")) + "/region-pick"
    function pickRegion() {
        root.regionPicking = true;
        Spawn.spawn(["sh", "-c",
            "mkdir -p \"$(dirname '" + root.regionFilePath + "')\"; "
            + "g=$(slurp -f '%wx%h+%x+%y' 2>/dev/null); "
            + "printf '%s' \"$g\" > '" + root.regionFilePath + ".tmp'; "
            + "mv '" + root.regionFilePath + ".tmp' '" + root.regionFilePath + "'"]);
    }
    FileView {
        id: regionFile
        path: root.regionFilePath
        blockLoading: true
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (!root.regionPicking)
                return;
            root.regionPicking = false;
            var g = (regionFile.text() || "").trim();
            root.regionGeom = /^\d+x\d+\+\d+\+\d+$/.test(g) ? g : "";
        }
    }

    function start(extraArgs) {
        Spawn.spawn([root.script, ...(extraArgs || [])]);
        root.active = true;
        root.startedAt = Math.floor(Date.now() / 1000);
        root.elapsedSec = 0;
        confirm.restart();
    }

    function stop() {
        Spawn.spawn([root.script, "--stop"]);
        root.active = false;
    }

    SequentialAnimation on pulse {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation { to: 0.18; duration: 620; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutSine }
    }

    // reconcile against the live process and clear stale state when nothing's
    // recording. the [w] bracket keeps this poll's own command from matching.
    Process {
        id: poll
        command: ["sh", "-c", "pgrep -f '(^|/)[w]f-recorder( |$)' >/dev/null 2>&1 && echo on || echo off"]
        stdout: StdioCollector {
            onStreamFinished: {
                var nowActive = text.trim() === "on";
                if (nowActive && !root.active) {
                    root.startedAt = Math.floor(Date.now() / 1000);
                    root.elapsedSec = 0;
                }
                if (!nowActive) {
                    root.startedAt = 0;
                    root.elapsedSec = 0;
                    root.pulse = 1;
                }
                root.active = nowActive;
            }
        }
    }

    // reconcile cadence: poll hard (2s) only while a capture is live, so an
    // external stop or crash can't strand the island; idle we poll slowly (30s),
    // enough to catch a capture started outside the shell without spawning a
    // pgrep subprocess every 2s around the clock.
    Timer {
        interval: root.active ? 2000 : 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!poll.running) poll.running = true
    }

    // confirm the recorder actually came up after a start; a failed launch
    // would otherwise leave the optimistic running state counting up forever.
    Timer {
        id: confirm
        interval: 2500
        onTriggered: poll.running = true
    }

    Timer {
        interval: 1000
        running: root.active
        repeat: true
        onTriggered: root.elapsedSec++
    }

    function fmt(sec) {
        var s = Math.max(0, Math.round(sec));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        var r = s % 60;
        if (h > 0)
            return h + ":" + (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }
}
