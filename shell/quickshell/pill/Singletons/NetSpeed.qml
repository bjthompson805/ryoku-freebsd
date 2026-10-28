pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// live network throughput for the bar's net-speed module: rx/tx byte-rate off
// the default-route interface, sampled from /proc/net/dev deltas. the
// interface is resolved via `ip route` and re-resolved occasionally (it can
// change, e.g. wifi to ethernet), so there is no per-tick subprocess. the
// poller runs only while `active` (a visible BarNetSpeed sets it). keeps a
// short rate history for the popout sparklines and a running byte total for
// as long as the daemon has been up, for the session-usage readout.
Singleton {
    id: root

    property bool active: false
    property real rxRate: 0 // bytes/sec
    property real txRate: 0 // bytes/sec
    property string rxLabel: "0 B/s"
    property string txLabel: "0 B/s"

    readonly property int histLen: 60
    property var rxHistory: []
    property var txHistory: []

    property real rxTotal: 0 // bytes, cumulative since the poller first ran
    property real txTotal: 0
    property string rxTotalLabel: "0 B"
    property string txTotalLabel: "0 B"

    property string _iface: ""
    property real _prevRx: -1
    property real _prevTx: -1
    property real _prevTime: 0

    function _push(arr, v) {
        var a = arr.slice();
        a.push(v);
        if (a.length > root.histLen)
            a.shift();
        return a;
    }

    function _fmt(bps) {
        if (bps < 1024)
            return Math.round(bps) + " B/s";
        if (bps < 1024 * 1024)
            return (bps / 1024).toFixed(1) + " KB/s";
        if (bps < 1024 * 1024 * 1024)
            return (bps / (1024 * 1024)).toFixed(1) + " MB/s";
        return (bps / (1024 * 1024 * 1024)).toFixed(1) + " GB/s";
    }

    function _fmtBytes(bytes) {
        if (bytes < 1024)
            return Math.round(bytes) + " B";
        if (bytes < 1024 * 1024)
            return (bytes / 1024).toFixed(1) + " KB";
        if (bytes < 1024 * 1024 * 1024)
            return (bytes / (1024 * 1024)).toFixed(1) + " MB";
        return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB";
    }

    Process {
        id: ifaceProc
        command: ["sh", "-c", "ip route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i==\"dev\") print $(i+1)}' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = (this.text || "").trim();
                if (p.length > 0 && p !== root._iface) {
                    root._iface = p;
                    root._prevRx = -1;
                    root._prevTx = -1;
                }
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: ifaceProc.running = true
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.active && root._iface.length > 0
        triggeredOnStart: true
        onTriggered: devFile.reload()
    }

    FileView {
        id: devFile
        path: "/proc/net/dev"
        blockLoading: true
        printErrors: false
        onLoaded: {
            if (root._iface.length === 0)
                return;
            var lines = devFile.text().split("\n");
            for (var i = 0; i < lines.length; i++) {
                var ln = lines[i].trim();
                var idx = ln.indexOf(":");
                if (idx < 0)
                    continue;
                if (ln.slice(0, idx).trim() !== root._iface)
                    continue;
                var f = ln.slice(idx + 1).trim().split(/\s+/);
                if (f.length < 9)
                    return;
                var rx = Number(f[0]);
                var tx = Number(f[8]);
                var now = Date.now() / 1000;
                if (root._prevRx >= 0 && root._prevTime > 0) {
                    var dt = now - root._prevTime;
                    if (dt > 0) {
                        var drx = Math.max(0, rx - root._prevRx);
                        var dtx = Math.max(0, tx - root._prevTx);
                        root.rxRate = drx / dt;
                        root.txRate = dtx / dt;
                        root.rxLabel = root._fmt(root.rxRate);
                        root.txLabel = root._fmt(root.txRate);
                        root.rxHistory = root._push(root.rxHistory, root.rxRate);
                        root.txHistory = root._push(root.txHistory, root.txRate);
                        root.rxTotal += drx;
                        root.txTotal += dtx;
                        root.rxTotalLabel = root._fmtBytes(root.rxTotal);
                        root.txTotalLabel = root._fmtBytes(root.txTotal);
                    }
                }
                root._prevRx = rx;
                root._prevTx = tx;
                root._prevTime = now;
                return;
            }
        }
    }
}
