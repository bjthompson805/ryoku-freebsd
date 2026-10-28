pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "Singletons"

// input: keyboard, pointer, touchpad, key-repeat. edited live through the
// ryoku-hub hypr backend (settings.lua applied via hyprctl eval). every
// control writes a scalar draft on the shared HyprStore and previews at
// once. Save persists + reloads. Revert / leaving restore the saved state.
// Reset returns just the input domain to shipped defaults.
Item {
    id: page

    HyprStore { id: store }

    // read by the hub to drop a live preview when this page is left.
    readonly property bool previewDirty: store.dirty

    // camera flip draft: WebcamPrefs isn't part of HyprStore (no Hyprland
    // meaning, its own JSON file), but this control lives on a Hub page and
    // must obey the same "preview only, persist on Save" contract as every
    // other control here -- not WebcamPrefs' own instant-apply default (that
    // default is right for a live shell toggle, e.g. the Mirror bubble's
    // flip, but wrong for a Hub settings row). So: a local draft, synced from
    // WebcamPrefs.flip180 on load, only ever written back to the singleton
    // (which persists it immediately itself) from Save below. Leaving the
    // page destroys this Item and its draft with it, so an unsaved edit is
    // discarded for free, same as HyprStore's edits are via previewDirty.
    property bool flipDraft: WebcamPrefs.flip180
    readonly property bool flipDirty: page.flipDraft !== WebcamPrefs.flip180
    readonly property bool anyDirty: store.dirty || page.flipDirty

    // xkb-rules layouts, mapped to Dropdown options.
    property var layoutOptions: []

    Process {
        id: layoutsProc
        command: ["ryoku-hub", "hypr", "layouts"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var arr = JSON.parse(this.text);
                    var out = [];
                    for (var i = 0; i < arr.length; i++)
                        out.push({ "key": arr[i].code, "label": arr[i].name, "hint": arr[i].code });
                    page.layoutOptions = out;
                } catch (e) {}
            }
        }
    }

    // ------ layout composition ----------------------------------------------
    // kb_layout may hold "fr,us" (primary + secondary with a switch chord);
    // the two dropdowns edit the halves and recompose the comma form. The
    // variant applies to the primary layout, so a secondary keeps its slot
    // empty ("azerty," aligns variants to layouts positionally in xkb).

    function primaryLayout() { return String(store.kbLayout || "").split(",")[0]; }
    function secondaryLayout() {
        var parts = String(store.kbLayout || "").split(",");
        return parts.length > 1 ? parts[1] : "";
    }
    function primaryVariant() { return String(store.kbVariant || "").split(",")[0]; }

    function setLayouts(primary, secondary) {
        store.edit("kbLayout", secondary ? primary + "," + secondary : primary);
        var v = page.primaryVariant();
        store.edit("kbVariant", secondary && v ? v + "," : v);
    }
    function setVariant(v) {
        store.edit("kbVariant", page.secondaryLayout() && v ? v + "," : v);
    }

    // xkb variants for the primary layout, refetched when it changes. xkb
    // names repeat the language ("French (AZERTY)", "Belgian (alt.)"); inside
    // an already-chosen layout that prefix is noise, so it is stripped and the
    // qualifier alone becomes the label ("AZERTY", "alt."), code as the hint.
    property var variantOptions: [{ "key": "", "label": "Default" }]

    function variantLabel(name) {
        var m = String(name || "").match(/^[^(]+\((.+)\)$/);
        if (!m)
            return name;
        var q = m[1].trim();
        return q.charAt(0).toUpperCase() + q.slice(1);
    }

    Process {
        id: variantsProc
        property string forLayout: ""
        command: ["ryoku-hub", "hypr", "variants", forLayout]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [{ "key": "", "label": "Default" }];
                try {
                    var arr = JSON.parse(this.text);
                    for (var i = 0; i < arr.length; i++)
                        out.push({ "key": arr[i].code, "label": page.variantLabel(arr[i].name), "hint": arr[i].code });
                } catch (e) {}
                page.variantOptions = out;
            }
        }
    }
    function refreshVariants() {
        var l = page.primaryLayout();
        if (l.length === 0 || variantsProc.forLayout === l)
            return;
        variantsProc.forLayout = l;
        variantsProc.running = false;
        variantsProc.running = true;
    }
    Connections {
        target: store
        function onKbLayoutChanged() { page.refreshVariants(); }
    }
    Component.onCompleted: refreshVariants()

    // ------ curated remaps over kb_options ----------------------------------
    // Each picker owns one xkb option family; anything it doesn't recognise
    // stays in the free-text field, so power users lose nothing. All state
    // lives in the single store.kbOptions string.

    readonly property var capsIds: ["caps:escape", "ctrl:nocaps", "caps:swapescape", "caps:none"]
    readonly property var composeIds: ["compose:ralt", "compose:menu"]
    readonly property var grpIds: ["grp:alt_shift_toggle", "grp:win_space_toggle", "grp:caps_toggle"]
    readonly property string swapId: "altwin:swap_alt_win"

    function optTokens() {
        var raw = String(store.kbOptions || "").split(",");
        var out = [];
        for (var i = 0; i < raw.length; i++) {
            var t = raw[i].trim();
            if (t.length)
                out.push(t);
        }
        return out;
    }
    function pickFrom(ids) {
        var toks = page.optTokens();
        for (var i = 0; i < toks.length; i++)
            if (ids.indexOf(toks[i]) !== -1)
                return toks[i];
        return "";
    }
    function knownIds() {
        return page.capsIds.concat(page.composeIds).concat(page.grpIds).concat([page.swapId]);
    }
    function extraOptions() {
        var known = page.knownIds();
        var toks = page.optTokens();
        var out = [];
        for (var i = 0; i < toks.length; i++)
            if (known.indexOf(toks[i]) === -1)
                out.push(toks[i]);
        return out.join(",");
    }
    // rebuild kb_options with one family replaced; "" drops the family.
    function setOption(ids, value) {
        var toks = page.optTokens();
        var out = [];
        for (var j = 0; j < toks.length; j++)
            if (ids.indexOf(toks[j]) === -1)
                out.push(toks[j]);
        if (value.length)
            out.push(value);
        store.edit("kbOptions", out.join(","));
    }
    function setExtra(text) {
        var known = page.knownIds();
        var keep = [];
        var toks = page.optTokens();
        for (var i = 0; i < toks.length; i++)
            if (known.indexOf(toks[i]) !== -1)
                keep.push(toks[i]);
        var raw = String(text || "").split(",");
        for (var j = 0; j < raw.length; j++) {
            var t = raw[j].trim();
            if (t.length)
                keep.push(t);
        }
        store.edit("kbOptions", keep.join(","));
    }

    // localectl converts the X11 keymap to the nearest console keymap too, so
    // one privileged call covers the SDDM greeter AND the TTY. polkit prompts.
    property string sysApplyState: ""
    Process {
        id: sysApplyProc
        command: ["localectl", "set-x11-keymap",
            String(store.kbLayout || "us"), "",
            String(store.kbVariant || ""), String(store.kbOptions || "")]
        onExited: (code, status) => {
            page.sysApplyState = code === 0 ? "ok" : "err";
            sysApplyClear.restart();
        }
    }
    Timer {
        id: sysApplyClear
        interval: 6000
        onTriggered: page.sysApplyState = ""
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bar.top
        anchors.bottomMargin: 18
        contentWidth: width
        contentHeight: Math.max(col.height, height)
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
            spacing: 30

            SettingSection {
                width: parent.width
                title: "KEYBOARD"
                Dropdown {
                    width: Math.min(parent.width, 460); label: "Layout"
                    fieldWidth: 240
                    highlightId: "keyboard_layout"
                    options: page.layoutOptions
                    current: page.primaryLayout()
                    placeholder: page.primaryLayout()
                    onChosen: (k) => page.setLayouts(k, page.secondaryLayout())
                }
                Dropdown {
                    width: Math.min(parent.width, 460); label: "Style"
                    fieldWidth: 240
                    highlightId: "keyboard_style"
                    options: page.variantOptions
                    current: page.primaryVariant()
                    placeholder: "Default"
                    onChosen: (k) => page.setVariant(k)
                }
                Dropdown {
                    width: Math.min(parent.width, 460); label: "Second layout"
                    fieldWidth: 240
                    highlightId: "keyboard_second_layout"
                    options: [{ "key": "", "label": "None" }].concat(page.layoutOptions)
                    current: page.secondaryLayout()
                    placeholder: "None"
                    onChosen: (k) => page.setLayouts(page.primaryLayout(), k)
                }
                ChoiceRow {
                    width: Math.min(parent.width, 460); label: "Switch layouts"
                    visible: page.secondaryLayout().length > 0
                    highlightId: "keyboard_switch"
                    options: [
                        { "key": "", "label": "Off" },
                        { "key": "grp:alt_shift_toggle", "label": "Alt+Shift" },
                        { "key": "grp:win_space_toggle", "label": "Super+Space" }
                    ]
                    current: page.pickFrom(page.grpIds)
                    onChosen: (k) => page.setOption(page.grpIds, k)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Numlock on at login"
                    highlightId: "keyboard_numlock"
                    checked: store.numlockByDefault
                    onToggled: (v) => store.edit("numlockByDefault", v)
                }
            }

            SettingSection {
                width: parent.width
                title: "KEY REMAPS"
                ChoiceRow {
                    width: Math.min(parent.width, 460); label: "Caps Lock"
                    highlightId: "key_remaps_capslock"
                    options: [
                        { "key": "", "label": "Default" },
                        { "key": "caps:escape", "label": "Escape" },
                        { "key": "ctrl:nocaps", "label": "Ctrl" },
                        { "key": "caps:swapescape", "label": "Swap Esc" },
                        { "key": "caps:none", "label": "Off" }
                    ]
                    current: page.pickFrom(page.capsIds)
                    onChosen: (k) => page.setOption(page.capsIds, k)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Swap Alt and Super"
                    highlightId: "key_remaps_swap"
                    checked: page.pickFrom([page.swapId]) === page.swapId
                    onToggled: (v) => page.setOption([page.swapId], v ? page.swapId : "")
                }
                ChoiceRow {
                    width: Math.min(parent.width, 460); label: "Compose key"
                    highlightId: "key_remaps_compose"
                    options: [
                        { "key": "", "label": "Off" },
                        { "key": "compose:ralt", "label": "Right Alt" },
                        { "key": "compose:menu", "label": "Menu" }
                    ]
                    current: page.pickFrom(page.composeIds)
                    onChosen: (k) => page.setOption(page.composeIds, k)
                }
                SettingField {
                    width: Math.min(parent.width, 460); label: "Extra options"
                    fieldWidth: 240
                    highlightId: "key_remaps_extra"
                    placeholder: "raw xkb options, comma-separated\u2026"
                    value: page.extraOptions()
                    onCommitted: (v) => page.setExtra(v)
                }
                Item {
                    width: Math.min(parent.width, 460)
                    height: 34

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - sysBtn.width - 14
                        text: page.sysApplyState === "ok" ? "Applied to login screen and console"
                            : page.sysApplyState === "err" ? "Not applied (cancelled or failed)"
                            : "Login screen and TTY keep their own keymap"
                        elide: Text.ElideRight
                        color: page.sysApplyState === "ok" ? Theme.ok
                            : page.sysApplyState === "err" ? Theme.ember : Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    HubButton {
                        id: sysBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Apply system-wide"
                        icon: "check"
                        enabled: !store.dirty && !sysApplyProc.running
                        onClicked: sysApplyProc.running = true
                    }
                }
            }

            SettingSection {
                width: parent.width
                title: "POINTER"
                SliderRow {
                    width: Math.min(parent.width, 460); label: "Sensitivity"
                    highlightId: "pointer_sensitivity"
                    from: -1; to: 1; step: 0.05; decimals: 2
                    value: store.sensitivity
                    onModified: (v) => store.edit("sensitivity", v)
                }
                ChoiceRow {
                    width: Math.min(parent.width, 460); label: "Follow mouse"
                    highlightId: "pointer_follow"
                    options: [{ "key": "0", "label": "Off" }, { "key": "1", "label": "Normal" }, { "key": "2", "label": "Loose" }]
                    current: String(store.followMouse)
                    onChosen: (k) => store.edit("followMouse", parseInt(k))
                }
                ChoiceRow {
                    width: Math.min(parent.width, 460); label: "Acceleration"
                    highlightId: "pointer_accel"
                    options: [{ "key": "", "label": "Default" }, { "key": "flat", "label": "Flat" }, { "key": "adaptive", "label": "Adaptive" }]
                    current: store.accelProfile
                    onChosen: (k) => store.edit("accelProfile", k)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Left-handed buttons"
                    highlightId: "pointer_left_handed"
                    checked: store.leftHanded
                    onToggled: (v) => store.edit("leftHanded", v)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Natural scroll"
                    highlightId: "pointer_natural_scroll"
                    checked: store.mouseNaturalScroll
                    onToggled: (v) => store.edit("mouseNaturalScroll", v)
                }
                SliderRow {
                    width: Math.min(parent.width, 460); label: "Scroll speed"
                    highlightId: "pointer_scroll_speed"
                    from: 0.2; to: 3; step: 0.1; decimals: 1
                    value: store.mouseScrollFactor
                    onModified: (v) => store.edit("mouseScrollFactor", v)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Middle-click pastes"
                    highlightId: "pointer_middle_click"
                    checked: store.middleClickPaste
                    onToggled: (v) => store.edit("middleClickPaste", v)
                }
            }

            SettingSection {
                width: parent.width
                title: "TOUCHPAD"
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Natural scroll"
                    highlightId: "touchpad_natural_scroll"
                    checked: store.naturalScroll
                    onToggled: (v) => store.edit("naturalScroll", v)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Tap to click"
                    highlightId: "touchpad_tap_click"
                    checked: store.tapToClick
                    onToggled: (v) => store.edit("tapToClick", v)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Tap and drag"
                    highlightId: "touchpad_tap_drag"
                    checked: store.tapAndDrag
                    onToggled: (v) => store.edit("tapAndDrag", v)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Disable while typing"
                    highlightId: "touchpad_dwt"
                    checked: store.disableWhileTyping
                    onToggled: (v) => store.edit("disableWhileTyping", v)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Click by finger count"
                    highlightId: "touchpad_clickfinger"
                    checked: store.clickfinger
                    onToggled: (v) => store.edit("clickfinger", v)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Emulate middle click"
                    highlightId: "touchpad_middle_emulation"
                    checked: store.middleEmulation
                    onToggled: (v) => store.edit("middleEmulation", v)
                }
                SliderRow {
                    width: Math.min(parent.width, 460); label: "Scroll speed"
                    highlightId: "touchpad_scroll_speed"
                    from: 0.2; to: 3; step: 0.1; decimals: 1
                    value: store.touchScrollFactor
                    onModified: (v) => store.edit("touchScrollFactor", v)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Swipe between workspaces"
                    highlightId: "touchpad_swipe_enable"
                    checked: store.workspaceSwipe
                    onToggled: (v) => store.edit("workspaceSwipe", v)
                }
                ChoiceRow {
                    width: Math.min(parent.width, 460); label: "Swipe fingers"
                    visible: store.workspaceSwipe
                    highlightId: "touchpad_swipe_fingers"
                    options: [{ "key": "3", "label": "3" }, { "key": "4", "label": "4" }]
                    current: String(store.swipeFingers)
                    onChosen: (k) => store.edit("swipeFingers", parseInt(k, 10))
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Natural swipe direction"
                    visible: store.workspaceSwipe
                    highlightId: "touchpad_swipe_natural"
                    checked: store.swipeInvert
                    onToggled: (v) => store.edit("swipeInvert", v)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Swipe past the last workspace to add one"
                    visible: store.workspaceSwipe
                    highlightId: "touchpad_swipe_create"
                    checked: store.swipeCreateNew
                    onToggled: (v) => store.edit("swipeCreateNew", v)
                }
                SliderRow {
                    width: Math.min(parent.width, 460); label: "Swipe distance"
                    visible: store.workspaceSwipe
                    highlightId: "touchpad_swipe_distance"
                    from: 100; to: 600; step: 20; decimals: 0
                    value: store.swipeDistance
                    onModified: (v) => store.edit("swipeDistance", v)
                }
            }

            SettingSection {
                width: parent.width
                title: "KEY REPEAT"
                HighlightableNumberField {
                    width: Math.min(parent.width, 460); label: "Repeat rate"; unit: "/s"
                    highlightId: "key_repeat_rate"
                    from: 1; to: 100; value: store.repeatRate
                    onModified: (v) => store.edit("repeatRate", v)
                }
                HighlightableNumberField {
                    width: Math.min(parent.width, 460); label: "Repeat delay"; unit: "ms"
                    highlightId: "key_repeat_delay"
                    from: 100; to: 2000; step: 50; value: store.repeatDelay
                    onModified: (v) => store.edit("repeatDelay", v)
                }
            }

            // camera calibration: unrelated to HyprStore (no Hyprland meaning),
            // so it's its own small JSON-backed singleton (WebcamPrefs) instead
            // of riding the hypr.json/settings.lua pipeline every other control
            // on this page uses. Only matters for the non-UVC bridge path in
            // ryoku-cmd-webcam; harmless (unread) on a plain UVC webcam.
            SettingSection {
                width: parent.width
                title: "CAMERA"
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Flip webcam 180°"
                    highlightId: "camera"
                    checked: page.flipDraft
                    onToggled: (v) => page.flipDraft = v
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Only applies to built-in cameras that need Ryoku's virtual-camera bridge (not plain USB webcams) -- some sensors are mounted upside-down with no orientation entry in libcamera's database, so the feed needs a manual flip."
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
        }
    }

    // --- action bar, mirrors Shell Settings ---------------------------------
    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        height: 60
        radius: Theme.radius
        color: page.anyDirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.08) : Theme.surfaceLo
        border.width: 1
        border.color: page.anyDirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.4) : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.medium } }
        Behavior on border.color { ColorAnimation { duration: Theme.medium } }

        Rectangle {
            id: statusDot
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 9
            height: 9
            radius: 4.5
            color: store.dirty ? Theme.ember : Theme.ok
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }

        Text {
            anchors.left: statusDot.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: page.anyDirty ? "Previewing unsaved changes" : "Saved \u00b7 live on your desktop"
            color: page.anyDirty ? Theme.bright : Theme.dim
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
                onClicked: store.resetInput()
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Revert"
                icon: "close"
                enabled: page.anyDirty
                onClicked: {
                    if (store.dirty)
                        store.revert();
                    if (page.flipDirty)
                        page.flipDraft = Qt.binding(() => WebcamPrefs.flip180);
                }
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Save"
                icon: "check"
                primary: true
                enabled: page.anyDirty
                onClicked: {
                    if (store.dirty)
                        store.save();
                    if (page.flipDirty)
                        WebcamPrefs.flip180 = page.flipDraft;
                }
            }
        }
    }
}
