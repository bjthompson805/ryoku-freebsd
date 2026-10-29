pragma Singleton
import QtQuick
import Quickshell

// light network presence for the bar's status cluster: connection kind
// (ethernet/wifi/none) and wifi signal. Reactive off WifiLink's watcher --
// the same `ryoku-shell wifi watch` stream Link.qml drives its rows from --
// so this updates the instant the route or the supplicant changes, with no
// poll of its own.
Singleton {
    id: root

    readonly property var st: WifiLink.st

    // "ethernet" | "wifi" | "" (offline). any default route off a wlan
    // interface counts as ethernet, USB tethering included.
    readonly property string kind: st.wired ? "ethernet" : (st.ssid ? "wifi" : "")
    // 0..1 wifi signal, meaningful while kind === "wifi"
    readonly property real level: st.signal || 0
    // a box without Wi-Fi never shows the radio as off.
    readonly property bool wifiRadio: !WifiLink.present || WifiLink.wifiOn
}
