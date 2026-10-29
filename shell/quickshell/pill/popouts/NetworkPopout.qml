pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
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
// WifiLink state Link.qml's main view uses for kind/speed/SSID/signal, plus
// a per-interface `ifconfig` lookup for the IP so eth and wifi never share
// one "the" IP. a wifi header eyebrow over LinkWifi's live
// enable toggle, rescan, signal-sorted network list and inline password
// connect. plain transparent
// Item -- the frame blob behind it IS the surface; Popout reads the reported
// implicit size to melt open to fit and grows as the list fills or a
// password row expands. pointer-driven, no keyboard focus.
Item {
    id: root

    property real s: 1
    // popout open: gates LinkWifi's rescans so they never run while closed.
    property bool open: false

    anchors.fill: parent

    readonly property bool wired: WifiLink.st.wired

    readonly property real ethSpeed: WifiLink.st.speed || 0
    readonly property string ethSpeedText: ethSpeed > 0
        ? (ethSpeed >= 1000 ? (ethSpeed / 1000).toFixed(ethSpeed % 1000 === 0 ? 0 : 1) + " Gb/s" : ethSpeed + " Mb/s")
        : ""

    readonly property bool wifiOn: WifiLink.wifiOn
    readonly property var wifiActive: WifiLink.active
    readonly property bool wifiConnected: wifiActive !== null

    readonly property string wifiSignalText: wifiActive && wifiActive.signalStrength
        ? Math.round(wifiActive.signalStrength * 100) + "%"
        : ""

    // ask `ifconfig` per interface name, so eth and wifi never fight over
    // one shared "the" IP when both links are up at once.
    readonly property string ethIface: wired ? WifiLink.st.route : ""
    readonly property string wifiIface: WifiLink.st.iface

    property string ethIp: ""
    property string wifiIp: ""

    function ipCommand(iface) {
        return ["sh", "-c",
            "ifconfig \"$1\" inet 2>/dev/null | awk '$1==\"inet\"{print $2; exit}'",
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
            visible: WifiLink.present
            active: root.open && WifiLink.present
            enabled: root.open
            width: parent.width
        }
    }
}
