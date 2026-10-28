pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../Singletons"

// traffic popout content: the download / upload rate readout behind the bar's
// net-speed module, grown from the bar edge. each direction is an eyebrow +
// hero value with a bar sparkline off the NetSpeed rate history, scaled to
// its own recent peak (a byte rate has no natural ceiling like a percentage
// does), then the cumulative session usage. a bare transparent Item -- the
// Popout blob behind it IS the surface; this panel only reports its implicit
// size.
Item {
    id: root

    property real s: 1
    property bool open: false

    anchors.fill: parent

    implicitWidth: 240 * s
    implicitHeight: body.implicitHeight + 27 * s

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.hair
    }

    // one direction: eyebrow label + hero value on its baseline, then a bar
    // sparkline of the recent rate history scaled to its own peak (floored so
    // idle traffic doesn't read as a wall of full-height noise).
    component Metric: Column {
        id: metric
        property string label: ""
        property string value: ""
        property var series: []
        readonly property real peak: Math.max.apply(null, [64 * 1024].concat(metric.series))

        width: parent ? parent.width : 0
        spacing: 6 * root.s

        Item {
            width: parent.width
            height: mLabel.implicitHeight
            Text {
                id: mLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: metric.label
                color: Theme.subtle
                font.family: Theme.mono
                font.pixelSize: 9 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2 * root.s
            }
            Text {
                anchors.right: parent.right
                anchors.baseline: mLabel.baseline
                text: metric.value
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 14 * root.s
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }

        Row {
            id: spark
            width: parent.width
            height: 18 * root.s
            spacing: 1.5 * root.s

            readonly property int shown: Math.min(metric.series.length, 44)
            readonly property real barW: shown > 0 ? (width - (shown - 1) * spacing) / shown : 0

            Repeater {
                model: spark.shown
                delegate: Rectangle {
                    required property int index
                    readonly property real v: metric.series[metric.series.length - spark.shown + index]
                    width: spark.barW
                    height: Math.max(1, spark.height * Math.min(1, v / metric.peak))
                    y: spark.height - height
                    radius: width / 2
                    color: Theme.verm
                    opacity: 0.35 + 0.65 * (index / Math.max(1, spark.shown - 1))
                }
            }
        }
    }

    // one session-usage row: eyebrow label left, total right.
    component TotalRow: Item {
        id: totalRow
        property string label: ""
        property string value: ""
        width: parent ? parent.width : 0
        height: tLabel.implicitHeight

        Text {
            id: tLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: totalRow.label
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: totalRow.value
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }

    Column {
        id: body
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 13 * root.s
        anchors.leftMargin: 16 * root.s
        anchors.rightMargin: 16 * root.s
        spacing: 11 * root.s

        // header: brand glyph + eyebrow, the popout idiom.
        Row {
            spacing: 8 * root.s
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "swap_vert"
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

        Metric { label: "Download"; value: NetSpeed.rxLabel; series: NetSpeed.rxHistory }
        Metric { label: "Upload"; value: NetSpeed.txLabel; series: NetSpeed.txHistory }

        Divider {}

        Text {
            text: "SESSION USAGE"
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.4 * root.s
        }

        TotalRow { label: "Downloaded"; value: NetSpeed.rxTotalLabel }
        TotalRow { label: "Uploaded"; value: NetSpeed.txTotalLabel }
    }
}
