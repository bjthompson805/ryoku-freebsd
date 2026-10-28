pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// update data for the Hub's Updates section, wired to `ryoku status --json`.
// installed commit, pending updates (commits behind the channel plus package
// upgrades), and the incoming list are all live. when behind, `updates` holds
// the incoming commits and packages; when current, `recent` holds the recent
// history the installed version contains, so the page stays informative either
// way. check() re-runs it (fetches origin with no prompt).
Singleton {
    id: root

    property bool available: false
    property string currentVersion: ""
    property string latestVersion: ""
    property string branch: "main"
    property int behind: 0

    // incoming commits and package upgrades: [{ name, old, new }]. empty when
    // current.
    property var updates: []

    // recent history the installed version contains: [{ name, old, new }].
    // populated when the box is up to date, so the page stays informative.
    property var recent: []

    property var lastChecked: null
    property int tick: 0
    readonly property string checkedAgo: {
        root.tick;  // re-eval as the clock ticks
        if (!root.lastChecked)
            return "not yet";
        var s = Math.floor((Date.now() - root.lastChecked.getTime()) / 1000);
        if (s < 10)
            return "just now";
        if (s < 60)
            return s + "s ago";
        var m = Math.floor(s / 60);
        if (m < 60)
            return m + "m ago";
        var h = Math.floor(m / 60);
        if (h < 24)
            return h + "h ago";
        return Math.floor(h / 24) + "d ago";
    }

    function check() {
        statusProc.running = true;
    }

    function apply(t) {
        try {
            var o = JSON.parse(t);
            root.currentVersion = o.installedVersion || "";
            root.latestVersion = o.latestVersion || "";
            root.branch = o.channel || "main";
            root.behind = o.pendingUpdates || 0;
            root.available = root.behind > 0;
            root.updates = o.updates || [];
            root.recent = o.recent || [];
            root.lastChecked = new Date();
        } catch (e) {
            root.available = false;
            root.behind = 0;
            root.updates = [];
            root.recent = [];
        }
    }

    Process {
        id: statusProc
        command: ["ryoku", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.apply(this.text)
        }
    }

    // keep the "checked Xm ago" line live.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.tick++
    }

    Component.onCompleted: root.check()
}
