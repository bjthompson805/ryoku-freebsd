import QtQuick
import Quickshell.Widgets
import "Singletons"

// the focused-window title. on a focus change the outgoing title cross-fades
// out (a ghost layer) while the new one fades in, and the width eases to the
// new length instead of snapping, so the left island and its frame lobe resize
// smoothly. the live layer is bound straight to the source, so the title always
// shows; an empty title (no window, or the toggle off) collapses to nothing.
// iconSource, when set, paints the focused window's app icon ahead of the
// title text; it's bound straight to the source like the live text layer, no
// cross-fade of its own. clicking it (while a window is focused) opens the
// window-info popout, off the same requestPopout(name, center) convention as
// BarStats/BarNetSpeed.
Item {
    id: root

    property real s: 1
    property string label: ""
    property string iconSource: ""
    property real maxWidth: 240
    readonly property real lead: 6 * s
    readonly property bool hasIcon: iconSource.length > 0
    readonly property real iconSize: 12 * s
    readonly property real iconGap: 5 * s
    readonly property real textLead: lead + (hasIcon ? iconSize + iconGap : 0)

    signal requestPopout(string name, real center)

    function open() {
        const p = root.mapToItem(null, root.width / 2, root.height / 2);
        root.requestPopout("windowinfo", p.x);
    }

    property bool ready: false
    property string prevLabel: ""
    Component.onCompleted: { prevLabel = label; ready = true; }

    clip: true
    width: label.length > 0 ? Math.min(metrics.implicitWidth, maxWidth - textLead) + textLead : 0
    implicitWidth: width
    height: metrics.implicitHeight
    implicitHeight: height
    // both the width ease and the crossfade are pure animation cost on every
    // focus change -- skip them in Game Mode so a transition never contends
    // with a game's frame time for main-thread/render-thread work.
    Behavior on width {
        enabled: root.ready && !Flags.gameMode
        NumberAnimation { duration: Motion.spatial; easing.type: Easing.OutCubic }
    }

    onLabelChanged: {
        if (!ready)
            return;
        if (Flags.gameMode) {
            fade.stop();
            prevLabel = label;
            ghost.opacity = 0;
            live.opacity = 1;
            return;
        }
        ghost.text = prevLabel;
        prevLabel = label;
        ghost.opacity = 1;
        live.opacity = 0;
        fade.restart();
    }
    ParallelAnimation {
        id: fade
        NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: Motion.effects; easing.type: Easing.OutCubic }
        NumberAnimation { target: live; property: "opacity"; to: 1; duration: Motion.effects; easing.type: Easing.OutCubic }
    }

    Text {
        id: metrics
        visible: false
        text: root.label
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
        font.weight: Font.Medium
    }

    // the focused window's app icon, ahead of the title text.
    IconImage {
        id: icon
        visible: root.hasIcon
        x: root.lead
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: root.iconSize
        source: root.iconSource
    }

    // the old title, held and faded out on a change.
    //
    // width is pinned to the maxWidth cap, not root.width -- root's own
    // clip: true already does the reveal/hide as its width eases, the same
    // curtain idiom popouts/Popout.qml uses ("content at full size, revealed
    // by a widening clip ... content never reflows"). binding this to the
    // animating root.width instead would re-run Text's elide layout on
    // every one of the ~30 frames of that 500ms ease, for both labels, on
    // every single focus change -- real main-thread cost for a result the
    // clip already produces for free.
    Text {
        id: ghost
        x: root.textLead
        anchors.verticalCenter: parent.verticalCenter
        width: root.maxWidth - root.textLead
        elide: Text.ElideRight
        color: Theme.dim
        font: metrics.font
        opacity: 0
    }
    // the current title.
    Text {
        id: live
        x: root.textLead
        anchors.verticalCenter: parent.verticalCenter
        width: root.maxWidth - root.textLead
        elide: Text.ElideRight
        text: root.label
        color: Theme.dim
        font: metrics.font
        opacity: 1
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.label.length > 0
        cursorShape: Qt.PointingHandCursor
        onClicked: root.open()
    }
}
