import QtQuick
import "Singletons"

// generic "flash and scroll to me" behavior: drop as a plain child of any
// Item -- a whole SettingSection, or a single row like ToggleRow/SliderRow
// -- with a highlightId. When HubHighlight.trigger(id) matches, `target`
// (the parent by default) gets a soft ember outline and the page scrolls it
// into view. Factored out of SettingSection.qml so a group and a single row
// share one mechanic instead of duplicating it per row type.
//
// width/height: 1 (not 0) -- Qt Quick culls rendering of a zero-area item's
// whole subtree, even though flashBg's own geometry extends well past it.
// The 1px is otherwise irrelevant: plain Items (rows) ignore a sibling's
// size entirely, and a Column (SettingSection) only stacks by it, so 1px of
// slack is imperceptible.
Item {
    id: hl

    property string highlightId: ""
    property Item target: parent

    width: 1
    height: 1

    Connections {
        target: HubHighlight
        function onRequested(id) {
            if (id.length > 0 && id === hl.highlightId)
                hl.runHighlight();
        }
    }

    function runHighlight() {
        hl.scrollIntoView();
        hl.escapeClip();
        flashAnim.restart();
    }

    // the nearest Flickable-like ancestor of target (duck-typed on
    // contentY/contentHeight, since pages differ in how deep content sits
    // inside one), or null.
    function nearestFlickable() {
        var f = hl.target.parent;
        while (f && (f.contentY === undefined || f.contentHeight === undefined))
            f = f.parent;
        return f;
    }

    // nudge the Flickable so target is on-screen.
    function scrollIntoView() {
        var flick = hl.nearestFlickable();
        if (!flick)
            return;
        var top = hl.target.mapToItem(flick.contentItem || flick, 0, 0).y;
        var margin = 24;
        if (top - margin < flick.contentY)
            flick.contentY = Math.max(0, top - margin);
        else if (top + hl.target.height + margin > flick.contentY + flick.height)
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), top + hl.target.height + margin - flick.height);
    }

    // flashBg needs to overflow target's own edges for its padding, but
    // target's width often fills its Flickable exactly (rows/sections
    // stretch edge to edge), so that overflow is otherwise clipped clean
    // away by the Flickable's own clip:true -- no margin value would ever
    // show. Move flashBg out to sit beside (a sibling of) that Flickable
    // instead, where it isn't clipped; only ever needs doing once.
    property bool flashEscaped: false
    function escapeClip() {
        if (hl.flashEscaped)
            return;
        var flick = hl.nearestFlickable();
        if (!flick || !flick.parent)
            return;
        flashBg.parent = flick.parent;
        flashBg.z = -1;
        hl.flashEscaped = true;
    }

    // positioned via mapToItem (not anchors -- flashBg.parent isn't always
    // target's own parent/sibling, so anchoring to target would be invalid)
    // against whatever flashBg.parent currently is; escapeClip() may
    // reparent it away from `hl` after the first flash.
    Rectangle {
        id: flashBg
        readonly property int hMargin: 24
        readonly property int vMargin: 10
        x: hl.target.mapToItem(flashBg.parent, -hMargin, -vMargin).x
        y: hl.target.mapToItem(flashBg.parent, -hMargin, -vMargin).y
        width: hl.target.width + hMargin * 2
        height: hl.target.height + vMargin * 2
        radius: 12
        color: "transparent"
        border.width: 2
        border.color: Theme.ember
        opacity: 0
    }

    SequentialAnimation {
        id: flashAnim
        NumberAnimation { target: flashBg; property: "opacity"; to: 0.9; duration: Theme.quick }
        PauseAnimation { duration: 550 }
        NumberAnimation { target: flashBg; property: "opacity"; to: 0; duration: 600 }
    }
}
