pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Shared wifi + hotspot control for every network surface (the Hub's Wi-Fi
// and Hotspot tabs, the pill's Link drill-in). One real file, symlinked into
// every root's Singletons/ that needs it, same trick as SpawnCore.qml -- see
// that file's header for why a symlink instead of a copy. Named WifiLink, not
// Network or Networking: Quickshell.Networking already exports a global
// `Networking` type (Networking.devices below), and pill already has a
// separate, lightweight `Network` singleton (bar-status presence only, no
// scanning/connecting) that this must not collide with.
//
// nmcli is ground truth for security + known-profile state (the Quickshell
// service doesn't expose them); connecting pipes the password on stdin so it
// never lands in /proc/<pid>/cmdline. The hotspot half brings the persistent
// `RyokuHotspot` NetworkManager profile up/down, name/password as positional
// args, never spliced into the shell string.
Singleton {
    id: root

    // ---- wifi list ----------------------------------------------------

    readonly property var devices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var wifiDev: devices.find(function(d) { return d && d.type === DeviceType.Wifi }) || null
    readonly property bool wifiOn: (typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : false
    readonly property var nets: (wifiDev && wifiDev.networks) ? wifiDev.networks.values : []
    readonly property var netsSorted: nets
        .slice()
        .filter(function(n) { return n && n.name && n.name.length > 0; })
        .sort(function(a, b) {
            return ((b ? b.signalStrength : 0) || 0) - ((a ? a.signalStrength : 0) || 0);
        })

    property var securityMap: ({})
    property var knownProfiles: ({})
    property string expandedSsid: ""
    property bool connecting: false
    property bool connectFailed: false
    property bool scanning: false

    // whether some visible UI wants the wifi device's continuous background
    // scanner on -- set via setScannerActive() from whichever surface (hub
    // tab or pill drill-in) is currently shown, since more than one may exist
    // across the app's lifetime but only one is ever visible at a time.
    property bool scannerActive: false

    // password being typed for expandedSsid. lives here, not on a delegate:
    // an nmcli rescan hands the network list a brand-new array, which tears
    // down and recreates the delegate mid-typing; the field restores from
    // this on rebuild.
    property string pwDraft: ""
    property string pendingPw: ""
    property string attemptSsid: ""
    property bool attemptWasKnown: false

    // ---- hotspot --------------------------------------------------------

    // hsCon = the NM profile name Ryoku owns; everything else is read from
    // that profile or driven into it by applyHotspot/stopHotspot.
    readonly property string hsCon: "RyokuHotspot"
    readonly property string hsIface: wifiDev ? (wifiDev.name || "wlan0") : "wlan0"
    property string hsName: "Ryoku"
    property string hsPw: ""
    property bool hsActive: false
    property bool hsBusy: false
    property string hsEdit: ""
    property string hsDraft: ""

    function isSecured(ssid) {
        var sec = root.securityMap[ssid];
        return sec !== undefined && sec !== "" && sec !== "--";
    }

    function refresh() {
        secProc.running = true;
        profProc.running = true;
    }

    // split one `nmcli -t` line at its last unescaped colon, unescape the
    // leading field. null if there's no separator.
    function _splitTerse(line) {
        for (var k = line.length - 1; k >= 0; k--) {
            if (line[k] === ":" && (k === 0 || line[k - 1] !== "\\"))
                return { head: line.slice(0, k).replace(/\\:/g, ":"), tail: line.slice(k + 1) };
        }
        return null;
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
            if (typeof net.disconnect === "function")
                net.disconnect();
            return;
        }
        var secKnown = root.securityMap[ssid] !== undefined;
        if (root.knownProfiles[ssid] === true || (secKnown && !root.isSecured(ssid))) {
            root.expandedSsid = "";
            if (typeof net.connect === "function")
                net.connect();
            root.refresh();
            return;
        }
        root.connectFailed = false;
        root.pwDraft = "";
        root.expandedSsid = ssid;
    }

    // `nmcli --ask`, password through stdin. /proc/<pid>/cmdline is world-
    // readable for the whole attempt, so it MUST NOT be in argv.
    function connectWithPassword(ssid, pw) {
        if (connProc.running || !pw.length)
            return;
        root.connecting = true;
        root.connectFailed = false;
        root.attemptSsid = ssid;
        root.attemptWasKnown = root.knownProfiles[ssid] === true;
        root.pendingPw = pw;
        connProc.command = ["nmcli", "--ask", "dev", "wifi", "connect", ssid];
        connProc.running = true;
    }

    function setWifiEnabled(v) {
        if (typeof Networking !== "undefined" && Networking)
            Networking.wifiEnabled = v;
    }

    // reload pulse. forces an nmcli rescan and spins the button up to 10s.
    // the device scanner runs continuously while some surface wants it on
    // (scannerActive); this just refreshes results and drives the spinner.
    function startScan() {
        if (!root.wifiOn)
            return;
        root.scanning = true;
        rescanProc.running = true;
        scanTimer.restart();
    }

    function stopScan() {
        root.scanning = false;
        scanTimer.stop();
    }

    // called by a surface as it becomes/stops being the visible wifi UI:
    // drives the device's background scanner and, on the way out, drops any
    // in-progress password entry so the next visit starts clean.
    function setScannerActive(v) {
        root.scannerActive = v;
        if (!v) {
            root.stopScan();
            root.expandedSsid = "";
            root.connectFailed = false;
        }
    }

    Binding {
        target: root.wifiDev
        property: "scannerEnabled"
        value: root.scannerActive && root.wifiOn
        when: root.wifiDev !== null
    }

    Timer {
        id: scanTimer
        interval: 10000
        onTriggered: root.stopScan()
    }

    Timer {
        id: secRefresh
        interval: 1200
        onTriggered: if (root.scannerActive) secProc.running = true
    }
    onNetsChanged: if (root.scannerActive) secRefresh.restart()

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
    }

    Process {
        id: secProc
        command: ["nmcli", "-t", "-f", "SSID,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i].length)
                        continue;
                    var parts = root._splitTerse(lines[i]);
                    if (parts && parts.head.length)
                        map[parts.head] = parts.tail;
                }
                root.securityMap = map;
            }
        }
    }

    Process {
        id: profProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var set = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = root._splitTerse(lines[i]);
                    if (parts && parts.head.length && parts.tail === "802-11-wireless")
                        set[parts.head] = true;
                }
                root.knownProfiles = set;
            }
        }
    }

    Process {
        id: connProc
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onStarted: {
            write(root.pendingPw + "\n");
            root.pendingPw = "";
        }
        onExited: function(exitCode) {
            root.connecting = false;
            if (exitCode === 0) {
                root.expandedSsid = "";
                root.pwDraft = "";
                root.connectFailed = false;
                root.refresh();
            } else {
                root.connectFailed = true;
                if (!root.attemptWasKnown && root.attemptSsid.length) {
                    cleanupProc.command = ["nmcli", "connection", "delete", "id", root.attemptSsid];
                    cleanupProc.running = true;
                }
            }
        }
    }

    // a failed `nmcli dev wifi connect` leaves a profile named after the SSID;
    // without deleting it the next click reads it as known and silently fails
    // forever. ask me how I found out.
    Process {
        id: cleanupProc
        onExited: root.refresh()
    }

    // ---- hotspot ----------------------------------------------------------

    // bring the shared AP up with the current name/pw. creates the persistent
    // connection on first use, modifies it after. name and pw are positional
    // args, never spliced into the shell string -- a weird char can't break or
    // inject the command.
    function applyHotspot() {
        if (root.hsBusy || root.hsPw.length < 8)
            return;
        root.hsBusy = true;
        hsApplyProc.command = ["sh", "-c",
            'c="' + root.hsCon + '"; '
            + 'if nmcli -t connection show "$c" >/dev/null 2>&1; then '
            +   'nmcli connection modify "$c" 802-11-wireless.ssid "$1" 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$2"; '
            + 'else '
            +   'nmcli connection add type wifi ifname "$3" con-name "$c" autoconnect no 802-11-wireless.ssid "$1" 802-11-wireless.mode ap 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$2" ipv4.method shared; '
            + 'fi; '
            + 'nmcli connection up "$c"',
            "sh", root.hsName, root.hsPw, root.hsIface];
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
        hsReadProc.running = true;
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
        onExited: {
            root.hsBusy = false;
            root.refreshHotspot();
        }
    }

    Process {
        id: hsDownProc
        command: ["nmcli", "connection", "down", root.hsCon]
        onExited: {
            root.hsBusy = false;
            root.refreshHotspot();
        }
    }

    Process {
        id: hsStateProc
        command: ["sh", "-c", "nmcli -t -f NAME connection show --active | grep -qxF -- \"$1\" && echo on || echo off", "sh", root.hsCon]
        stdout: StdioCollector {
            onStreamFinished: root.hsActive = this.text.trim() === "on"
        }
    }

    Process {
        id: hsReadProc
        command: ["nmcli", "-t", "-s", "-g", "802-11-wireless.ssid,802-11-wireless-security.psk", "connection", "show", root.hsCon]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                if (lines.length >= 1 && lines[0].length)
                    root.hsName = lines[0];
                if (lines.length >= 2 && lines[1].length)
                    root.hsPw = lines[1];
            }
        }
    }
}
