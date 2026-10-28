pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Networking
import ".."
import "../Singletons"

// network popout content: an ethernet status line (when wired) and a wifi
// status line (when associated) -- both can show at once, since a box can be
// on ethernet and wifi simultaneously -- sitting over a compact wifi control
// center that reuses the LinkWifi drill-in with its surface-only chrome
// stripped (no back chevron, no hotspot block). the bar's status icon already
// knows wired vs wifi via the lightweight Network singleton, but LinkWifi
// only ever talks wifi -- so a wired box used to open this popout and see
// nothing but "Searching networks…". the status rows here read the same
// Quickshell.Networking devices Link.qml's main view uses for kind/speed/
// SSID/signal, plus a per-interface `ip addr` lookup for the IP (the QML
// device's own "address" property is its MAC, not an IP) so eth and wifi
// never share one "the" IP. a wifi header eyebrow over LinkWifi's live
// enable toggle, rescan, signal-sorted network list and inline password
// connect. plain transparent
// Item -- the frame blob behind it IS the surface; Popout reads the reported
// implicit size to melt open to fit and grows as the list fills or a
// password row expands. pointer-driven, no keyboard focus.
Item {
    id: root

    property real s: 1
    // popout open: gates LinkWifi's live scanner so nmcli never spins while closed.
    property bool open: false

    anchors.fill: parent

    readonly property var netDevices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var eth: netDevices.find(function(d) { return d && d.type === DeviceType.Wired && d.connected }) || null
    readonly property bool wired: eth !== null

    readonly property real ethSpeed: (eth && eth.linkSpeed) ? eth.linkSpeed : 0
    readonly property string ethSpeedText: ethSpeed > 0
        ? (ethSpeed >= 1000 ? (ethSpeed / 1000).toFixed(ethSpeed % 1000 === 0 ? 0 : 1) + " Gb/s" : ethSpeed + " Mb/s")
        : ""

    readonly property var wifiDev: netDevices.find(function(d) { return d && d.type === DeviceType.Wifi }) || null
    readonly property bool wifiOn: (typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : false
    readonly property var wifiNets: (wifiDev && wifiDev.networks) ? wifiDev.networks.values : []
    readonly property var wifiActive: wifiNets.find(function(n) { return n && n.connected }) || null
    readonly property bool wifiConnected: wifiActive !== null

    readonly property string wifiSignalText: wifiActive && wifiActive.signalStrength
        ? Math.round(wifiActive.signalStrength * 100) + "%"
        : ""

    // NetworkDevice.address is the interface's MAC, not an IP -- ask `ip`
    // per interface name instead, so eth and wifi never fight over one
    // shared "the" IP when both links are up at once.
    readonly property string ethIface: eth ? eth.name : ""
    readonly property string wifiIface: wifiDev ? wifiDev.name : ""

    property string ethIp: ""
    property string wifiIp: ""

    function ipCommand(iface) {
        return ["sh", "-c",
            "ip -4 -o addr show dev \"$1\" scope global up | awk '{for(i=1;i<=NF;i++) if($i==\"inet\"){print $(i+1); exit}}' | cut -d/ -f1",
            "sh", iface];
    }

    function refreshIps() {
        if (ethIface.length) {
            ethIpProc.command = ipCommand(ethIface);
            ethIpProc.running = true;
        } else {
            ethIp = "";
        }
        if (wifiIface.length) {
            wifiIpProc.command = ipCommand(wifiIface);
            wifiIpProc.running = true;
        } else {
            wifiIp = "";
        }
    }

    Process {
        id: ethIpProc
        stdout: StdioCollector { onStreamFinished: root.ethIp = this.text.trim() }
    }

    Process {
        id: wifiIpProc
        stdout: StdioCollector { onStreamFinished: root.wifiIp = this.text.trim() }
    }

    Timer {
        interval: 15000
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshIps()
    }

    readonly property string ethSubText: "Ethernet"
        + (ethSpeedText.length ? " · " + ethSpeedText : "")
        + (ethIp.length ? " · " + ethIp : "")
    readonly property string wifiSubText: (wifiActive && wifiActive.name ? wifiActive.name : "Wi-Fi")
        + (wifiSignalText.length ? " · " + wifiSignalText : "")
        + (wifiIp.length ? " · " + wifiIp : "")

    implicitWidth: 300 * s
    implicitHeight: body.implicitHeight + 27 * s

    Column {
        id: body
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 13 * root.s
        anchors.leftMargin: 16 * root.s
        anchors.rightMargin: 16 * root.s
        spacing: 11 * root.s

        Row {
            spacing: 8 * root.s
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.wired ? "lan" : "wifi"
                fill: 1
                color: Theme.brand
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "NETWORK"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }

        Item {
            visible: root.wired
            width: parent.width
            height: visible ? 30 * root.s : 0

            MaterialIcon {
                id: ethGlyph
                anchors.left: parent.left
                anchors.leftMargin: 2 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 17 * root.s
                height: 17 * root.s
                text: "lan"
                fill: 1
                color: Theme.vermLit
                font.pixelSize: 15 * root.s
            }

            Text {
                anchors.left: ethGlyph.right
                anchors.leftMargin: 11 * root.s
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.ethSubText
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        Item {
            visible: root.wifiConnected
            width: parent.width
            height: visible ? 30 * root.s : 0

            MaterialIcon {
                id: wifiStatusGlyph
                anchors.left: parent.left
                anchors.leftMargin: 2 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 17 * root.s
                height: 17 * root.s
                text: "wifi"
                fill: 1
                color: Theme.vermLit
                font.pixelSize: 15 * root.s
            }

            Text {
                anchors.left: wifiStatusGlyph.right
                anchors.leftMargin: 11 * root.s
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.wifiSubText
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        LinkWifi {
            compact: true
            s: root.s
            active: root.open
            enabled: root.open
            width: parent.width
        }
    }
}
