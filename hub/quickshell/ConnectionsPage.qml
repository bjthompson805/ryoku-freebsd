pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// Connections section: Wi-Fi, Bluetooth, Hotspot, each a subtab. the subtab
// bar reuses the hub Segmented control; each tab is self-contained, backed
// by the Quickshell Networking/Bluetooth services (plus nmcli/bluetoothctl).
Item {
    id: page

    property string sub: "wifi"

    Segmented {
        id: tabs
        anchors.left: parent.left
        anchors.top: parent.top
        model: [
            { "key": "wifi", "label": "Wi-Fi" },
            { "key": "bluetooth", "label": "Bluetooth" },
            { "key": "hotspot", "label": "Hotspot" }
        ]
        current: page.sub
        onSelected: (k) => page.sub = k
    }

    Loader {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: tabs.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 22
        sourceComponent: page.sub === "wifi" ? wifiComp
            : (page.sub === "bluetooth" ? btComp : hsComp)
    }

    Component { id: wifiComp; WifiTab {} }
    Component { id: btComp; BluetoothTab {} }
    Component { id: hsComp; HotspotTab {} }
}
