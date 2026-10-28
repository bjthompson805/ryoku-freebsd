pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Update state for the top-right update island, wired to `ryoku status --json`.
//
// `available`/`behind` reflect commits behind the channel; the island folds to
// nothing when current. The run-state fields mirror an in-flight `ryoku update`:
// the CLI publishes progress to a small runtime file (a Ryoku wave while it
// runs), and once it finishes the island re-checks and folds away.
Singleton {
    id: root

    // availability (live, from `ryoku status --json`)
    property bool available: false
    property int behind: 0
    property string latestVersion: ""

    // live run state (published by `ryoku update`)
    property string runPhase: "idle"   // idle | running | success
    property real runProgress: 0

    readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-update.json"

    function check() {
        statusProc.running = true;
    }

    function applyStatus(t) {
        try {
            var o = JSON.parse(t);
            root.behind = o.pendingUpdates || 0;
            root.available = root.behind > 0;
            root.latestVersion = o.latestVersion || "";
        } catch (e) {
            root.available = false;
            root.behind = 0;
        }
    }

    function applyState(t) {
        var prev = root.runPhase;
        try {
            var o = JSON.parse(t);
            root.runPhase = o.phase || "idle";
            root.runProgress = (typeof o.progress === "number") ? o.progress : 0;
        } catch (e) {
            root.runPhase = "idle";
            root.runProgress = 0;
        }
        // update just finished: re-check so the island folds when current.
        if (prev === "running" && root.runPhase !== "running")
            root.check();
    }

    // Dismiss the run state (write idle). Used after a refresh.
    function clearRun() {
        root.runPhase = "idle";
        root.runProgress = 0;
        state.setText("{\"phase\":\"idle\"}");
    }

    // Reload the shell so a finished update's changes take effect, then clear.
    function refresh() {
        Spawn.spawn(["ryoku-shell", "reload"]);
        root.clearRun();
    }

    Process {
        id: statusProc
        command: ["ryoku", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(this.text)
        }
    }

    Component.onCompleted: root.check()

    // First check after boot can race a slow fetch. Re-check on a steady cadence
    // so commits that land mid-session still surface and an early empty read
    // recovers.
    Timer {
        interval: 300000
        running: true
        repeat: true
        onTriggered: root.check()
    }

    FileView {
        id: state
        path: root.statePath
        watchChanges: true
        atomicWrites: false
        onLoaded: root.applyState(state.text())
        onFileChanged: state.reload()
        onLoadFailed: state.setText("{\"phase\":\"idle\"}")
    }
}
