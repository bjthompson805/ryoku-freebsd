pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

// flat quick-toggle tile: glyph only, lights vermilion when on, its name
// fading in at the bottom on hover. shared by DeckToggles' collapsed/
// expanded rows and its edit-mode grid.
Rectangle {
    id: tt

    property real s: 1
    property string glyph: ""
    property string label: ""
    property bool on: false
    signal acted()

    // a little taller than a bare icon tile needs, so the hover label has
    // clearance under the (still vertically centered) icon instead of
    // overlapping it.
    height: 44 * tt.s
    radius: Theme.radius
    color: tt.on ? Theme.brand : (tHov.hovered ? Theme.frameBg : "transparent")
    border.width: 1
    border.color: tt.on ? Theme.brand : (tHov.hovered ? Theme.frameBorder : Theme.border)
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    GlyphIcon {
        anchors.centerIn: parent
        width: 15 * tt.s
        height: 15 * tt.s
        name: tt.glyph
        color: tt.on ? Theme.onAccent : (tHov.hovered ? Theme.cream : Theme.iconDim)
        stroke: 1.6
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3 * tt.s
        width: tt.width - 6 * tt.s
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: tt.label
        color: tt.on ? Theme.onAccent : Theme.cream
        font.family: Theme.font
        font.pixelSize: 6.5 * tt.s
        font.weight: Font.DemiBold
        opacity: tHov.hovered ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    }

    HoverHandler { id: tHov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: tt.acted() }
}
