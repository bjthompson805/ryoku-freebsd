pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "Singletons"

// Custom keybinds editor: user shortcuts layered over the shipped binds. Each row
// is a key combo plus an action (run a command, or a window dispatcher). They are
// written to settings.lua and applied on Save. The shared store persists them.
Item {
    id: page

    HyprStore { id: store }

    property var categories: []

    // conflict detection catches what a hand-edited user.lua never would: a
    // custom combo that shadows a shipped bind, or duplicates another custom one.
    // keys are normalised for case, spacing, and modifier order before compare.
    function normKeys(s) {
        if (!s)
            return "";
        var parts = ("" + s).split("+");
        var out = [];
        for (var i = 0; i < parts.length; i++) {
            var t = parts[i].trim().toLowerCase();
            if (t.length)
                out.push(t);
        }
        out.sort();
        return out.join("+");
    }
    readonly property var shippedKeys: {
        var set = {};
        for (var c = 0; c < page.categories.length; c++) {
            var binds = page.categories[c].binds || [];
            for (var b = 0; b < binds.length; b++) {
                var k = page.normKeys((binds[b].keys || []).join(" + "));
                if (k.length)
                    set[k] = true;
            }
        }
        return set;
    }
    function customCount(norm) {
        var n = 0;
        for (var i = 0; i < store.keybinds.length; i++)
            if (page.normKeys(store.keybinds[i].keys) === norm)
                n++;
        return n;
    }
    // "" none, "shipped" shadows a Ryoku bind (saving unbinds the shipped one, so
    // this combo cleanly becomes yours), "duplicate" repeats another custom bind
    // (a real footgun: only the last-declared one ends up bound).
    function rowConflict(i) {
        var k = page.normKeys(store.keybinds[i].keys);
        if (!k)
            return "";
        if (page.customCount(k) > 1)
            return "duplicate";
        return page.shippedKeys[k] ? "shipped" : "";
    }
    // duplicates are worth a loud warning; a shipped override is expected and
    // safe, so it's counted separately and shown calmer.
    readonly property int conflictCount: {
        void store.rev;
        var n = 0;
        for (var i = 0; i < store.keybinds.length; i++)
            if (page.rowConflict(i) === "duplicate")
                n++;
        return n;
    }
    readonly property int overrideCount: {
        void store.rev;
        var n = 0;
        for (var i = 0; i < store.keybinds.length; i++)
            if (page.rowConflict(i) === "shipped")
                n++;
        return n;
    }

    readonly property var actionOpts: [
        { "key": "exec", "label": "Run command" },
        { "key": "close", "label": "Close window" },
        { "key": "fullscreen", "label": "Fullscreen" },
        { "key": "togglefloating", "label": "Toggle floating" }
    ]

    // a single field commit (blur/Enter on a TextInput, a Dropdown choice) edits
    // its row's object in place and just bumps rev, rather than reassigning
    // store.keybinds wholesale: the Repeater's model is that array directly, and
    // a plain-array model has no incremental change signal, so reassigning it
    // makes the Repeater tear down and recreate every row's delegates (and every
    // TextInput in them) on every keystroke-commit. That both loses whatever the
    // user was mid-typing elsewhere and, worse, can destroy the very field a
    // click was headed for out from under it (the field silently eats the first
    // click). add()/remove() do need to reassign -- the row count actually
    // changes -- so those keep the full-array path.
    function patch(i, key, val) {
        store.keybinds[i][key] = val;
        store.rev++;
    }
    function remove(i) {
        var a = store.keybinds.slice();
        a.splice(i, 1);
        store.editList("keybinds", a);
    }
    function add() {
        var a = store.keybinds.slice();
        a.push({ "keys": "", "action": "exec", "value": "" });
        store.editList("keybinds", a);
    }

    Text {
        id: intro
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        wrapMode: Text.WordWrap
        text: "Custom shortcuts layered over the ones Ryoku ships and kept in the Hub, so they show in the Shortcuts legend and get conflict-checked. Reusing a shipped combo overrides it cleanly, swapping in your action; reusing another custom combo doesn't, only the last one you saved actually binds. Add binds here, not by hand in ~/.config/hypr/user.lua: binds written there never appear in the legend and aren't checked for conflicts. Write the combo the way Hyprland does, e.g. SUPER + J or SUPER + SHIFT + Return."
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12
    }

    HubButton {
        id: addBtn
        anchors.left: parent.left
        anchors.top: intro.bottom
        anchors.topMargin: 14
        label: "Add shortcut"
        icon: "plus"
        // same reasoning as Save below: commit whatever's mid-edit before the
        // new row's full-array add() rebuilds every delegate, or the just-typed
        // text in an unfocused-but-uncommitted field gets discarded.
        onClicked: { page.forceActiveFocus(); page.add(); }
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: addBtn.bottom
        anchors.topMargin: 16
        anchors.bottom: bar.top
        anchors.bottomMargin: 16
        contentWidth: width
        contentHeight: rows.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            id: sb
            policy: ScrollBar.AsNeeded
            width: 7
            contentItem: Rectangle {
                implicitWidth: 4
                radius: Theme.radius
                color: Theme.line
                opacity: sb.pressed ? 0.9 : (sb.hovered ? 0.7 : 0.4)
            }
        }

        Column {
            id: rows
            width: flick.width - 12
            spacing: 10

            Text {
                visible: store.keybinds.length === 0
                text: "No custom shortcuts yet."
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 13
            }

            Repeater {
                model: store.keybinds

                delegate: Rectangle {
                    id: rowItem
                    required property int index
                    required property var modelData
                    // modelData's fields now mutate in place (see patch()), which
                    // doesn't itself trigger a re-evaluation of plain property reads
                    // off it, so these depend on rev explicitly instead.
                    readonly property bool needsValue: { void store.rev; return rowItem.modelData.action === "exec" || rowItem.modelData.action === undefined; }
                    readonly property string conflict: { void store.rev; return page.rowConflict(rowItem.index); }
                    readonly property color conflictColor: rowItem.conflict === "duplicate" ? Theme.gold
                        : (rowItem.conflict === "shipped" ? Theme.ember : Theme.line)
                    width: rows.width
                    height: 56
                    radius: Theme.radius
                    color: Theme.surfaceLo
                    border.width: 1
                    border.color: rowItem.conflictColor

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        spacing: 10

                        // key combo
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 200
                            height: 32
                            radius: Theme.radius
                            color: Theme.surface
                            border.width: 1
                            border.color: keysIn.activeFocus ? Theme.ember : rowItem.conflictColor
                            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                            TextInput {
                                id: keysIn
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                text: rowItem.modelData.keys
                                color: Theme.bright
                                font.family: Theme.mono
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                clip: true
                                selectByMouse: true
                                KeyNavigation.tab: valIn
                                onEditingFinished: page.patch(rowItem.index, "keys", text)

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: keysIn.text === "" && !keysIn.activeFocus
                                    text: "SUPER + J"
                                    color: Theme.faint
                                    font: keysIn.font
                                }
                            }
                        }

                        Dropdown {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 230
                            fieldWidth: 150
                            label: ""
                            options: page.actionOpts
                            current: { void store.rev; return rowItem.modelData.action || "exec"; }
                            onChosen: (k) => page.patch(rowItem.index, "action", k)
                        }

                        // command (exec only)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 200 - 230 - delBtn.width - 40
                            height: 32
                            radius: Theme.radius
                            visible: rowItem.needsValue
                            color: Theme.surface
                            border.width: 1
                            border.color: valIn.activeFocus ? Theme.ember : Theme.line
                            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                            TextInput {
                                id: valIn
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                text: rowItem.modelData.value
                                color: Theme.bright
                                font.family: Theme.mono
                                font.pixelSize: 13
                                clip: true
                                selectByMouse: true
                                KeyNavigation.backtab: keysIn
                                onEditingFinished: page.patch(rowItem.index, "value", text)

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: valIn.text === "" && !valIn.activeFocus
                                    text: "command to run"
                                    color: Theme.faint
                                    font: valIn.font
                                }
                            }
                        }
                    }

                    Item {
                        id: delBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        Icon {
                            anchors.centerIn: parent
                            name: "trash"
                            size: 15
                            tint: delHov.hovered ? Theme.bad : Theme.faint
                        }
                        HoverHandler { id: delHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: page.remove(rowItem.index) }
                    }
                }
            }
        }
    }

    // --- action bar ---------------------------------------------------------
    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        height: 60
        radius: Theme.radius
        color: store.dirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.08) : Theme.surfaceLo
        border.width: 1
        border.color: store.dirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.4) : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.medium } }
        Behavior on border.color { ColorAnimation { duration: Theme.medium } }

        Rectangle {
            id: dot
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 9; height: 9; radius: 4.5
            color: page.conflictCount > 0 ? Theme.gold : (page.overrideCount > 0 ? Theme.ember : (store.dirty ? Theme.ember : Theme.ok))
        }
        Text {
            anchors.left: dot.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: page.conflictCount > 0
                ? (page.conflictCount + (page.conflictCount === 1 ? " duplicate combo — only the last one binds" : " duplicate combos — only the last one binds"))
                : (page.overrideCount > 0
                    ? (page.overrideCount + (page.overrideCount === 1 ? " shortcut overrides a shipped default" : " shortcuts override shipped defaults") + (store.dirty ? " · unsaved" : ""))
                    : (store.dirty ? "Unsaved shortcuts" : "Saved"))
            color: page.conflictCount > 0 ? Theme.gold : (store.dirty || page.overrideCount > 0 ? Theme.bright : Theme.dim)
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Clear all"
                icon: "refresh"
                onClicked: store.editList("keybinds", [])
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Revert"
                icon: "close"
                enabled: store.dirty
                onClicked: store.revert()
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Save"
                icon: "check"
                primary: true
                enabled: store.dirty
                // Save is a TapHandler, not a focusable control, so it never steals
                // focus on its own: a row's key/command TextInput only commits its
                // typed text to the store on editingFinished (Enter or losing
                // focus), so clicking here mid-edit would save a stale value
                // unless something first knocks that field out of focus. Force it.
                onClicked: { page.forceActiveFocus(); store.save(); }
            }
        }
    }
}
