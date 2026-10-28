pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// network throughput readout for the bar: download over upload, off the
// NetSpeed singleton (default-route interface, /proc/net/dev deltas). stacked
// two-line like a waybar custom/network_traffic module. keeps the poller
// awake while shown. the value column is pinned to the widest reading
// (NetSpeed._fmt never exceeds "1023.9 KB/s"-length text), so a scale change
// -- B/s to KB/s to MB/s -- never reflows the module width and shifts
// whatever rides beside it. click either row to open the traffic popout.
Column {
    id: netSpeed

    property real s: 1

    signal requestPopout(string name, real center)

    spacing: 1 * s

    readonly property real valueWidth: valueMetrics.implicitWidth
    Text {
        id: valueMetrics
        visible: false
        text: "1023.9 KB/s"
        font.family: Theme.font
        font.pixelSize: 8.5 * netSpeed.s
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }

    Component.onCompleted: NetSpeed.active = true
    Component.onDestruction: NetSpeed.active = false

    function open(item) {
        const p = item.mapToItem(null, item.width / 2, item.height / 2);
        netSpeed.requestPopout("netspeed", p.x);
    }

    component SpeedRow: Item {
        id: it
        property string glyph: ""
        property string value: ""
        implicitWidth: itRow.implicitWidth
        implicitHeight: itRow.implicitHeight

        Row {
            id: itRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * netSpeed.s

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: it.glyph
                fill: 1
                color: Theme.subtle
                font.pixelSize: 10 * netSpeed.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: netSpeed.valueWidth
                text: it.value
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 8.5 * netSpeed.s
                font.weight: Font.Medium
                font.features: ({ "tnum": 1 })
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: netSpeed.open(it)
        }
    }

    SpeedRow { glyph: "arrow_downward"; value: NetSpeed.rxLabel }
    SpeedRow { glyph: "arrow_upward"; value: NetSpeed.txLabel }
}
