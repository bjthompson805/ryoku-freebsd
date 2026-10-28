pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import Quickshell.Widgets
import ".."
import "../Singletons"

// One session action in the power panel's action row. Safe actions (lock,
// sleep) fire on a tap. Destructive ones (logout, restart, shutdown) fire
// only on a press-and-hold: the tile fills bottom-up with the accent as it
// confirms, release early drains it. `s` is the content scale.
Item {
    id: root

    property real s: 1
    property string glyph: ""
    property string label: ""
    property bool confirm: false
    property var argv: []
    property string dispatch: ""

    signal ran()

    readonly property real tileW: 64 * root.s
    readonly property real tileH: 68 * root.s
    implicitWidth: tileW
    implicitHeight: tileH

    readonly property bool hovered: ma.containsMouse
    readonly property color accent: root.confirm ? Theme.vermLit : Theme.cream

    // heat.cancel() drains the fill straight back to empty the instant a hold
    // confirms (see HeatHold.qml -- shared with the clipboard wipe button,
    // which wants exactly that reset). a destructive session action instead
    // needs the tile to stay full through to the panel closing, or it reads
    // as the hold having been let go rather than fired. latched here so the
    // fill visuals don't depend on heat's own hold value once fired; cleared
    // on the next press so a failed dispatch (e.g. polkit deny) doesn't leave
    // the tile stuck full for a following attempt.
    property bool locked: false

    function fire() {
        root.locked = true;
        heat.cancel();
        if (root.dispatch && root.dispatch.length)
            Hyprland.dispatch(root.dispatch);
        else if (root.argv && root.argv.length)
            Spawn.spawn(root.argv);
        root.ran();
    }

    HeatHold {
        id: heat
        onConfirmed: root.fire()
    }

    Rectangle {
        id: tile
        anchors.fill: parent
        radius: Motion.rTile * root.s
        color: root.hovered ? Theme.frameBg : "transparent"
        border.width: 1
        border.color: (root.hovered || heat.holding || root.locked) ? Theme.frameBorder : Theme.border
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        clip: true

        // the confirm ramp in a ClippingRectangle that carries the tile's
        // corner radius. a plain Rectangle with its own radius gets it
        // clamped to height/2 while the fill is still flat -> corners poke
        // outside the tile outline on the first beat of a hold.
        ClippingRectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: (Motion.rTile - 1) * root.s
            color: "transparent"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * (root.locked ? 1 : heat.hold)
                visible: heat.holding || root.locked
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.verm, 0.7) }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.vermLit, 0.15) }
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 4 * root.s

        GlyphIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 22 * root.s; height: 22 * root.s
            name: root.glyph
            stroke: 1.9
            color: (heat.holding || root.locked) ? Theme.flameCore : (root.hovered ? root.accent : Theme.iconDim)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.family: Theme.mono
            font.pixelSize: 10 * root.s
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1
            color: (heat.holding || root.locked) ? Theme.flameCore : (root.hovered ? Theme.subtle : Theme.faint)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: if (root.confirm) { root.locked = false; heat.press(); }
        onReleased: if (root.confirm) heat.release()
        onCanceled: if (root.confirm) heat.cancel()
        onExited: if (root.confirm) heat.cancel()
        onClicked: if (!root.confirm) root.fire()
    }
}
