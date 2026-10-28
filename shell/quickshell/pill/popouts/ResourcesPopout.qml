pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."
import "../Singletons"

// resources popout content: the CPU / memory / temperature readout behind the
// Nacre stats module, grown from the bar edge. each metric is an eyebrow + hero
// value with a bar sparkline from the SysStats history, then the top processes
// by CPU. a bare transparent Item -- the Popout blob behind it IS the surface;
// this panel only reports its implicit size. pointer-driven, no keyboard focus.
Item {
    id: root

    property real s: 1
    // popout open: gates the process sampler so `ps` never spins while closed.
    property bool open: false

    anchors.fill: parent

    implicitWidth: 260 * s
    implicitHeight: body.implicitHeight + 27 * s

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.hair
    }

    // one metric: eyebrow label + hero value on its baseline, then a bar
    // sparkline of the recent history (newest at the right).
    component Metric: Column {
        id: metric
        property string label: ""
        property string value: ""
        property var series: []
        property real max: 100
        property bool warn: false

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
                color: metric.warn ? Theme.vermLit : Theme.cream
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
                    height: Math.max(1, spark.height * Math.min(1, v / metric.max))
                    y: spark.height - height
                    radius: width / 2
                    color: metric.warn ? Theme.vermLit : Theme.verm
                    opacity: 0.35 + 0.65 * (index / Math.max(1, spark.shown - 1))
                }
            }
        }
    }

    // one core: index caption over a small usage bar, warn-tinted like the
    // other metrics past the same 85% threshold.
    component CoreCell: Column {
        id: cell
        property int index: 0
        property int pct: 0
        readonly property bool warn: cell.pct > 85
        width: (parent.width - 3 * 6 * root.s) / 4
        spacing: 3 * root.s

        Text {
            text: "C" + cell.index
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 8 * root.s
            font.weight: Font.DemiBold
        }
        Rectangle {
            width: parent.width
            height: 5 * root.s
            radius: height / 2
            color: Theme.hair
            Rectangle {
                width: parent.width * Math.min(1, cell.pct / 100)
                height: parent.height
                radius: parent.radius
                color: cell.warn ? Theme.vermLit : Theme.verm
            }
        }
        Text {
            text: cell.pct + "%"
            color: cell.warn ? Theme.vermLit : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 8.5 * root.s
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
        }
    }

    // one GPU engine: short name caption over a small usage bar, same
    // warn-tinted styling as CoreCell. width is assigned externally by the
    // engine row so the whole set fits one line regardless of engine count.
    component EngineCell: Column {
        id: ecell
        property string name: ""
        property int pct: 0
        readonly property bool warn: ecell.pct > 85
        spacing: 3 * root.s

        Text {
            width: parent.width
            text: ecell.name.toUpperCase()
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 7.5 * root.s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Rectangle {
            width: parent.width
            height: 5 * root.s
            radius: height / 2
            color: Theme.hair
            Rectangle {
                width: parent.width * Math.min(1, ecell.pct / 100)
                height: parent.height
                radius: parent.radius
                color: ecell.warn ? Theme.vermLit : Theme.verm
            }
        }
        Text {
            text: ecell.pct + "%"
            color: ecell.warn ? Theme.vermLit : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 8 * root.s
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
        }
    }

    // one disk I/O rate: short name caption over a small usage bar, same
    // styling as EngineCell but fed a pre-formatted rate string and a
    // fill fraction instead of a raw percent (throughput has no natural
    // 0-100 scale).
    component RateCell: Column {
        id: rcell
        property string name: ""
        property string valueText: ""
        property real frac: 0
        width: parent ? parent.width : 0
        spacing: 3 * root.s

        Text {
            width: parent.width
            text: rcell.name
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 7.5 * root.s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Rectangle {
            width: parent.width
            height: 5 * root.s
            radius: height / 2
            color: Theme.hair
            Rectangle {
                width: parent.width * Math.min(1, rcell.frac)
                height: parent.height
                radius: parent.radius
                color: Theme.verm
            }
        }
        Text {
            text: rcell.valueText
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 8 * root.s
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
        }
    }

    // disk usage: a plain snapshot rather than a history sparkline (the
    // number barely moves), so it gets a single static fill bar plus a
    // used/total caption instead of the ticking Metric treatment.
    component DiskStat: Column {
        id: disk
        width: parent ? parent.width : 0
        spacing: 6 * root.s

        Item {
            width: parent.width
            height: dLabel.implicitHeight
            Text {
                id: dLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "DISK"
                color: Theme.subtle
                font.family: Theme.mono
                font.pixelSize: 9 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2 * root.s
            }
            Text {
                anchors.right: parent.right
                anchors.baseline: dLabel.baseline
                text: SysStats.disk + "%"
                color: SysStats.disk > 90 ? Theme.vermLit : Theme.cream
                font.family: Theme.font
                font.pixelSize: 14 * root.s
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }

        Rectangle {
            width: parent.width
            height: 5 * root.s
            radius: height / 2
            color: Theme.hair
            Rectangle {
                width: parent.width * Math.min(1, SysStats.disk / 100)
                height: parent.height
                radius: parent.radius
                color: SysStats.disk > 90 ? Theme.vermLit : Theme.verm
            }
        }

        Text {
            visible: SysStats.diskUsed.length > 0
            anchors.right: parent.right
            text: SysStats.diskUsed + " / " + SysStats.diskTotal
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
        }

        Row {
            id: ioRow
            visible: SysStats.diskIOAvailable
            width: parent.width
            spacing: 6 * root.s

            RateCell {
                width: (ioRow.width - ioRow.spacing) / 2
                name: "READ"
                valueText: SysStats.fmtRate(SysStats.diskReadRate)
                frac: SysStats.diskReadRate / SysStats.diskIOMaxBps
            }
            RateCell {
                width: (ioRow.width - ioRow.spacing) / 2
                name: "WRITE"
                valueText: SysStats.fmtRate(SysStats.diskWriteRate)
                frac: SysStats.diskWriteRate / SysStats.diskIOMaxBps
            }
        }
    }

    // top processes by CPU, one row each: tabular percent + command.
    component ProcRow: Item {
        id: procRow
        property string pct: ""
        property string name: ""
        width: parent ? parent.width : 0
        height: pctText.implicitHeight
        Text {
            id: pctText
            anchors.left: parent.left
            width: 40 * root.s
            text: procRow.pct + "%"
            color: Theme.subtle
            font.family: Theme.mono
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
        }
        Text {
            anchors.left: pctText.right
            anchors.right: parent.right
            anchors.baseline: pctText.baseline
            text: procRow.name
            elide: Text.ElideRight
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
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

        // header: brand glyph + RESOURCES eyebrow, the popout idiom.
        Row {
            spacing: 8 * root.s
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "monitor_heart"
                fill: 1
                color: Theme.brand
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "RESOURCES"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }

        Metric { label: "CPU"; value: SysStats.cpu + "%"; series: SysStats.cpuHistory; warn: SysStats.cpu > 85 }

        Grid {
            id: coreGrid
            visible: SysStats.cpuPerCore.length > 0
            width: parent.width
            columns: 4
            columnSpacing: 6 * root.s
            rowSpacing: 8 * root.s

            Repeater {
                model: SysStats.cpuPerCore
                delegate: CoreCell {
                    required index
                    required property int modelData
                    pct: modelData
                }
            }
        }

        Metric {
            visible: SysStats.gpuAvailable
            label: "GPU"
            value: SysStats.gpu + "%"
            series: SysStats.gpuHistory
            warn: SysStats.gpu > 85
        }

        Row {
            id: engineRow
            visible: SysStats.gpuEngines.length > 0
            width: parent.width
            spacing: 6 * root.s

            Repeater {
                model: SysStats.gpuEngines
                delegate: EngineCell {
                    required property var modelData
                    width: (engineRow.width - (SysStats.gpuEngines.length - 1) * engineRow.spacing) / Math.max(1, SysStats.gpuEngines.length)
                    name: modelData.name
                    pct: modelData.pct
                }
            }
        }

        Metric {
            visible: SysStats.npuAvailable
            label: "NPU"
            value: SysStats.npu + "%"
            series: SysStats.npuHistory
            warn: SysStats.npu > 85
        }
        Metric { label: "Memory"; value: SysStats.mem + "%"; series: SysStats.memHistory; warn: SysStats.mem > 90 }
        Metric {
            visible: SysStats.tempAvailable
            label: "Temp"
            value: SysStats.temp + "\u00b0C"
            series: SysStats.tempHistory
            warn: SysStats.temp > 80
        }
        DiskStat { visible: SysStats.diskAvailable }

        Divider {}

        Text {
            text: "TOP PROCESSES"
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.4 * root.s
        }

        Column {
            id: procList
            property var rows: []
            width: parent.width
            spacing: 5 * root.s

            Repeater {
                model: procList.rows
                delegate: ProcRow {
                    required property var modelData
                    pct: modelData.pct
                    name: modelData.name
                }
            }
        }
    }

    // sample the top processes only while the popout is mounted and open.
    Process {
        id: psProc
        // a freshly-forked process's %cpu (ps's own busy-since-start / age-since-
        // start ratio) is unstable while its age is near zero, so the sampler
        // routinely samples *itself* pegged near 100%. drop its own sh/ps pair.
        command: ["sh", "-c", "ps -eo pcpu,comm --sort=-pcpu --no-headers | grep -Ev '^ *[0-9.]+ (ps|sh)$' | head -5"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [];
                (this.text || "").trim().split("\n").forEach(function (ln) {
                    var m = ln.trim().match(/^([\d.]+)\s+(.*)$/);
                    if (m)
                        out.push({ pct: m[1], name: m[2] });
                });
                procList.rows = out;
            }
        }
    }
    Timer {
        interval: 2500
        repeat: true
        running: root.open
        triggeredOnStart: true
        onTriggered: psProc.running = true
    }
}
