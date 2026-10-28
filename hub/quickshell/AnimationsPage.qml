pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "Singletons"

// Animations: the live Hyprland animation tree (read via hyprctl) plus a visual
// bezier-curve editor. Curves and per-leaf overrides preview at once through the
// ryoku-hub hypr backend (hyprctl eval) and persist to settings.lua on Save; the
// global on/off lives in Appearance. Leaving with unsaved edits restores via the
// hub, since the preview is live.
Item {
    id: page

    HyprStore { id: store }
    readonly property bool previewDirty: store.dirty

    property var liveAnims: []
    property var liveCurves: []
    property string selectedCurve: ""

    Process {
        id: animProc
        command: ["hyprctl", "animations", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    page.liveAnims = (d[0] || []).filter((a) => a.overridden && a.name.indexOf("__") !== 0);
                    page.liveCurves = d[1] || [];
                    if (page.selectedCurve === "" && page.liveCurves.length > 0)
                        page.selectedCurve = page.liveCurves[0].name;
                } catch (e) {
                    console.log("hub: animations parse failed: " + e);
                }
            }
        }
    }

    // --- curves -------------------------------------------------------------
    function curveNames() {
        var seen = ({}), out = [];
        for (var i = 0; i < page.liveCurves.length; i++) {
            var n = page.liveCurves[i].name;
            if (!seen[n]) { seen[n] = true; out.push(n); }
        }
        for (var j = 0; j < store.animCurves.length; j++) {
            var m = store.animCurves[j].name;
            if (!seen[m]) { seen[m] = true; out.push(m); }
        }
        return out;
    }
    function curveOf(name) {
        for (var i = 0; i < store.animCurves.length; i++)
            if (store.animCurves[i].name === name)
                return store.animCurves[i];
        for (var j = 0; j < page.liveCurves.length; j++)
            if (page.liveCurves[j].name === name)
                return { "name": name, "x0": page.liveCurves[j].X0, "y0": page.liveCurves[j].Y0, "x1": page.liveCurves[j].X1, "y1": page.liveCurves[j].Y1 };
        return { "name": name, "x0": 0.25, "y0": 0.1, "x1": 0.25, "y1": 1 };
    }
    readonly property bool selectedIsCustom: {
        for (var i = 0; i < page.liveCurves.length; i++)
            if (page.liveCurves[i].name === page.selectedCurve)
                return false;
        return page.selectedCurve !== "";
    }
    readonly property bool selectedHasOverride: {
        void store.rev;
        for (var i = 0; i < store.animCurves.length; i++)
            if (store.animCurves[i].name === page.selectedCurve)
                return true;
        return false;
    }
    function upsertCurve(name, x0, y0, x1, y1) {
        if (name === "")
            return;
        var arr = store.animCurves.slice(), found = false;
        for (var i = 0; i < arr.length; i++)
            if (arr[i].name === name) {
                arr[i] = { "name": name, "x0": x0, "y0": y0, "x1": x1, "y1": y1 };
                found = true;
                break;
            }
        if (!found)
            arr.push({ "name": name, "x0": x0, "y0": y0, "x1": x1, "y1": y1 });
        store.editAnim("animCurves", arr);
    }
    function resetCurve(name) {
        var arr = [];
        for (var i = 0; i < store.animCurves.length; i++)
            if (store.animCurves[i].name !== name)
                arr.push(store.animCurves[i]);
        store.editAnim("animCurves", arr);
        if (page.selectedIsCustom && page.liveCurves.length > 0)
            page.selectedCurve = page.liveCurves[0].name;
    }
    function addCurve() {
        var n = 1, name = "custom", names = page.curveNames();
        while (names.indexOf(name) >= 0) { name = "custom" + n; n++; }
        page.upsertCurve(name, 0.25, 0.1, 0.25, 1);
        page.selectedCurve = name;
    }

    // --- per-leaf animations ------------------------------------------------
    function itemOf(leaf) {
        for (var i = 0; i < store.animItems.length; i++)
            if (store.animItems[i].leaf === leaf)
                return store.animItems[i];
        for (var j = 0; j < page.liveAnims.length; j++)
            if (page.liveAnims[j].name === leaf)
                return { "leaf": leaf, "enabled": page.liveAnims[j].enabled, "speed": page.liveAnims[j].speed, "bezier": page.liveAnims[j].bezier, "style": page.liveAnims[j].style };
        return { "leaf": leaf, "enabled": true, "speed": 1, "bezier": "", "style": "" };
    }
    function upsertItem(leaf, key, val) {
        var cur = page.itemOf(leaf);
        var next = { "leaf": leaf, "enabled": cur.enabled, "speed": cur.speed, "bezier": cur.bezier, "style": cur.style };
        next[key] = val;
        var arr = store.animItems.slice(), found = false;
        for (var i = 0; i < arr.length; i++)
            if (arr[i].leaf === leaf) { arr[i] = next; found = true; break; }
        if (!found)
            arr.push(next);
        store.editAnim("animItems", arr);
    }

    // --- layout -------------------------------------------------------------
    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bar.top
        anchors.bottomMargin: 16
        contentWidth: width
        contentHeight: col.implicitHeight
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
                Behavior on opacity { NumberAnimation { duration: Theme.quick } }
            }
        }

        Column {
            id: col
            width: flick.width - 12
            spacing: 26
            topPadding: 2
            bottomPadding: 8

            SettingSection {
                width: parent.width
                title: "GLOBAL"
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Animations"
                    highlightId: "global"
                    checked: store.animations
                    onToggled: (v) => store.edit("animations", v)
                }
            }

            SettingSection {
                width: parent.width
                title: "FOCUS FLASH"
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Animate the focused window"
                    highlightId: "focus_flash_enable"
                    checked: store.plugins.hyprfocus.enabled
                    onToggled: (v) => store.editPlugin("hyprfocus", "enabled", v)
                }
                ChoiceRow {
                    width: Math.min(parent.width, 460); label: "Style"
                    highlightId: "focus_flash_style"
                    options: [{ "key": "flash", "label": "Flash" }, { "key": "bounce", "label": "Bounce" }, { "key": "slide", "label": "Slide" }]
                    current: store.plugins.hyprfocus.mode
                    visible: store.plugins.hyprfocus.enabled
                    onChosen: (k) => store.editPlugin("hyprfocus", "mode", k)
                }
                SliderRow {
                    width: Math.min(parent.width, 460); label: "Flash opacity"; percent: true
                    highlightId: "focus_flash_opacity"
                    from: 0; to: 1; step: 0.05
                    value: store.plugins.hyprfocus.opacity
                    visible: store.plugins.hyprfocus.enabled && store.plugins.hyprfocus.mode === "flash"
                    onModified: (v) => store.editPlugin("hyprfocus", "opacity", v)
                }
                SliderRow {
                    width: Math.min(parent.width, 460); label: "Bounce strength"; percent: true
                    highlightId: "focus_flash_bounce"
                    from: 0.5; to: 1; step: 0.01
                    value: store.plugins.hyprfocus.bounce
                    visible: store.plugins.hyprfocus.enabled && store.plugins.hyprfocus.mode === "bounce"
                    onModified: (v) => store.editPlugin("hyprfocus", "bounce", v)
                }
                SliderRow {
                    width: Math.min(parent.width, 460); label: "Slide height"
                    highlightId: "focus_flash_slide"
                    from: 0; to: 150; step: 5; decimals: 0
                    value: store.plugins.hyprfocus.slide
                    visible: store.plugins.hyprfocus.enabled && store.plugins.hyprfocus.mode === "slide"
                    onModified: (v) => store.editPlugin("hyprfocus", "slide", v)
                }
                Text {
                    width: Math.min(parent.width, 620)
                    wrapMode: Text.WordWrap
                    text: "Briefly flashes, bounces, or slides a window when it gains focus. Applies on Save."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                    visible: store.plugins.hyprfocus.enabled
                }
            }

            SettingSection {
                width: parent.width
                title: "CURVES"
                highlightId: "curves"

                Row {
                    width: parent.width
                    spacing: 10
                    Dropdown {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - newBtn.width - resetBtn.width - 20
                        fieldWidth: 200
                        label: "Curve"
                        options: page.curveNames()
                        current: page.selectedCurve
                        onChosen: (k) => page.selectedCurve = k
                    }
                    HubButton {
                        id: newBtn
                        anchors.verticalCenter: parent.verticalCenter
                        label: "New"
                        icon: "plus"
                        onClicked: page.addCurve()
                    }
                    HubButton {
                        id: resetBtn
                        anchors.verticalCenter: parent.verticalCenter
                        label: page.selectedIsCustom ? "Delete" : "Reset"
                        icon: page.selectedIsCustom ? "trash" : "refresh"
                        enabled: page.selectedIsCustom || page.selectedHasOverride
                        onClicked: page.resetCurve(page.selectedCurve)
                    }
                }

                Row {
                    width: parent.width
                    spacing: 24

                    BezierEditor {
                        id: bez
                        width: 300
                        height: 280
                        x0: page.curveOf(page.selectedCurve).x0
                        y0: page.curveOf(page.selectedCurve).y0
                        x1: page.curveOf(page.selectedCurve).x1
                        y1: page.curveOf(page.selectedCurve).y1
                        onChanged: (x0, y0, x1, y1) => page.upsertCurve(page.selectedCurve, x0, y0, x1, y1)
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            text: "Drag the two handles."
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                        Text {
                            text: "P1   " + bez.x0.toFixed(2) + ", " + bez.y0.toFixed(2)
                            color: Theme.cream
                            font.family: Theme.mono
                            font.pixelSize: 13
                        }
                        Text {
                            text: "P2   " + bez.x1.toFixed(2) + ", " + bez.y1.toFixed(2)
                            color: Theme.cream
                            font.family: Theme.mono
                            font.pixelSize: 13
                        }
                        Text {
                            width: 200
                            wrapMode: Text.WordWrap
                            text: "Curves are shared by name. Animations below reference them."
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }
                }
            }

            SettingSection {
                width: parent.width
                title: "ANIMATIONS"
                highlightId: "per_window_animations"

                Text {
                    visible: page.liveAnims.length === 0
                    text: "No tunable animations reported."
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 13
                }

                Repeater {
                    model: page.liveAnims
                    delegate: AnimRow {
                        required property var modelData
                        width: parent.width
                        leaf: modelData.name
                        on: page.itemOf(modelData.name).enabled
                        speed: page.itemOf(modelData.name).speed
                        bezier: page.itemOf(modelData.name).bezier
                        style: page.itemOf(modelData.name).style
                        curveNames: page.curveNames()
                        onToggled: (v) => page.upsertItem(modelData.name, "enabled", v)
                        onSpeedEdited: (v) => page.upsertItem(modelData.name, "speed", v)
                        onBezierPicked: (b) => page.upsertItem(modelData.name, "bezier", b)
                        onStylePicked: (s) => page.upsertItem(modelData.name, "style", s)
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
            color: store.dirty ? Theme.ember : Theme.ok
        }
        Text {
            anchors.left: dot.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: store.dirty ? "Previewing unsaved changes" : "Saved \u00b7 live on your desktop"
            color: store.dirty ? Theme.bright : Theme.dim
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
                label: "Reset to defaults"
                icon: "refresh"
                onClicked: { store.editAnim("animItems", []); store.editAnim("animCurves", []); }
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
                onClicked: store.save()
            }
        }
    }
}
