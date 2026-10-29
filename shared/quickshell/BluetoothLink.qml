pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared bluetooth control for every Bluetooth surface (the bar icon, the
// deck toggle, the pill's Link drill-in, the launcher's device cards, the
// Hub's Connections > Bluetooth tab). One real file, symlinked into every
// root's Singletons/ that needs it, same trick as SpawnCore.qml -- see that
// file's header for why a symlink instead of a copy.
//
// `ryoku-shell bt watch` is ground truth: it streams the adapter, the paired
// devices and a recent scan's finds as one JSON line per change, from
// FreeBSD's own stack (hccontrol, sdpcontrol) rather than BlueZ. Pairing,
// connecting, forgetting and power go through `ryoku-shell bt`, which hands
// the root parts to ryoku-priv. The objects below keep the shape the
// surfaces were written against (Quickshell.Bluetooth's adapter and device
// properties, connect()/disconnect()), so they read the same either way.
Singleton {
    id: root

    // the last line from the watcher; see btStatus in shell/ipc/bt.go.
    property var st: ({ present: false, enabled: false, discovering: false, address: "", devices: [] })

    readonly property bool hasAdapter: st.present === true
    readonly property var adapter: hasAdapter ? {
        enabled: st.enabled === true,
        discovering: root.discovering,
        address: st.address || ""
    } : null
    readonly property bool discovering: st.discovering === true || scanProc.running
    // FreeBSD has no rfkill; power is the driver attached or not, which the
    // toggle flips directly.
    readonly property bool blocked: false

    readonly property var devices: (st.devices || []).map(function(d) {
        return {
            address: d.address,
            name: d.name || d.address,
            deviceName: d.name || "",
            paired: d.paired === true,
            connected: d.connected === true,
            kind: d.kind || "",
            icon: d.icon || "bluetooth",
            // FreeBSD's stack reports no battery levels.
            battery: -1,
            batteryAvailable: false,
            connect: function() { root.run(["connect", d.address], d.address); },
            disconnect: function() { root.run(["disconnect", d.address], d.address); },
            forget: function() { root.forgetDevice(d); }
        };
    })
    readonly property int connectedCount: devices.filter(function(d) { return d.connected; }).length
    // the backend already sorts: connected, then paired, then by name.
    readonly property var devicesSorted: devices

    property string pairingAddress: ""
    property string failedAddress: ""
    // the backend's message for the last failed action, for a surface that
    // wants to say why.
    property string lastError: ""

    function metaFor(d) {
        if (!d) return "";
        var parts = [];
        if (d.connected) parts.push("connected");
        else if (d.paired) parts.push("paired");
        if (d.kind === "audio") parts.push("audio");
        else if (d.kind === "input") parts.push("input");
        return parts.join(" · ");
    }

    function batteryLevel(d) {
        if (!d || d.battery === undefined || d.battery === null) return -1;
        var b = d.battery;
        if (b <= 0) return -1;
        if (b <= 1) b = b * 100;
        return Math.round(b);
    }

    // row click: connected -> disconnect, paired -> connect, else pair, which
    // registers the device with hcsecd and connects it in one go.
    function activateDevice(d) {
        if (!d)
            return;
        if (d.connected)
            d.disconnect();
        else if (d.paired)
            d.connect();
        else
            root.pairDevice(d);
    }

    function pairDevice(d) {
        if (!d || !d.address)
            return;
        root.run(["pair", d.address], d.address);
    }

    function forgetDevice(d) {
        if (!d || !d.address)
            return;
        root.run(["forget", d.address], d.address);
    }

    // one action at a time: each one is a few seconds of SDP and ryoku-priv,
    // and a second tap while it runs would only race it.
    function run(args, addr) {
        if (opProc.running)
            return;
        root.pairingAddress = args[0] === "pair" || args[0] === "connect" ? addr : "";
        root.failedAddress = "";
        root.lastError = "";
        opProc.addr = addr;
        opProc.command = ["ryoku-shell", "bt"].concat(args);
        opProc.running = true;
    }

    function setAdapterEnabled(v) {
        if (!root.hasAdapter || powerProc.running)
            return;
        powerProc.command = ["ryoku-shell", "bt", "power", v ? "on" : "off"];
        powerProc.running = true;
    }

    // a scan is one inquiry, about ten seconds with the name lookups, so a
    // toggle that lands mid-scan stops it instead of queueing another.
    function toggleScan() {
        if (scanProc.running)
            root.stopScan();
        else
            root.startScan();
    }

    function startScan() {
        if (!root.adapter || root.adapter.enabled !== true || scanProc.running)
            return;
        scanProc.running = true;
    }

    // a surface losing visibility (tab switch, popout close) calls this so a
    // scan isn't left holding the radio in the background.
    function stopScan() {
        if (scanProc.running)
            scanProc.running = false;
    }

    Process {
        id: watchProc
        running: true
        command: ["ryoku-shell", "bt", "watch"]
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    root.st = JSON.parse(line);
                } catch (e) {}
            }
        }
        onExited: watchRetry.restart()
    }

    Timer {
        id: watchRetry
        interval: 5000
        onTriggered: watchProc.running = true
    }

    Process {
        id: scanProc
        command: ["ryoku-shell", "bt", "scan"]
    }

    Process {
        id: opProc
        property string addr: ""
        stderr: StdioCollector { id: opErr }
        onExited: function(exitCode) {
            root.pairingAddress = "";
            if (exitCode !== 0) {
                root.failedAddress = opProc.addr;
                root.lastError = opErr.text.replace(/^ryoku-shell bt: /, "").trim();
                failTimer.restart();
            }
        }
    }

    Process {
        id: powerProc
    }

    Timer {
        id: failTimer
        interval: 4000
        repeat: false
        onTriggered: root.failedAddress = ""
    }
}
