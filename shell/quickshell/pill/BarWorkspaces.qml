pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import "Singletons"

// the workspace indicator, per bar skin.
//   caelestia = one container pill; equal numeral cells inside it with a
//               fully rounded accent indicator sliding behind the active one
//               (emphasized curve, stretchy leading/trailing edges); the
//               numeral over the indicator flips dark.
//   noctalia  = free-standing mini pills, one per workspace: dots for empty,
//               brighter dots for occupied, and the active one grown into a
//               wide accent lozenge carrying its number (width animates).
//   aegis     = numeral cells, the active one marked by an accent underline.
//   stele     = numeral cells, the active one boxed in an engraved frame.
// click jumps, wheel walks neighbours. cells past five appear once used.
// barWorkspaceIcons: an occupied pill/ring swaps its numeral for up to
// maxWsIcons tiny per-window app icons (deduped by class, resolved the same
// way as the overview's WorkspaceCell), growing to fit them; empty
// workspaces are untouched. Only the non-cell dialects (noctalia and its
// siblings, plus nacre) pick this up -- caelestia/aegis/stele's cells share a
// fixed-step sliding accent indicator that assumes uniform cell width, so a
// variable-width cell would need that math reworked; out of scope here.
Item {
    id: strip

    property real s: 1
    property int activeWsId: 1
    property bool vertical: false
    readonly property string style: Config.barStyle
    readonly property bool caelestia: style === "caelestia"
    readonly property bool aegis: style === "aegis"
    readonly property bool stele: style === "stele"
    readonly property bool nacre: style === "nacre"
    readonly property bool cells: caelestia || aegis || stele

    // caelestia cell metrics (inside the container pill).
    readonly property real cellW: vertical ? 21 * s : 24 * s
    readonly property real cellH: vertical ? 24 * s : 21 * s
    readonly property real cellSpan: vertical ? cellH : cellW
    // noctalia pill metrics.
    readonly property real dotSize: 10 * s
    readonly property real activeLen: dotSize * 2.2
    readonly property real dotGap: 4 * s
    // nacre ring metrics.
    readonly property real ringSize: 6 * s
    readonly property real ringActive: 9 * s
    readonly property real ringGap: 5 * s

    // tiny per-window icons: only the non-cell dialects render these.
    readonly property bool wsIconsOn: Config.barWorkspaceIcons && !cells
    readonly property int maxWsIcons: 3
    readonly property real wsIconPx: 9 * s
    readonly property real wsIconGap: 3 * s
    readonly property real wsIconPadAlong: 5 * s
    readonly property real wsIconPadCross: 4 * s
    // uniform cross size for the noctalia row / nacre rings so entries stay
    // aligned whether or not a given one happens to be showing icons.
    readonly property real dotCross: (wsIconsOn && !nacre)
        ? Math.max(dotSize, wsIconPx + 2 * wsIconPadCross) : dotSize
    readonly property real ringCross: (wsIconsOn && nacre)
        ? Math.max(ringActive, wsIconPx + 2 * wsIconPadCross) : ringActive
    property var classesByWs: ({})

    // the along-bar extent a given workspace's entry occupies -- used both by
    // the delegates and by implicitWidth/Height below, so the module's
    // reserved band always matches what's actually drawn.
    function wsAlong(id) {
        if (cells)
            return vertical ? cellH : cellW;
        var arr = wsIconsOn ? (classesByWs[id] || []) : [];
        if (arr.length === 0)
            return nacre ? ringActive : (id === activeWsId ? activeLen : dotSize);
        return arr.length * wsIconPx + Math.max(0, arr.length - 1) * wsIconGap + 2 * wsIconPadAlong;
    }

    // icon path resolution: same two-step lookup as the overview's WorkspaceCell.
    function iconFor(className) {
        if (!className)
            return "";
        const desktop = DesktopEntries.heuristicLookup(className);
        const byEntry = (desktop && desktop.icon) ? Quickshell.iconPath(desktop.icon, true) : "";
        return byEntry !== "" ? byEntry : Quickshell.iconPath(className.toLowerCase(), true);
    }

    readonly property int base: Math.floor((activeWsId - 1) / 10) * 10
    // occupancy = which workspaces own a window, from hyprctl. Quickshell's
    // bulk refresh doesn't parse this Hyprland's IPC, so its own workspace and
    // toplevel models only track what changed since the shell started and miss
    // windows opened before a reload. re-query at startup and on any
    // window/workspace event so occupied-only is always right.
    property var occupiedSet: ({})
    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var occ = {};
                    var byWs = {};
                    var cs = JSON.parse(this.text);
                    for (var i = 0; i < cs.length; i++) {
                        var w = cs[i].workspace;
                        if (!w || !(w.id > 0))
                            continue;
                        occ[w.id] = true;
                        if (strip.wsIconsOn) {
                            var arr = byWs[w.id] || (byWs[w.id] = []);
                            var cls = Apps.resolveIconKey(cs[i].class || "", cs[i].title || cs[i].initialTitle || "");
                            if (cls && arr.indexOf(cls) < 0 && arr.length < strip.maxWsIcons)
                                arr.push(cls);
                        }
                    }
                    strip.occupiedSet = occ;
                    strip.classesByWs = byWs;
                } catch (e) {}
            }
        }
    }
    Timer { id: occDebounce; interval: 80; onTriggered: clientsProc.running = true }
    Component.onCompleted: clientsProc.running = true
    // classesByWs is only populated while wsIconsOn is true (see above), so
    // flipping the setting on needs its own re-query -- otherwise it stays
    // empty (numerals keep showing despite the pill already having resized)
    // until the next window/workspace event happens to trigger one.
    onWsIconsOnChanged: clientsProc.running = true
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var n = event.name;
            if (n === "openwindow" || n === "closewindow" || n.indexOf("movewindow") === 0
                || n.indexOf("createworkspace") === 0 || n.indexOf("destroyworkspace") === 0)
                occDebounce.restart();
        }
    }
    // classesByWs resolves each window's class through Apps.resolveIconKey,
    // which for Proton/Steam wrapper classes depends on DesktopEntries having
    // scanned far enough to know about the title-matched .desktop entry.
    // that scan runs asynchronously and can still be in progress when this
    // component completes (or when a window opens right at shell startup),
    // so a resolution done too early gets permanently stuck on the raw
    // wrapper class until some window event happens to re-trigger it. re-run
    // the resolution whenever the desktop entry list changes so a late-
    // arriving entry still gets picked up.
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { occDebounce.restart(); }
    }
    // which workspaces to show. occupied-only (the default) lists the ones
    // with windows plus the active one, so empty numbers vanish; otherwise a
    // contiguous 1..N run (N grows past 5 as higher spaces get used) with
    // empties dimmed.
    readonly property var wsList: {
        var out = [];
        if (Config.barOccupiedWorkspaces) {
            // fill gaps below the highest occupied workspace too, so an empty
            // ws2 still shows when ws3 has windows -- only the tail past the
            // last occupied one (or the active one, if it sits further out)
            // stays collapsed.
            var maxOccupied = 0;
            for (var i = 1; i <= 10; i++) {
                if (occupiedSet[base + i])
                    maxOccupied = i;
            }
            for (var j = 1; j <= 10; j++) {
                var id = base + j;
                if (j <= maxOccupied || id === activeWsId)
                    out.push(id);
            }
            if (out.length === 0)
                out.push(activeWsId);
        } else {
            var n = 5;
            for (var j = 10; j > 5; j--) {
                if (occupiedSet[base + j] || activeWsId === base + j) { n = j; break; }
            }
            for (var k = 1; k <= n; k++)
                out.push(base + k);
        }
        return out;
    }
    readonly property int count: wsList.length
    readonly property int activeIdx: Math.max(0, wsList.indexOf(activeWsId))

    // sum of each entry's along-bar extent + the gaps between them; unaffected
    // by icons unless wsIconsOn actually grew some entry past its base size.
    readonly property real wsRunExtent: {
        var sum = 0;
        for (var i = 0; i < wsList.length; i++)
            sum += wsAlong(wsList[i]);
        var gap = nacre ? ringGap : (cells ? 0 : dotGap);
        return sum + Math.max(0, wsList.length - 1) * gap;
    }
    readonly property real crossExtent: nacre ? ringCross : cells ? (vertical ? cellW : cellH) : dotCross

    implicitWidth: vertical ? crossExtent : wsRunExtent
    implicitHeight: vertical ? wsRunExtent : crossExtent

    function jump(id) {
        Hyprland.dispatch('hl.dsp.workspace.move({ workspace = ' + id + ', monitor = "current" })');
        Hyprland.dispatch('hl.dsp.focus({ workspace = ' + id + ' })');
    }
    function walk(dir) {
        var i = strip.activeIdx + dir;
        if (i >= 0 && i < strip.wsList.length)
            strip.jump(strip.wsList[i]);
    }
    WheelHandler {
        onWheel: (w) => strip.walk(w.angleDelta.y > 0 ? -1 : 1)
    }

    // one tiny app icon, shared by the noctalia and nacre icon rows/columns.
    Component {
        id: wsIconD
        IconImage {
            required property string modelData
            implicitSize: strip.wsIconPx
            source: strip.iconFor(modelData)
        }
    }

    // ---- numeral cells: caelestia, aegis, stele --------------------------
    Item {
        visible: strip.cells
        anchors.fill: parent

        // sliding accent indicator: fully rounded, inset a hair inside the
        // container, leading edge chasing fast and trailing edge settling on
        // the emphasized curve so a switch stretches across and contracts.
        Item {
            readonly property real inset: 2.5 * strip.s
            readonly property real target: strip.activeIdx * strip.cellSpan
            property real lead: target
            property real trailEdge: target
            onTargetChanged: {
                lead = target;
                trailEdge = target;
            }
            Behavior on lead {
                NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedCurve }
            }
            Behavior on trailEdge {
                NumberAnimation { duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedCurve }
            }

            x: strip.vertical ? inset : Math.min(lead, trailEdge) + inset
            y: strip.vertical ? Math.min(lead, trailEdge) + inset : inset
            width: (strip.vertical ? strip.cellW : Math.abs(lead - trailEdge) + strip.cellW) - 2 * inset
            height: (strip.vertical ? Math.abs(lead - trailEdge) + strip.cellH : strip.cellH) - 2 * inset

            Rectangle {
                visible: strip.caelestia
                anchors.fill: parent
                radius: Math.min(width, height) / 2
                color: Theme.verm
            }
            Rectangle {
                visible: strip.stele
                anchors.fill: parent
                color: "transparent"
                border.width: Math.max(1, strip.s)
                border.color: Theme.verm
            }
            Rectangle {
                visible: strip.aegis
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(2, 2 * strip.s)
                color: Theme.verm
            }
        }

        Grid {
            columns: strip.vertical ? 1 : strip.count
            Repeater {
                model: strip.wsList
                delegate: Item {
                    id: cCell
                    required property int modelData
                    readonly property int wsId: cCell.modelData
                    readonly property bool active: cCell.wsId === strip.activeWsId
                    readonly property bool occupied: strip.occupiedSet[wsId] === true
                    width: strip.cellW
                    height: strip.cellH

                    Text {
                        anchors.centerIn: parent
                        text: cCell.wsId - strip.base
                        color: cCell.active ? (strip.caelestia ? Theme.cardBot : Theme.verm)
                            : (cCell.occupied ? Theme.cream : Qt.alpha(Theme.subtle, 0.45))
                        font.family: strip.caelestia ? Theme.font : Theme.mono
                        font.pixelSize: 10.5 * strip.s
                        font.weight: cCell.active ? Font.Bold : Font.Medium
                        font.features: ({ "tnum": 1 })
                        Behavior on color { ColorAnimation { duration: Motion.effects } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: strip.jump(cCell.wsId)
                    }
                }
            }
        }
    }

    // ---- noctalia dialect ---------------------------------------------------
    Grid {
        visible: !strip.cells && !strip.nacre
        anchors.centerIn: parent
        columns: strip.vertical ? 1 : strip.count
        columnSpacing: strip.dotGap
        rowSpacing: strip.dotGap
        verticalItemAlignment: Grid.AlignVCenter
        horizontalItemAlignment: Grid.AlignHCenter

        Repeater {
            model: strip.wsList
            delegate: Rectangle {
                id: nPill
                required property int modelData
                readonly property int wsId: nPill.modelData
                readonly property bool active: nPill.wsId === strip.activeWsId
                readonly property bool occupied: strip.occupiedSet[wsId] === true
                readonly property var classes: strip.wsIconsOn ? (strip.classesByWs[wsId] || []) : []
                readonly property bool showIcons: classes.length > 0
                readonly property real iconRunExtent: classes.length * strip.wsIconPx
                    + Math.max(0, classes.length - 1) * strip.wsIconGap
                readonly property real along: showIcons
                    ? (iconRunExtent + 2 * strip.wsIconPadAlong)
                    : (active ? strip.activeLen : strip.dotSize)
                width: strip.vertical ? strip.dotCross : along
                height: strip.vertical ? along : strip.dotCross
                radius: Math.min(width, height) / 2
                color: active ? Theme.verm
                    : (occupied ? Qt.alpha(Theme.cream, 0.55) : Qt.alpha(Theme.cream, 0.18))
                Behavior on width { NumberAnimation { duration: Motion.effects; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: Motion.effects; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Motion.effects } }

                Text {
                    anchors.centerIn: parent
                    visible: nPill.active && !nPill.showIcons
                    text: nPill.wsId - strip.base
                    color: Theme.cardBot
                    font.family: Theme.font
                    font.pixelSize: 8.5 * strip.s
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                }
                Row {
                    visible: !strip.vertical && nPill.showIcons
                    anchors.centerIn: parent
                    spacing: strip.wsIconGap
                    opacity: nPill.active ? 1.0 : 0.55
                    Repeater { model: nPill.classes; delegate: wsIconD }
                }
                Column {
                    visible: strip.vertical && nPill.showIcons
                    anchors.centerIn: parent
                    spacing: strip.wsIconGap
                    opacity: nPill.active ? 1.0 : 0.55
                    Repeater { model: nPill.classes; delegate: wsIconD }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: strip.jump(nPill.wsId)
                }
            }
        }
    }

    // ---- nacre dialect: hollow rings, the active one an accent donut --------
    Grid {
        visible: strip.nacre
        anchors.centerIn: parent
        columns: strip.vertical ? 1 : strip.count
        columnSpacing: strip.ringGap
        rowSpacing: strip.ringGap
        verticalItemAlignment: Grid.AlignVCenter
        horizontalItemAlignment: Grid.AlignHCenter

        Repeater {
            model: strip.wsList
            delegate: Item {
                id: nRing
                required property int modelData
                readonly property bool active: nRing.modelData === strip.activeWsId
                readonly property bool occupied: strip.occupiedSet[nRing.modelData] === true
                readonly property var classes: strip.wsIconsOn ? (strip.classesByWs[nRing.modelData] || []) : []
                readonly property bool showIcons: classes.length > 0
                readonly property real iconRunExtent: classes.length * strip.wsIconPx
                    + Math.max(0, classes.length - 1) * strip.wsIconGap
                readonly property real along: showIcons
                    ? (iconRunExtent + 2 * strip.wsIconPadAlong)
                    : strip.ringActive
                width: strip.vertical ? strip.ringCross : along
                height: strip.vertical ? along : strip.ringCross

                Rectangle {
                    visible: !nRing.showIcons
                    anchors.centerIn: parent
                    width: nRing.active ? strip.ringActive : strip.ringSize
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Math.max(1.5, 2 * strip.s)
                    border.color: nRing.active ? Theme.verm
                        : (nRing.occupied ? Qt.alpha(Theme.cream, 0.55) : Qt.alpha(Theme.cream, 0.20))
                    Behavior on width { NumberAnimation { duration: Motion.effects; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: Motion.effects } }
                }
                // occupied + icons on: the hollow ring gives way to a faint
                // filled chip, since a ring's own outline leaves no room to
                // carry icons.
                Rectangle {
                    visible: nRing.showIcons
                    anchors.fill: parent
                    radius: Math.min(width, height) / 2
                    color: nRing.active ? Qt.alpha(Theme.verm, 0.20) : Qt.alpha(Theme.cream, 0.10)
                }
                Row {
                    visible: !strip.vertical && nRing.showIcons
                    anchors.centerIn: parent
                    spacing: strip.wsIconGap
                    opacity: nRing.active ? 1.0 : 0.55
                    Repeater { model: nRing.classes; delegate: wsIconD }
                }
                Column {
                    visible: strip.vertical && nRing.showIcons
                    anchors.centerIn: parent
                    spacing: strip.wsIconGap
                    opacity: nRing.active ? 1.0 : 0.55
                    Repeater { model: nRing.classes; delegate: wsIconD }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: strip.jump(nRing.modelData)
                }
            }
        }
    }
}
