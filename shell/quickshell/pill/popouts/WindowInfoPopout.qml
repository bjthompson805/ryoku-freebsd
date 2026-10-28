pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import ".."
import "../Singletons"

// window-info popout: opened from the bar's title module, a readout of the
// window Hyprland is tracking behind that title (class, workspace, monitor,
// geometry, floating/fullscreen state) and the process driving it (pid,
// command line, live CPU/memory from `ps`), so an unfamiliar title is never a
// mystery. sourced off Hyprland.activeToplevel -- the Hyprland-specific
// toplevel, not the generic ToplevelManager one BarTitle itself renders off
// -- because only its lastIpcObject carries pid/class/geometry (see
// Singletons/Apps.qml's iconFor). a bare transparent Item -- the Popout blob
// behind it IS the surface; this panel only reports its implicit size.
// pointer-driven, no keyboard focus.
Item {
    id: root

    property real s: 1
    // popout open: gates the process sampler so `ps` never spins while closed.
    property bool open: false

    anchors.fill: parent

    // Hyprland.activeToplevel is event-driven (an activewindowv2 IPC event),
    // not queried, so it stays null from shell start until the first focus
    // change -- the same gap Bar.qml seeds around for focusedWorkspace. seed
    // once from hyprctl so the popout is never wrongly "no focused window" on
    // its first open; a live toplevel always wins once an event has landed.
    property var seed: ({})
    Process {
        running: true
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.seed = JSON.parse(text); } catch (e) {}
            }
        }
    }

    readonly property var toplevel: Hyprland.activeToplevel
    readonly property var seedInfo: root.seed && root.seed.pid !== undefined ? root.seed : null
    readonly property bool hasWindow: toplevel !== null || seedInfo !== null
    readonly property var info: toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : (seedInfo || ({}))
    readonly property int pid: info.pid || 0
    readonly property string wmClass: info.class || ""
    readonly property string winTitle: toplevel ? toplevel.title : (seedInfo ? seedInfo.title : "")
    readonly property bool floating: !!info.floating
    readonly property bool fullscreen: !!info.fullscreen
    readonly property bool xwayland: !!info.xwayland
    readonly property var winSize: info.size || [0, 0]
    readonly property string wsName: toplevel && toplevel.workspace ? toplevel.workspace.name : (seedInfo && seedInfo.workspace ? seedInfo.workspace.name : "")
    readonly property string monName: toplevel && toplevel.monitor ? toplevel.monitor.name : (seedInfo ? ("Monitor " + seedInfo.monitor) : "")

    property string procCpu: ""
    property real procRssKb: 0
    property string procCmd: ""

    implicitWidth: 280 * s
    implicitHeight: body.implicitHeight + 27 * s

    function memLabel() {
        if (root.procRssKb <= 0)
            return "";
        const mb = root.procRssKb / 1024;
        return (mb < 10 ? mb.toFixed(1) : Math.round(mb)) + " MB";
    }

    function sample() {
        if (root.pid <= 0) {
            root.procCpu = "";
            root.procRssKb = 0;
            root.procCmd = "";
            return;
        }
        procSampler.command = ["ps", "-o", "pcpu=,rss=,args=", "-p", String(root.pid)];
        procSampler.running = true;
    }
    onPidChanged: if (root.open) root.sample()

    Process {
        id: procSampler
        stdout: StdioCollector {
            onStreamFinished: {
                const m = (this.text || "").trim().match(/^(\S+)\s+(\S+)\s+(.*)$/);
                root.procCpu = m ? m[1] : "";
                root.procRssKb = m ? (parseFloat(m[2]) || 0) : 0;
                root.procCmd = m ? m[3] : "";
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.open
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.hair
    }

    // one attribute: label left, value right (elided if it overruns).
    component InfoRow: Item {
        id: infoRow
        property string label: ""
        property string value: ""
        visible: infoRow.value.length > 0
        width: parent ? parent.width : 0
        height: infoRow.visible ? rLabel.implicitHeight : 0

        Text {
            id: rLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: infoRow.label
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
        }
        Text {
            anchors.left: rLabel.right
            anchors.leftMargin: 10 * root.s
            anchors.right: parent.right
            anchors.baseline: rLabel.baseline
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: infoRow.value
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }

    // a label above a full-width, wrapped mono value -- for the command
    // line, which is too long to sit beside its label on one row.
    component FullValueRow: Column {
        id: fullRow
        property string label: ""
        property string value: ""
        visible: fullRow.value.length > 0
        width: parent ? parent.width : 0
        height: fullRow.visible ? implicitHeight : 0
        spacing: 3 * root.s

        Text {
            text: fullRow.label
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2 * root.s
        }
        Text {
            width: parent.width
            text: fullRow.value
            wrapMode: Text.Wrap
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 9.5 * root.s
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
                text: "select_window"
                fill: 1
                color: Theme.brand
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "WINDOW"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }

        // hero: app icon + the full title, wrapped rather than elided --
        // seeing the whole thing is the point of this popout.
        Row {
            width: parent.width
            spacing: 8 * root.s
            visible: root.hasWindow

            IconImage {
                anchors.top: parent.top
                anchors.topMargin: 2 * root.s
                implicitSize: 16 * root.s
                // gated like sample()/procSampler below -- iconForClass scans every
                // desktop entry plus an icon-theme lookup, real synchronous work
                // this closed-and-invisible popout has no business paying on every
                // single focus change (BarTitle already pays it once, for the
                // visible title icon).
                source: root.open ? Apps.iconForClass(root.wmClass) : ""
            }
            Text {
                width: parent.width - 16 * root.s - 8 * root.s
                text: root.winTitle
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.DemiBold
            }
        }

        Text {
            width: parent.width
            visible: !root.hasWindow
            text: "No focused window"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }

        Divider { visible: root.hasWindow }

        InfoRow { label: "Class"; value: root.wmClass }
        InfoRow { label: "Workspace"; value: root.wsName }
        InfoRow { label: "Monitor"; value: root.monName }
        InfoRow { label: "Size"; value: (root.winSize[0] > 0) ? (root.winSize[0] + " × " + root.winSize[1]) : "" }
        InfoRow { label: "State"; value: !root.hasWindow ? "" : (root.floating ? "Floating" : "Tiled") + (root.fullscreen ? " · Fullscreen" : "") }
        InfoRow { label: "Xwayland"; value: root.xwayland ? "Yes" : "" }

        Divider { visible: root.pid > 0 }
        Text {
            width: parent.width
            visible: root.pid > 0
            text: "PROCESS"
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.4 * root.s
        }

        InfoRow { label: "PID"; value: root.pid > 0 ? String(root.pid) : "" }
        InfoRow { label: "CPU"; value: root.procCpu.length > 0 ? root.procCpu + "%" : "" }
        InfoRow { label: "Memory"; value: root.memLabel() }
        FullValueRow { label: "Command"; value: root.procCmd }
    }
}
