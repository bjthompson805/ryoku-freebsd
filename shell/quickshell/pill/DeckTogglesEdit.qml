pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

// inline edit-mode for the quick-toggles row, entered via DeckToggles'
// pencil icon: an Active grid (every enabled toggle, draggable to reorder,
// tap x to unpin) over a Hidden pool (every disabled toggle, tap + to pin --
// appends to the end, same convention as ShellSettingsPage's
// toggleSidebarPane, drag afterward to reposition). Windows/Android
// quick-settings edit-mode shape.
//
// reorder mechanics start from MonitorTile.qml's DragHandler idiom (target:
// null, accumulate translation deltas) -- this codebase has no
// DelegateModel-based list reorder anywhere, and a 7-tile grid doesn't need
// that machinery. but a plain JS array bound as a Repeater's `model` is
// destroyed and fully recreated on every reassignment, which would kill the
// drag gesture mid-flight if `editOrder` were spliced on every frame. so
// `editOrder` stays frozen for the whole gesture; the live "make room"
// reflow is a derived `effectiveIndex()` shift (the standard reorderable-
// list technique: everything between the drag's start and current slot
// shifts by one), and the array is only actually spliced once, on release.
Item {
    id: root

    property real s: 1
    property var catalog: []
    property var order: []
    property var glyphFor: null
    signal reordered(var keys)
    signal membershipChanged(string key, bool on)
    signal done()

    property var editOrder: order.slice()
    onOrderChanged: root.editOrder = root.order.slice()

    readonly property var byKey: {
        var m = ({});
        for (var i = 0; i < root.catalog.length; i++)
            m[root.catalog[i].key] = root.catalog[i];
        return m;
    }
    readonly property var hiddenKeys: root.catalog.map(c => c.key).filter(k => root.editOrder.indexOf(k) < 0)

    readonly property int perRow: 5
    readonly property real spacing: 8 * root.s
    readonly property real tileW: (width - root.spacing * (root.perRow - 1)) / root.perRow
    readonly property real tileH: 54 * root.s
    readonly property real slotW: root.tileW + root.spacing
    readonly property real slotH: root.tileH + root.spacing

    implicitHeight: header.height + 8 * root.s + activeGrid.height
        + (root.hiddenKeys.length > 0 ? 16 * root.s + hiddenLabel.height + 8 * root.s + hiddenFlow.height : 0)

    Item {
        id: header
        width: parent.width
        height: 16 * root.s

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Edit Toggles"
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 1.4 * root.s
            font.capitalization: Font.AllUppercase
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Done"
            color: doneHov.hovered ? Theme.bright : Theme.brand
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            TapHandler { onTapped: root.done() }
            HoverHandler { id: doneHov; cursorShape: Qt.PointingHandCursor }
        }
    }

    Item {
        id: activeGrid
        anchors.top: header.bottom
        anchors.topMargin: 8 * root.s
        width: parent.width
        height: root.editOrder.length > 0
            ? Math.ceil(root.editOrder.length / root.perRow) * root.slotH - root.spacing
            : 0

        // live drag state: the dragged tile's original slot and its current
        // preview slot. -1 = no drag in progress. shared here (not per-tile)
        // since only one gesture can be active at a time.
        property int dragFrom: -1
        property int dragTo: -1

        // every OTHER tile's live displaced slot while a drag is in progress
        // -- shifts by one wherever it sits between the drag's start and its
        // current preview position, same as any drag-reorder list.
        function effectiveIndex(i) {
            if (activeGrid.dragFrom < 0 || i === activeGrid.dragFrom)
                return i;
            if (activeGrid.dragFrom < activeGrid.dragTo) {
                if (i > activeGrid.dragFrom && i <= activeGrid.dragTo) return i - 1;
            } else if (activeGrid.dragFrom > activeGrid.dragTo) {
                if (i >= activeGrid.dragTo && i < activeGrid.dragFrom) return i + 1;
            }
            return i;
        }

        Repeater {
            model: root.editOrder
            delegate: Item {
                id: tile
                required property string modelData
                required property int index
                readonly property var meta: root.byKey[tile.modelData]

                readonly property int slot: activeGrid.effectiveIndex(tile.index)
                readonly property real homeX: (tile.slot % root.perRow) * root.slotW
                readonly property real homeY: Math.floor(tile.slot / root.perRow) * root.slotH

                width: root.tileW
                height: root.tileH
                x: 0
                y: 0
                z: dh.active ? 1 : 0
                // a reorder-drop reassigns root.editOrder, which (being a
                // plain JS array, not a ListModel) makes the Repeater destroy
                // and recreate every delegate -- including ones that didn't
                // move. `ready` keeps that recreation from animating in from
                // (0,0): position instantly on creation, only animate once
                // settled, so a genuine later reflow (a different tile being
                // dragged) still glides.
                property bool ready: false
                Component.onCompleted: { tile.x = tile.homeX; tile.y = tile.homeY; tile.ready = true; }
                onHomeXChanged: if (!dh.active) tile.x = tile.homeX
                onHomeYChanged: if (!dh.active) tile.y = tile.homeY
                Behavior on x { enabled: !dh.active && tile.ready; NumberAnimation { duration: Motion.fast } }
                Behavior on y { enabled: !dh.active && tile.ready; NumberAnimation { duration: Motion.fast } }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: Theme.tileBg
                    border.width: 1
                    border.color: Theme.border

                    Column {
                        anchors.centerIn: parent
                        spacing: 4 * root.s
                        GlyphIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 16 * root.s
                            height: 16 * root.s
                            name: root.glyphFor(tile.modelData)
                            color: Theme.cream
                            stroke: 1.6
                        }
                        Text {
                            width: tile.width - 8 * root.s
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: tile.meta ? tile.meta.label : ""
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 8.5 * root.s
                        }
                    }

                    Item {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 3 * root.s
                        width: 14 * root.s
                        height: 14 * root.s
                        GlyphIcon {
                            anchors.fill: parent
                            name: "close"
                            color: closeHov.hovered ? Theme.brand : Theme.faint
                            stroke: 1.8
                        }
                        HoverHandler { id: closeHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.membershipChanged(tile.modelData, false) }
                    }
                }

                DragHandler {
                    id: dh
                    target: null
                    property real lastX: 0
                    property real lastY: 0
                    onActiveChanged: {
                        if (active) {
                            lastX = 0;
                            lastY = 0;
                            activeGrid.dragFrom = tile.index;
                            activeGrid.dragTo = tile.index;
                        } else {
                            var from = activeGrid.dragFrom;
                            var to = activeGrid.dragTo;
                            // clear the shift state BEFORE splicing editOrder:
                            // that reassignment recreates every delegate, and
                            // if dragFrom/dragTo were still set at that point,
                            // the fresh delegates -- already sitting at their
                            // correct final index -- would have the shift
                            // math applied on top, landing wrong for one
                            // frame and then animating a "correction" nobody
                            // asked for. neutralize effectiveIndex() first, so
                            // recreated tiles land right the first time.
                            activeGrid.dragFrom = -1;
                            activeGrid.dragTo = -1;
                            if (from >= 0 && from !== to) {
                                var l = root.editOrder.slice();
                                var moved = l.splice(from, 1)[0];
                                l.splice(to, 0, moved);
                                root.editOrder = l;
                                root.reordered(l);
                            } else {
                                tile.x = tile.homeX;
                                tile.y = tile.homeY;
                            }
                        }
                    }
                    onTranslationChanged: {
                        if (!active) return;
                        var dx = translation.x - lastX;
                        var dy = translation.y - lastY;
                        lastX = translation.x;
                        lastY = translation.y;
                        tile.x += dx;
                        tile.y += dy;

                        var col = Math.max(0, Math.min(root.perRow - 1, Math.round(tile.x / root.slotW)));
                        var row = Math.max(0, Math.round(tile.y / root.slotH));
                        activeGrid.dragTo = Math.max(0, Math.min(root.editOrder.length - 1, row * root.perRow + col));
                    }
                }
            }
        }
    }

    Text {
        id: hiddenLabel
        anchors.top: activeGrid.bottom
        anchors.topMargin: root.hiddenKeys.length > 0 ? 16 * root.s : 0
        visible: root.hiddenKeys.length > 0
        text: "Hidden"
        color: Theme.faint
        font.family: Theme.mono
        font.pixelSize: 9 * root.s
        font.weight: Font.DemiBold
        font.letterSpacing: 1.4 * root.s
        font.capitalization: Font.AllUppercase
    }

    Flow {
        id: hiddenFlow
        anchors.top: hiddenLabel.bottom
        anchors.topMargin: root.hiddenKeys.length > 0 ? 8 * root.s : 0
        width: parent.width
        spacing: root.spacing
        visible: root.hiddenKeys.length > 0

        Repeater {
            model: root.hiddenKeys
            delegate: Rectangle {
                id: hidden
                required property string modelData
                readonly property var meta: root.byKey[hidden.modelData]

                width: root.tileW
                height: root.tileH * 0.78
                radius: Theme.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.border
                opacity: 0.55

                Column {
                    anchors.centerIn: parent
                    spacing: 3 * root.s
                    GlyphIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 14 * root.s
                        height: 14 * root.s
                        name: root.glyphFor(hidden.modelData)
                        color: Theme.iconDim
                        stroke: 1.6
                    }
                    Text {
                        width: hidden.width - 6 * root.s
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: hidden.meta ? hidden.meta.label : ""
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 8 * root.s
                    }
                }

                Item {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 3 * root.s
                    width: 14 * root.s
                    height: 14 * root.s
                    GlyphIcon {
                        anchors.fill: parent
                        name: "add"
                        color: addHov.hovered ? Theme.bright : Theme.brand
                        stroke: 1.8
                    }
                    HoverHandler { id: addHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.membershipChanged(hidden.modelData, true) }
                }
            }
        }
    }
}
