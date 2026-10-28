pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// light network presence for the bar's status cluster: connection kind
// (ethernet/wifi/none) and wifi signal. Reactive off Quickshell.Networking's
// NetworkManager binding -- the same D-Bus-backed source Link.qml drives its
// rows from -- so this updates the instant NM reports a change. Used to poll
// nmcli every 30s instead, which meant plugging in ethernet or a wifi AP
// could sit unreflected in the bar for up to half a minute; this is both
// faster and cheaper (no periodic subprocess spawn).
Singleton {
    id: root

    readonly property var devices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var eth: devices.find(function(d) { return d && d.type === DeviceType.Wired && d.connected; }) || null
    readonly property var wifiDev: devices.find(function(d) { return d && d.type === DeviceType.Wifi && d.connected; }) || null
    readonly property var wifiActive: (wifiDev && wifiDev.networks) ? (wifiDev.networks.values.find(function(n) { return n && n.connected; }) || null) : null

    // "ethernet" | "wifi" | "" (offline / no NM)
    readonly property string kind: eth ? "ethernet" : (wifiDev ? "wifi" : "")
    // 0..1 wifi signal, meaningful while kind === "wifi"
    readonly property real level: (wifiActive && wifiActive.signalStrength) || 0
    readonly property bool wifiRadio: (typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : true
}
