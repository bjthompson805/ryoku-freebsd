pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

// the quick-toggles row: collapsible + reorderable, Windows/Android quick-
// settings style. `catalog` is the full universe of known toggles (data
// only -- glyph/label); `Config.sidebarToggles` is the enabled subset AND
// its display order in one array (membership = enabled), same idiom
// SidebarSystem.qml uses for its pane tabs. `deck` (the owning DeckControls)
// holds every toggle's live state + action -- catalog entries can't carry
// live bindings, so glyphFor/onFor/actFor dispatch by key instead.
//
// collapsed shows the first `collapsedCount` enabled toggles, identical to
// the row's pre-existing fixed-5 look; a full-width chevron bar reveals the
// rest, wrapped onto additional rows. the pencil (edit-mode entry) sits in
// its own row below the chevron, and only appears once expanded -- so
// reordering is reached through the expanded view -- unless there's no
// overflow to expand in the first place, where it's always reachable (see
// `hasOverflow`/pencilRow below). expand/edit state is session-only -- it
// never touches Config and always resets when the deck closes.
Item {
    id: root

    property real s: 1
    property var deck: null
    property int collapsedCount: 5
    property bool expanded: false
    property bool editMode: false

    implicitHeight: box.implicitHeight

    readonly property var catalog: [
        { key: "wifi",      glyph: "wifi",      label: "Wi-Fi" },
        { key: "bluetooth", glyph: "bluetooth", label: "Bluetooth" },
        { key: "mic",       glyph: "mic",       label: "Mic" },
        { key: "dnd",       glyph: "dnd",       label: "Do Not Disturb" },
        { key: "night",     glyph: "moon",      label: "Night Light" },
        { key: "airplane",  glyph: "airplane",  label: "Airplane Mode" },
        { key: "tablet",    glyph: "tablet",    label: "Tablet Mode" },
        { key: "webcam",    glyph: "webcam",    label: "Webcam" },
        { key: "lidsleep",  glyph: "lidsleep",  label: "Lid Sleep" }
    ]
    readonly property var catalogByKey: {
        var m = ({});
        for (var i = 0; i < root.catalog.length; i++)
            m[root.catalog[i].key] = root.catalog[i];
        return m;
    }
    readonly property var enabled: (Config.sidebarToggles || []).map(k => root.catalogByKey[k]).filter(Boolean)
    readonly property bool hasOverflow: root.enabled.length > root.collapsedCount

    function glyphFor(key) {
        if (key === "mic")
            return root.deck.micMuted ? "mic-off" : "mic";
        var c = root.catalogByKey[key];
        return c ? c.glyph : "";
    }
    function onFor(key) {
        switch (key) {
            case "wifi": return root.deck.wifiOn;
            case "bluetooth": return root.deck.btOn;
            case "mic": return !root.deck.micMuted;
            case "dnd": return Flags.dndActive;
            case "night": return root.deck.nightOn;
            case "airplane": return root.deck.airplaneOn;
            case "tablet": return root.deck.tabletOn;
            case "webcam": return Webcam.on;
            case "lidsleep": return Flags.lidSleep;
        }
        return false;
    }
    function actFor(key) {
        switch (key) {
            case "wifi": root.deck.toggleWifi(); break;
            case "bluetooth": root.deck.toggleBt(); break;
            case "mic": root.deck.toggleMic(); break;
            case "dnd": Flags.dnd = !Flags.dndActive; break;
            case "night": root.deck.toggleNight(); break;
            case "airplane": root.deck.toggleAirplane(); break;
            case "tablet": root.deck.toggleTablet(); break;
            case "webcam": Webcam.toggle(); break;
            case "lidsleep": Flags.lidSleep = !Flags.lidSleep; break;
        }
    }

    // session-only: collapse/close edit-mode whenever the sidebar shuts.
    Connections {
        target: root.deck
        function onActiveChanged() {
            if (!root.deck.active) {
                root.expanded = false;
                root.editMode = false;
            }
        }
    }

    function commitOrder(keys) {
        Config.sidebarToggles = keys;
        Config.persist();
    }
    function setEnabled(key, on) {
        var l = (Config.sidebarToggles || []).slice();
        var i = l.indexOf(key);
        if (on && i < 0)
            l.push(key);
        else if (!on && i >= 0)
            l.splice(i, 1);
        root.commitOrder(l);
    }

    // a bordered box segments the whole toggles block (tiles + chevron +
    // pencil, in either view or edit mode) from DeckTools' capture-tool row
    // sitting right below it in SidebarSystem's column.
    Rectangle {
        id: box
        width: parent.width
        implicitHeight: boxCol.implicitHeight + box.pad * 2
        radius: Theme.radius
        color: Theme.tileBg
        border.width: 1
        border.color: Theme.border

        readonly property real pad: 10 * root.s

        Column {
            id: boxCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: box.pad
            spacing: 8 * root.s

            // collapsed row (+ wrapped overflow when expanded) -- identical
            // visual to the original fixed-5 row when enabled.length <= 5.
            Column {
                width: parent.width
                visible: !root.editMode
                spacing: 8 * root.s

                Row {
                    id: mainRow
                    width: parent.width
                    spacing: 8 * root.s
                    readonly property int shown: Math.min(root.enabled.length, root.collapsedCount)
                    readonly property real tileW: shown > 0 ? (width - spacing * (shown - 1)) / shown : 0

                    Repeater {
                        model: root.enabled.slice(0, root.collapsedCount)
                        delegate: ToggleTile {
                            id: tile
                            required property var modelData
                            s: root.s
                            width: mainRow.tileW
                            glyph: root.glyphFor(tile.modelData.key)
                            label: tile.modelData.label
                            on: root.onFor(tile.modelData.key)
                            onActed: root.actFor(tile.modelData.key)
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 8 * root.s
                    visible: root.expanded && root.hasOverflow

                    Repeater {
                        model: root.expanded ? root.enabled.slice(root.collapsedCount) : []
                        delegate: ToggleTile {
                            id: tile
                            required property var modelData
                            s: root.s
                            width: mainRow.tileW
                            glyph: root.glyphFor(tile.modelData.key)
                            label: tile.modelData.label
                            on: root.onFor(tile.modelData.key)
                            onActed: root.actFor(tile.modelData.key)
                        }
                    }
                }

                // chevron bar: spans the box's content width, a comfortable
                // touch target -- hovering brightens the whole bar, not just
                // the glyph. sits directly under the tiles.
                Rectangle {
                    id: chevronBar
                    width: parent.width
                    height: 20 * root.s
                    visible: root.hasOverflow
                    radius: Theme.radius
                    color: chevronHov.hovered ? Theme.frameBg : "transparent"
                    border.width: 1
                    border.color: chevronHov.hovered ? Theme.frameBorder : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 11 * root.s
                        height: 11 * root.s
                        name: "chevron-down"
                        color: chevronHov.hovered ? Theme.cream : Theme.iconDim
                        rotation: root.expanded ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: Motion.fast } }
                    }
                    TapHandler { onTapped: root.expanded = !root.expanded }
                    HoverHandler { id: chevronHov; cursorShape: Qt.PointingHandCursor }
                }

                // pencil row: below the chevron bar, still inside the box.
                // only appears once expanded -- reordering is reached
                // through the expanded view, not the collapsed one -- except
                // when there's no overflow to expand in the first place
                // (enabled.length <= collapsedCount), where gating it on
                // `expanded` would permanently strand the user out of
                // edit-mode with no chevron left to click.
                Item {
                    width: parent.width
                    height: 14 * root.s
                    visible: root.expanded || !root.hasOverflow

                    GlyphIcon {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13 * root.s
                        height: 13 * root.s
                        name: "pencil"
                        color: pencilHov.hovered ? Theme.cream : Theme.iconDim
                        TapHandler { onTapped: root.editMode = true }
                        HoverHandler { id: pencilHov; cursorShape: Qt.PointingHandCursor }
                    }
                }
            }

            DeckTogglesEdit {
                width: parent.width
                visible: root.editMode
                s: root.s
                catalog: root.catalog
                order: Config.sidebarToggles || []
                glyphFor: root.glyphFor
                onDone: root.editMode = false
                onReordered: (keys) => root.commitOrder(keys)
                onMembershipChanged: (key, on) => root.setEnabled(key, on)
            }
        }
    }
}
