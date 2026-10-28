pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// global webcam-toggle state, polled continuously (not gated on the sidebar
// being open, unlike DeckControls' other toggle probes) because the bar's
// bridge indicator (BarStatus.qml) needs a live answer at all times, not
// just while the deck is up. `on` drives the sidebar's Webcam quick toggle;
// `bridgeOn`/`streaming` are the bar icon's own signals -- distinct from
// `on` because on a mixed UVC+non-UVC system `on` can be true from the UVC
// side alone while the bridge is untouched (see ryoku-cmd-webcam's header).
Singleton {
    id: root

    readonly property string scripts: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/"

    property bool on: true
    property bool bridgeOn: false
    property bool streaming: false

    Process {
        id: statusProc
        command: ["sh", "-c", root.scripts + "ryoku-cmd-webcam status 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.on = this.text.trim() === "on" }
    }
    Process {
        id: bridgeProc
        command: ["sh", "-c", root.scripts + "ryoku-cmd-webcam bridge-status 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.bridgeOn = this.text.trim() === "on" }
    }
    Process {
        id: streamingProc
        command: ["sh", "-c", root.scripts + "ryoku-cmd-webcam streaming-status 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.streaming = this.text.trim() === "on" }
    }

    function toggle() {
        Spawn.spawn([root.scripts + "ryoku-cmd-webcam", root.on ? "off" : "on"]);
        root.on = !root.on;
        pollDebounce.restart();
    }

    function repoll() {
        statusProc.running = true;
        bridgeProc.running = true;
        streamingProc.running = true;
    }
    Timer { id: pollDebounce; interval: 1500; onTriggered: root.repoll() }
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.repoll()
    }
    Component.onCompleted: repoll()

    // flip180 is read-only here (Ryoku Hub > Input > Camera owns writes) --
    // shown in the bridge popout so "which orientation is live" doesn't
    // require opening Hub. Same ~/.config/ryoku/webcam.json Hub writes to,
    // unrelated to camera.json (the self-view Mirror bubble's own flip).
    property alias flip180: adapter.flip180

    FileView {
        id: cfg
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/webcam.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property bool flip180: false
        }
    }
}
