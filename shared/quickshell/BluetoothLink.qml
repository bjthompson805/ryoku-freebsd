pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Shared bluetooth control for every device-list surface (the Hub's
// Connections > Bluetooth tab, the pill's Link drill-in). One real file,
// symlinked into every root's Singletons/ that needs it, same trick as
// SpawnCore.qml -- see that file's header for why a symlink instead of a
// copy. Named BluetoothLink, not Bluetooth: Quickshell.Bluetooth already
// exports a global `Bluetooth` type (Bluetooth.defaultAdapter below), and a
// same-named local singleton in this same Singletons/ dir would shadow it.
// The adapter/device objects are already global via Quickshell.Bluetooth;
// this centralises the bluetoothctl pair-trust-connect script, the
// rfkill-unblock-then-power toggle flow, the scan auto-stop, and the
// bluetoothd service-repair path, so every surface agrees on scan/pair/service
// state instead of racing separate copies of it.
Singleton {
    id: root

    readonly property var adapter: (typeof Bluetooth !== "undefined" && Bluetooth) ? Bluetooth.defaultAdapter : null
    readonly property var devices: (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices) ? Bluetooth.devices.values : []
    readonly property bool hasAdapter: adapter !== null
    readonly property bool discovering: adapter ? adapter.discovering === true : false
    // rfkill (airplane mode, a laptop radio key) blocks the radio at the
    // kernel; BlueZ then refuses Powered=true, which is why a plain toggle can
    // look dead. Surfaced so the toggle can unblock first (setAdapterEnabled).
    readonly property bool blocked: (adapter && typeof BluetoothAdapterState !== "undefined")
        ? adapter.state === BluetoothAdapterState.Blocked : false
    readonly property int connectedCount: {
        var n = 0;
        for (var i = 0; i < devices.length; i++)
            if (devices[i] && devices[i].connected)
                n++;
        return n;
    }
    readonly property bool startingService: svcProc.running

    // BlueZ hands the cache out in arbitrary order. sort connected first, then
    // paired, then named devices, nameless MACs last, so a scan doesn't churn
    // the useful rows around.
    readonly property var devicesSorted: devices.slice().sort(function(a, b) {
        function rank(d) {
            if (!d) return 3;
            if (d.connected) return 0;
            if (d.paired) return 1;
            return (d.name && d.name.length) ? 2 : 3;
        }
        var r = rank(a) - rank(b);
        if (r !== 0) return r;
        return String((a && a.name) || "").localeCompare(String((b && b.name) || ""));
    })

    property string pairingAddress: ""
    property string failedAddress: ""
    property bool serviceFailed: false

    function metaFor(d) {
        if (!d) return "";
        var parts = [];
        if (d.connected) parts.push("connected");
        else if (d.paired) parts.push("paired");
        if (d.state !== undefined && typeof BluetoothDeviceState !== "undefined") {
            var st = BluetoothDeviceState.toString(d.state);
            if (st && st.length > 0 && parts.indexOf(st.toLowerCase()) === -1)
                parts.push(st.toLowerCase());
        }
        return parts.join(" · ");
    }

    function batteryLevel(d) {
        if (!d || d.battery === undefined || d.battery === null) return -1;
        var b = d.battery;
        if (b <= 0) return -1;
        if (b <= 1) b = b * 100;
        return Math.round(b);
    }

    // row click: connected -> disconnect, paired -> connect, else run the
    // bluetoothctl pair-trust-connect flow.
    function activateDevice(d) {
        if (!d)
            return;
        if (d.connected) {
            if (typeof d.disconnect === "function")
                d.disconnect();
            return;
        }
        if (d.paired) {
            if (typeof d.connect === "function")
                d.connect();
            return;
        }
        root.pairDevice(d);
    }

    // driven over bluetoothctl's own interactive stdin/stdout, not the
    // one-shot `bluetoothctl pair <addr>` form: a one-shot invocation never
    // registers an agent, so a phone's SSP numeric-comparison confirm (the
    // "Confirm passkey NNNNNN (yes/no):" prompt every Android/iOS pairing
    // needs) has nowhere to be answered -- the device connects but never
    // actually bonds, and drops again the next time it sleeps. Registering
    // an agent and auto-confirming here mirrors what a human driving
    // bluetoothctl by hand (or GNOME/KDE's pairing applet) already does: the
    // phone shows the same passkey on its own screen, so this is the same
    // "do the numbers match" trust model, just answered on our end with
    // nowhere to display it. trust+connect ride the same session once
    // pairing lands, so a successful pair doesn't need a second tap.
    property bool _pairSucceeded: false

    function pairDevice(d) {
        if (!d || !d.address || pairProc.running)
            return;
        root.pairingAddress = d.address;
        root.failedAddress = "";
        root._pairSucceeded = false;
        pairProc.command = ["bluetoothctl"];
        pairProc.running = true;
        pairTimeout.restart();
    }

    // belt-and-suspenders: a phone that never answers the confirm prompt
    // (locked, out of range, ignored) would otherwise leave this session
    // open forever.
    Timer {
        id: pairTimeout
        interval: 30000
        onTriggered: if (pairProc.running) pairProc.running = false
    }

    // one entry point for the adapter toggle. a blocked radio is unblocked
    // first (/dev/rfkill is seat-writable via systemd uaccess, no root), and
    // powered on when the unblock lands; everything else is a plain flip.
    function setAdapterEnabled(v) {
        if (!root.adapter)
            return;
        if (v && (root.blocked || unblockProc.running)) {
            if (!unblockProc.running)
                unblockProc.running = true;
            return;
        }
        root.adapter.enabled = v;
    }

    // flip discovery, (re)arming the 25s auto-stop so a forgotten scan doesn't
    // keep the radio busy forever.
    function toggleScan() {
        if (!root.adapter)
            return;
        root.adapter.discovering = !root.adapter.discovering;
        if (root.adapter.discovering)
            scanTimer.restart();
        else
            scanTimer.stop();
    }

    // start a scan, or restart the 25s window if one is already running. for
    // refresh buttons: unlike toggleScan, a second press never cancels it.
    function startScan() {
        if (!root.adapter || root.adapter.enabled !== true)
            return;
        root.adapter.discovering = true;
        scanTimer.restart();
    }

    // a surface losing visibility (tab switch, popout close) calls this so
    // BlueZ isn't left chewing the radio in the background.
    function stopScan() {
        scanTimer.stop();
        if (root.adapter && root.adapter.discovering)
            root.adapter.discovering = false;
    }

    // revive a stopped bluetoothd (service disabled by hand, or an install
    // predating the bluez dependency). pkexec raises the polkit prompt
    // (hyprpolkitagent); enable --now so it also survives the next boot.
    function startService() {
        if (svcProc.running)
            return;
        root.serviceFailed = false;
        svcProc.running = true;
    }

    Timer {
        id: scanTimer
        interval: 25000
        repeat: false
        onTriggered: if (root.adapter) root.adapter.discovering = false
    }

    Timer {
        id: failTimer
        interval: 4000
        repeat: false
        onTriggered: root.failedAddress = ""
    }

    Timer {
        id: svcFailTimer
        interval: 6000
        repeat: false
        onTriggered: root.serviceFailed = false
    }

    Process {
        id: pairProc
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line.indexOf("(yes/no)") !== -1) {
                    pairProc.write("yes\n");
                } else if (line.indexOf("Pairing successful") !== -1) {
                    root._pairSucceeded = true;
                    pairProc.write("trust " + root.pairingAddress + "\nconnect " + root.pairingAddress + "\nquit\n");
                } else if (line.indexOf("Failed to pair") !== -1) {
                    pairProc.write("quit\n");
                }
            }
        }
        stderr: StdioCollector {}
        onStarted: pairProc.write("agent DisplayYesNo\ndefault-agent\npair " + root.pairingAddress + "\n")
        onExited: function(exitCode) {
            pairTimeout.stop();
            var addr = root.pairingAddress;
            root.pairingAddress = "";
            if (!root._pairSucceeded) {
                root.failedAddress = addr;
                failTimer.restart();
            }
        }
    }

    // rfkill unblock, then power the adapter once the radio is free.
    Process {
        id: unblockProc
        command: ["rfkill", "unblock", "bluetooth"]
        onExited: if (root.adapter) root.adapter.enabled = true
    }

    Process {
        id: svcProc
        command: ["pkexec", "systemctl", "enable", "--now", "bluetooth.service"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.serviceFailed = true;
                svcFailTimer.restart();
            }
        }
    }
}
