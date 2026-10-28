pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// webcam kill-switch state for the sidebar's Webcam quick toggle, backed by
// ryoku-cmd-webcam (webcamd on/off). polled only while something reads it
// through `active`, like DeckControls' own probes.
Singleton {
    id: root

    readonly property string scripts: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/"

    property bool active: false
    property bool on: true

    Process {
        id: statusProc
        command: ["sh", "-c", root.scripts + "ryoku-cmd-webcam status 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.on = this.text.trim() === "on" }
    }

    function toggle() {
        Spawn.spawn([root.scripts + "ryoku-cmd-webcam", root.on ? "off" : "on"]);
        root.on = !root.on;
        pollDebounce.restart();
    }

    function repoll() {
        statusProc.running = true;
    }
    Timer { id: pollDebounce; interval: 1500; onTriggered: root.repoll() }
    Timer {
        interval: 4000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: root.repoll()
    }
}
