pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared wifi + hotspot control for every network surface (the Hub's Wi-Fi
// and Hotspot tabs, the pill's Link drill-in, and the pill's Network
// singleton behind the bar icon). One real file, symlinked into every root's
// Singletons/ that needs it, same trick as SpawnCore.qml -- see that file's
// header for why a symlink instead of a copy. Named WifiLink, not Network:
// pill already has a separate, lightweight `Network` singleton (bar-status
// presence only) that reads from this one.
//
// `ryoku-shell wifi watch` is ground truth: it streams the radio, the default
// route and the wpa_supplicant scan list as one JSON line per change.
// Connecting pipes the password on stdin so it never lands in a process
// argument list; a new network that fails to join is removed by the backend.
// The hotspot half drives `ryoku-shell wifi hotspot`, name and password on
// stdin for the same reason.
Singleton {
    id: root

    // ---- wifi list ----------------------------------------------------

    // the last line from the watcher; see wifiStatus in shell/ipc/wifi.go.
    property var st: ({ iface: "", radio: false, route: "", wired: false, speed: 0, ssid: "", signal: 0, networks: [] })

    // a wlan interface exists. without one every Wi-Fi control hides.
    readonly property bool present: st.iface !== ""
    readonly property bool wifiOn: present && st.radio
    // rows shaped like the old Quickshell.Networking objects the surfaces
    // read: name, signalStrength (0..1), connected.
    readonly property var nets: (st.networks || []).map(function(n) {
        return { name: n.ssid, signalStrength: n.signal, connected: n.connected, secured: n.secured, known: n.known };
    })
    // the backend already sorts by signal and drops hidden SSIDs.
    readonly property var netsSorted: nets
    readonly property var active: nets.find(function(n) { return n.connected; }) || null

    readonly property var securityMap: {
        var map = {};
        nets.forEach(function(n) { map[n.name] = n.secured; });
        return map;
    }
    readonly property var knownProfiles: {
        var set = {};
        nets.forEach(function(n) { if (n.known) set[n.name] = true; });
        return set;
    }
    property string expandedSsid: ""
    property bool connecting: false
    property bool connectFailed: false
    property bool scanning: false

    // whether some visible UI wants periodic rescans -- set via
    // setScannerActive() from whichever surface (hub tab or pill drill-in)
    // is currently shown, since more than one may exist across the app's
    // lifetime but only one is ever visible at a time.
    property bool scannerActive: false

    // password being typed for expandedSsid. lives here, not on a delegate:
    // a rescan hands the network list a brand-new array, which tears down
    // and recreates the delegate mid-typing; the field restores from this on
    // rebuild.
    property string pwDraft: ""
    property string pendingPw: ""

    // ---- hotspot --------------------------------------------------------

    // the access point is its own interface, ryokuap0, cloned off the Wi-Fi
    // device while the hotspot is up; name and password persist in the
    // backend's state file.
    readonly property string hsIface: "ryokuap0"
    property string hsName: "Ryoku"
    property string hsPw: ""
    property bool hsActive: false
    property bool hsBusy: false
    // why the last start failed (no AP support, pf rules, ...), "" if not.
    property string hsError: ""
    property string hsEdit: ""
    property string hsDraft: ""

    function isSecured(ssid) {
        return root.securityMap[ssid] === true;
    }

    // the watcher keeps the state current; this only revives it if it died.
    function refresh() {
        watchProc.running = true;
    }

    // row click: connected -> disconnect, known or open -> connect, else
    // expand the inline password row (closes if already open).
    function activateNetwork(net) {
        if (!net)
            return;
        var ssid = net.name || "";
        if (root.expandedSsid === ssid) {
            root.expandedSsid = "";
            return;
        }
        if (net.connected) {
            disconnectProc.running = true;
            return;
        }
        if (net.known || !net.secured) {
            root.expandedSsid = "";
            root._connect(ssid, "");
            return;
        }
        root.connectFailed = false;
        root.pwDraft = "";
        root.expandedSsid = ssid;
    }

    // password through stdin: the process list is world-readable for the
    // whole attempt, so it MUST NOT be in argv.
    function connectWithPassword(ssid, pw) {
        if (pw.length)
            root._connect(ssid, pw);
    }

    function _connect(ssid, pw) {
        if (connProc.running)
            return;
        root.connecting = true;
        root.connectFailed = false;
        root.pendingPw = pw;
        connProc.command = pw.length
            ? ["ryoku-shell", "wifi", "connect", "-p", ssid]
            : ["ryoku-shell", "wifi", "connect", ssid];
        connProc.running = true;
    }

    function setWifiEnabled(v) {
        radioProc.command = ["ryoku-shell", "wifi", "radio", v ? "on" : "off"];
        radioProc.running = true;
    }

    // reload pulse: asks the supplicant for a fresh scan and spins the button
    // up to 10s; results arrive through the watcher.
    function startScan() {
        if (!root.wifiOn)
            return;
        root.scanning = true;
        scanProc.running = true;
        scanTimer.restart();
    }

    function stopScan() {
        root.scanning = false;
        scanTimer.stop();
    }

    // called by a surface as it becomes/stops being the visible wifi UI:
    // drives the periodic rescan and, on the way out, drops any in-progress
    // password entry so the next visit starts clean.
    function setScannerActive(v) {
        root.scannerActive = v;
        if (!v) {
            root.stopScan();
            root.expandedSsid = "";
            root.connectFailed = false;
        }
    }

    Timer {
        id: scanTimer
        interval: 10000
        onTriggered: root.stopScan()
    }

    // a connected supplicant does not rescan on its own, so keep the list
    // fresh while someone is looking at it.
    Timer {
        interval: 20000
        repeat: true
        triggeredOnStart: true
        running: root.scannerActive && root.wifiOn
        onTriggered: scanProc.running = true
    }

    Process {
        id: watchProc
        running: true
        command: ["ryoku-shell", "wifi", "watch"]
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
        command: ["ryoku-shell", "wifi", "scan"]
    }

    Process {
        id: radioProc
    }

    Process {
        id: disconnectProc
        command: ["ryoku-shell", "wifi", "disconnect"]
    }

    Process {
        id: connProc
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onStarted: {
            if (root.pendingPw.length)
                write(root.pendingPw + "\n");
            root.pendingPw = "";
        }
        onExited: function(exitCode) {
            root.connecting = false;
            if (exitCode === 0) {
                root.expandedSsid = "";
                root.pwDraft = "";
                root.connectFailed = false;
            } else {
                root.connectFailed = true;
            }
        }
    }

    // ---- hotspot ----------------------------------------------------------

    // bring the shared AP up with the current name/pw, restarting it if it is
    // already up. both go over stdin, never argv.
    function applyHotspot() {
        if (root.hsBusy || root.hsPw.length < 8)
            return;
        root.hsBusy = true;
        root.hsError = "";
        hsApplyProc.running = true;
    }

    function stopHotspot() {
        if (root.hsBusy)
            return;
        root.hsBusy = true;
        hsDownProc.running = true;
    }

    function refreshHotspot() {
        hsStateProc.running = true;
    }

    // commit an inline name/pw edit. pw shorter than the WPA2 minimum (8) is
    // ignored. live hotspot is re-applied so the change takes effect now.
    function commitHotspotEdit() {
        if (root.hsEdit === "name") {
            if (root.hsDraft.length)
                root.hsName = root.hsDraft;
        } else if (root.hsEdit === "pw") {
            if (root.hsDraft.length >= 8)
                root.hsPw = root.hsDraft;
        }
        root.hsEdit = "";
        root.hsDraft = "";
        if (root.hsActive)
            root.applyHotspot();
    }

    // 8-char WPA2 pw from an unambiguous alphabet. used when the hotspot is
    // flipped on before a pw has been set.
    function generatePw() {
        var cs = "abcdefghijkmnpqrstuvwxyz23456789";
        var s = "";
        for (var i = 0; i < 8; i++)
            s += cs.charAt(Math.floor(Math.random() * cs.length));
        return s;
    }

    Process {
        id: hsApplyProc
        command: ["ryoku-shell", "wifi", "hotspot", "up"]
        stdinEnabled: true
        stderr: StdioCollector { id: hsApplyErr }
        onStarted: write(root.hsName + "\n" + root.hsPw + "\n")
        onExited: function(exitCode) {
            root.hsBusy = false;
            root.hsError = exitCode === 0 ? "" : hsApplyErr.text.replace(/^ryoku-shell wifi: /, "").trim();
            root.refreshHotspot();
        }
    }

    Process {
        id: hsDownProc
        command: ["ryoku-shell", "wifi", "hotspot", "down"]
        onExited: {
            root.hsBusy = false;
            root.refreshHotspot();
        }
    }

    Process {
        id: hsStateProc
        command: ["ryoku-shell", "wifi", "hotspot", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var h = JSON.parse(this.text);
                    root.hsActive = h.active;
                    if (h.name)
                        root.hsName = h.name;
                    if (h.password)
                        root.hsPw = h.password;
                } catch (e) {}
            }
        }
    }
}
