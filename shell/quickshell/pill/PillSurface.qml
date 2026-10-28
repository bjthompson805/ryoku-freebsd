import QtQuick
import "Singletons"

// shared morph-surface base for the pill's standard surfaces. fills the
// pill body inset by its margins (scaled by `s`). content lives at a
// FIXED open size inside a clip that tracks the live morphing body, so
// the island shape reveals/hides it like a curtain (mirrors the edge
// popouts). never resizes/squishes.
//
// host sets: open, s, openW, openH, shown, openProgress (and morphCloseness).
// surface sets its own margins. `active` mirrors `open` for onActiveChanged.
// requestClose() dismisses. Osd/Toast use a different lifecycle.
Item {
    id: surface

    property real s: 1
    property bool open: false
    property real morphCloseness: 1

    // set by the pill. `shown` = true while this surface owns the island:
    // open, and through the close morph until the pill settles at rest.
    // `openProgress` = how open the island actually is right now (0 at rest,
    // 1 fully open), from its live width, so content can't fade out of a
    // still-open island or linger in a closing one.
    property bool shown: false
    property real openProgress: 0

    // surface open size (from pill.surfaceSize), so the content holder is
    // fixed at full size while the body clips it during the morph.
    property real openW: 0
    property real openH: 0

    property real mTop: 0
    property real mLeft: 0
    property real mRight: 0
    property real mBottom: 0

    signal requestClose()

    // Ame anchor. each surface declares the flame's form + dock point
    // (surface-local coords) for its open state; host maps the point into
    // pill space and feeds the active surface's pair to Ame. left non-readonly
    // so a deriving surface can re-bind. base default = off at the centre.
    property string ameForm: "off"
    property point amePoint: Qt.point(width / 2, height / 2)

    readonly property bool active: open

    anchors.fill: parent
    anchors.topMargin: mTop * s
    anchors.leftMargin: mLeft * s
    anchors.rightMargin: mRight * s
    anchors.bottomMargin: mBottom * s

    enabled: open
    // gentle finishing fade on top of the clip reveal, tied to the same
    // live openProgress so it can't run on its own timeline.
    opacity: shown ? Math.min(1, openProgress / 0.25) : 0
    visible: opacity > 0.01

    // ride the blob. content lives at its FIXED open size inside a clip
    // that tracks the live (morphing) body, so the island shape reveals/
    // hides it like a curtain rather than the content resizing as the pill
    // morphs (mirrors the edge popouts). surface children land in
    // `contentInner` via the default alias, lay out once at full size and
    // never reflow during the morph.
    Item {
        id: bodyClip
        anchors.fill: parent
        clip: true

        Item {
            id: contentInner
            width: Math.max(0, surface.openW - (surface.mLeft + surface.mRight) * surface.s)
            height: Math.max(0, surface.openH - (surface.mTop + surface.mBottom) * surface.s)
            x: Math.round((bodyClip.width - width) / 2)
            y: 0
        }
    }

    default property alias data: contentInner.data
}
