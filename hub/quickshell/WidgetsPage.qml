pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Singletons"

// Desktop Widgets: live editor for the clock + weather widgets on the
// wallpaper. every edit lands on the running widgets at once via
// ~/.config/ryoku/widgets.json (throttled, atomic), which the widgets host
// watches. preview mirrors the live design so you can pick without leaning
// over the hub. Save keeps it; Revert and leaving the section put the saved
// look back. controls are matched to the value: steppers for exact pixels,
// sliders for size/opacity, segmented + dropdowns for choices.
Item {
    id: page

    readonly property var keys: [
        "clockEnabled", "clockDesign", "clockAccent",
        "clockScale", "clockAnchor", "clockX", "clockY", "clockLocked", "clockOpacity",
        "clockBg", "clockRadius", "dateShow", "dateDesign",
        "weatherEnabled", "weatherDesign", "weatherUnit", "weatherScope", "weatherAnimate",
        "weatherScale", "weatherAnchor", "weatherX", "weatherY", "weatherLocked", "weatherOpacity",
        "weatherBg", "weatherRadius",
        "calEnabled", "calDesign", "calAccent", "calWeekStart", "calScale",
        "calAnchor", "calX", "calY", "calLocked", "calOpacity", "calBg", "calRadius"
    ]

    // mirror of the widgets' canonical defaults (widgets Singletons/Config.qml),
    // for "Reset to defaults" only.
    readonly property var defaults: ({
        "clockEnabled": true, "clockDesign": "digital",
        "clockAccent": "wallust", "clockScale": 1.0, "clockAnchor": "top-left",
        "clockX": 72, "clockY": 64, "clockLocked": false, "clockOpacity": 1.0, "clockBg": "none",
        "clockRadius": 26, "dateShow": true, "dateDesign": "inline",
        "weatherEnabled": true, "weatherDesign": "card", "weatherUnit": "C", "weatherScope": "today",
        "weatherAnimate": true, "weatherScale": 1.0, "weatherAnchor": "top-right",
        "weatherX": 72, "weatherY": 64, "weatherLocked": false, "weatherOpacity": 1.0, "weatherBg": "glass",
        "weatherRadius": 26,
        "calEnabled": false, "calDesign": "month", "calAccent": "wallust", "calWeekStart": "mon",
        "calScale": 1.0, "calAnchor": "bottom-right", "calX": 72, "calY": 64, "calLocked": false,
        "calOpacity": 1.0, "calBg": "glass", "calRadius": 26
    })

    readonly property var anchorOptions: [
        { "key": "top-left", "label": "Top left" }, { "key": "top", "label": "Top" }, { "key": "top-right", "label": "Top right" },
        { "key": "left", "label": "Left" }, { "key": "center", "label": "Centre" }, { "key": "right", "label": "Right" },
        { "key": "bottom-left", "label": "Bottom left" }, { "key": "bottom", "label": "Bottom" }, { "key": "bottom-right", "label": "Bottom right" },
        { "key": "free", "label": "Free (dragged)" }
    ]

    property string group: "clock"
    // set by Hub.qml (from search jumping to a specific tab); applied once on
    // mount and again live if it changes while this page stays mounted.
    property string initialTab: ""
    onInitialTabChanged: if (page.initialTab.length > 0) page.group = page.initialTab
    Component.onCompleted: if (page.initialTab.length > 0) page.group = page.initialTab
    // emitted by a GeneralLinkSection's button, which jumps to General for a
    // setting that used to live on this page but is shell-wide now. highlight
    // is the target SettingSection/row's highlightId there, so the link also
    // flashes it instead of just landing on the page.
    signal navigate(string section, string highlight)

    // a settings section that's just an explanation + a jump-to-General
    // button, for a control that moved off this page since it isn't owned by
    // one widget (weather's location, the clock's seconds format).
    component GeneralLinkSection: SettingSection {
        id: gls
        property string note: ""
        property string highlight: ""
        Row {
            width: parent.width
            spacing: 12
            Text {
                width: parent.width - linkBtn.width - 12
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                text: gls.note
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 12
            }
            HubButton {
                id: linkBtn
                anchors.verticalCenter: parent.verticalCenter
                label: "Open General"
                icon: "compass"
                onClicked: page.navigate("general", gls.highlight)
            }
        }
    }

    property bool loaded: false
    property var committedVals: ({})

    QtObject {
        id: draft
        property bool clockEnabled: true
        property string clockDesign: "digital"
        property string clockAccent: "wallust"
        property real clockScale: 1.0
        property string clockAnchor: "top-left"
        property int clockX: 72
        property int clockY: 64
        property bool clockLocked: false
        property real clockOpacity: 1.0
        property string clockBg: "none"
        property int clockRadius: 26
        property bool dateShow: true
        property string dateDesign: "inline"
        property bool weatherEnabled: true
        property string weatherDesign: "card"
        property string weatherUnit: "C"
        property string weatherScope: "today"
        property bool weatherAnimate: true
        property real weatherScale: 1.0
        property string weatherAnchor: "top-right"
        property int weatherX: 72
        property int weatherY: 64
        property bool weatherLocked: false
        property real weatherOpacity: 1.0
        property string weatherBg: "glass"
        property int weatherRadius: 26
        property bool calEnabled: false
        property string calDesign: "month"
        property string calAccent: "wallust"
        property string calWeekStart: "mon"
        property real calScale: 1.0
        property string calAnchor: "bottom-right"
        property int calX: 72
        property int calY: 64
        property bool calLocked: false
        property real calOpacity: 1.0
        property string calBg: "glass"
        property int calRadius: 26
    }

    function sameVal(a, b) { return String(a) === String(b); }

    readonly property bool dirty: {
        if (!page.loaded)
            return false;
        for (var i = 0; i < page.keys.length; i++) {
            var k = page.keys[i];
            if (!page.sameVal(draft[k], page.committedVals[k]))
                return true;
        }
        return false;
    }

    function adopt() {
        var c = {};
        for (var i = 0; i < page.keys.length; i++) {
            var k = page.keys[i];
            draft[k] = adapter[k];
            c[k] = adapter[k];
        }
        page.committedVals = c;
    }

    // a later external write (e.g. a desktop widget drag or right-click) has
    // reloaded into the adapter. pull it into any key the user hasn't locally
    // edited and move that key's baseline forward, so it isn't flagged dirty
    // or resurrected on Save. locally-edited keys keep the user's draft.
    function adoptExternal() {
        var c = {};
        for (var i = 0; i < page.keys.length; i++) {
            var k = page.keys[i];
            if (page.sameVal(draft[k], page.committedVals[k])) {
                draft[k] = adapter[k];
                c[k] = adapter[k];
            } else {
                c[k] = page.committedVals[k];
            }
        }
        page.committedVals = c;
    }

    function flush() {
        for (var i = 0; i < page.keys.length; i++) {
            var k = page.keys[i];
            adapter[k] = draft[k];
        }
        cfg.writeAdapter();
    }

    // throttle live writes: apply immediately, then at most every interval
    // while the value keeps changing, with a trailing write. drag updates the
    // desktop smoothly without thrashing the file.
    property bool writePending: false
    Timer {
        id: throttle
        interval: 70
        onTriggered: {
            if (page.writePending) {
                page.writePending = false;
                page.flush();
                throttle.restart();
            }
        }
    }
    function edit(k, v) {
        draft[k] = v;
        if (throttle.running) {
            page.writePending = true;
        } else {
            page.flush();
            throttle.start();
        }
    }

    function snapshotDraft() {
        var s = {};
        for (var i = 0; i < page.keys.length; i++) {
            var k = page.keys[i];
            s[k] = draft[k];
        }
        return s;
    }
    function save() {
        throttle.stop();
        page.writePending = false;
        page.flush();
        page.committedVals = page.snapshotDraft();
    }
    function revert() {
        throttle.stop();
        page.writePending = false;
        for (var i = 0; i < page.keys.length; i++) {
            var k = page.keys[i];
            draft[k] = page.committedVals[k];
        }
        page.flush();
    }
    function resetDefaults() {
        for (var i = 0; i < page.keys.length; i++) {
            var k = page.keys[i];
            page.edit(k, page.defaults[k]);
        }
    }

    FileView {
        id: cfg
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/widgets.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: { if (!page.loaded) { page.adopt(); page.loaded = true; } else { page.adoptExternal(); } }
        onLoadFailed: { if (!page.loaded) { page.adopt(); page.loaded = true; } }

        JsonAdapter {
            id: adapter
            property bool clockEnabled: true
            property string clockDesign: "digital"
            property string clockAccent: "wallust"
            property real clockScale: 1.0
            property string clockAnchor: "top-left"
            property int clockX: 72
            property int clockY: 64
            property bool clockLocked: false
            property real clockOpacity: 1.0
            property string clockBg: "none"
            property int clockRadius: 26
            property bool dateShow: true
            property string dateDesign: "inline"
            property bool weatherEnabled: true
            property string weatherDesign: "card"
            property string weatherUnit: "C"
            property string weatherScope: "today"
            property bool weatherAnimate: true
            property real weatherScale: 1.0
            property string weatherAnchor: "top-right"
            property int weatherX: 72
            property int weatherY: 64
            property bool weatherLocked: false
            property real weatherOpacity: 1.0
            property string weatherBg: "glass"
            property int weatherRadius: 26
            property bool calEnabled: false
            property string calDesign: "month"
            property string calAccent: "wallust"
            property string calWeekStart: "mon"
            property real calScale: 1.0
            property string calAnchor: "bottom-right"
            property int calX: 72
            property int calY: 64
            property bool calLocked: false
            property real calOpacity: 1.0
            property string calBg: "glass"
            property int calRadius: 26
        }
    }

    // leaving the section (or closing the hub) with unsaved edits puts the
    // saved look back, so a preview is never left applied by accident.
    Component.onDestruction: {
        if (page.loaded && page.dirty) {
            for (var i = 0; i < page.keys.length; i++) {
                var k = page.keys[i];
                adapter[k] = page.committedVals[k];
            }
            cfg.writeAdapter();
        }
    }

    // --- top: widget tabs + live hint --------------------------------------
    Segmented {
        id: tabs
        anchors.left: parent.left
        anchors.top: parent.top
        model: [{ "key": "clock", "label": "Clock" }, { "key": "weather", "label": "Weather" }, { "key": "calendar", "label": "Calendar" }]
        current: page.group
        onSelected: (k) => page.group = k
    }

    Text {
        anchors.left: tabs.right
        anchors.leftMargin: 18
        anchors.verticalCenter: tabs.verticalCenter
        text: "Edits show on your desktop as you make them"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    // --- controls ----------------------------------------------------------
    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: tabs.bottom
        anchors.topMargin: 24
        anchors.bottom: bar.top
        anchors.bottomMargin: 18
        contentWidth: width
        contentHeight: Math.max(loader.height, height)
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

        Loader {
            id: loader
            width: flick.width - 12
            height: item ? item.implicitHeight : 0
            sourceComponent: page.group === "clock" ? clockTab : (page.group === "weather" ? weatherTab : calendarTab)
            onLoaded: { if (item) { item.opacity = 0; fade.restart(); } }
        }

        NumberAnimation { id: fade; target: loader.item; property: "opacity"; to: 1; duration: Theme.medium; easing.type: Theme.ease }
    }

    // --- clock tab ---------------------------------------------------------
    Component {
        id: clockTab
        Column {
            id: clockCol
            spacing: 22

            Rectangle {
                width: clockCol.width
                height: 200
                radius: Theme.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#191320" }
                    GradientStop { position: 1.0; color: "#241a16" }
                }
                border.width: 1
                border.color: Theme.line
                clip: true

                ClockPreview {
                    anchors.fill: parent
                    anchors.margins: 1
                    opacity: draft.clockEnabled ? 1 : 0.32
                    design: draft.clockDesign
                    is24: Config.clock24h
                    seconds: Config.clockSeconds
                    accentChoice: draft.clockAccent
                    dateShow: draft.dateShow
                    dateDesign: draft.dateDesign
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 12
                    width: clockTag.width + 18
                    height: 20
                    radius: Theme.radius
                    color: Qt.rgba(0, 0, 0, 0.4)
                    Text {
                        id: clockTag
                        anchors.centerIn: parent
                        text: draft.clockEnabled ? "LIVE PREVIEW" : "DISABLED"
                        color: Theme.dim
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 2
                    }
                }
            }

            Row {
                id: clockRow
                width: clockCol.width
                spacing: 56
                readonly property real colW: (width - spacing) / 2

                Column {
                    width: clockRow.colW
                    spacing: 30

                    SettingSection {
                        width: parent.width
                        title: "WIDGET"
                        ToggleRow { width: parent.width; label: "Enabled"; highlightId: "clock_widget_enabled"; checked: draft.clockEnabled; onToggled: (v) => page.edit("clockEnabled", v) }
                        Dropdown {
                            width: parent.width; label: "Face"
                            highlightId: "clock_widget_face"
                            options: [{ "key": "digital", "label": "Digital" }, { "key": "minimal", "label": "Minimal" }, { "key": "analog", "label": "Analog" }, { "key": "flip", "label": "Flip" }, { "key": "rings", "label": "Rings" }]
                            current: draft.clockDesign
                            onChosen: (k) => page.edit("clockDesign", k)
                        }
                        ChoiceRow {
                            width: parent.width; label: "Accent"
                            highlightId: "clock_widget_accent"
                            options: [{ "key": "wallust", "label": "Wallust" }, { "key": "brand", "label": "Brand" }, { "key": "mono", "label": "Mono" }]
                            current: draft.clockAccent
                            onChosen: (k) => page.edit("clockAccent", k)
                        }
                    }

                    GeneralLinkSection {
                        width: parent.width
                        title: "FORMAT"
                        note: "Show seconds is shared desktop-wide, on General: the bar and this widget both follow it."
                        highlight: "time_seconds"
                    }

                    SettingSection {
                        width: parent.width
                        title: "DATE"
                        ToggleRow { width: parent.width; label: "Show date"; highlightId: "clock_date_show"; checked: draft.dateShow; onToggled: (v) => page.edit("dateShow", v) }
                        ChoiceRow {
                            width: parent.width; label: "Date style"
                            highlightId: "clock_date_style"
                            options: [{ "key": "inline", "label": "Inline" }, { "key": "badge", "label": "Badge" }, { "key": "stacked", "label": "Stacked" }]
                            current: draft.dateDesign
                            onChosen: (k) => page.edit("dateDesign", k)
                        }
                    }
                }

                Column {
                    width: clockRow.colW
                    spacing: 30

                    SettingSection {
                        width: parent.width
                        title: "SIZE & SHAPE"
                        SliderRow { width: parent.width; label: "Size"; highlightId: "clock_size_scale"; from: 0.5; to: 2.5; step: 0.05; decimals: 2; value: draft.clockScale; onModified: (v) => page.edit("clockScale", v) }
                        ChoiceRow {
                            width: parent.width; label: "Background"
                            highlightId: "clock_size_bg"
                            options: [{ "key": "none", "label": "None" }, { "key": "card", "label": "Card" }, { "key": "glass", "label": "Glass" }]
                            current: draft.clockBg
                            onChosen: (k) => page.edit("clockBg", k)
                        }
                        HighlightableNumberField { visible: draft.clockBg !== "none"; width: parent.width; label: "Corner radius"; highlightId: "clock_size_radius"; unit: "px"; from: 0; to: 60; value: draft.clockRadius; onModified: (v) => page.edit("clockRadius", v) }
                        SliderRow { width: parent.width; label: "Opacity"; highlightId: "clock_size_opacity"; percent: true; from: 0.2; to: 1; step: 0.01; value: draft.clockOpacity; onModified: (v) => page.edit("clockOpacity", v) }
                    }

                    SettingSection {
                        width: parent.width
                        title: "PLACEMENT"
                        Dropdown { width: parent.width; label: "Anchor"; highlightId: "clock_placement_anchor"; options: page.anchorOptions; current: draft.clockAnchor; onChosen: (k) => page.edit("clockAnchor", k) }
                        HighlightableNumberField { visible: draft.clockAnchor === "free"; width: parent.width; label: "X"; highlightId: "clock_placement_position"; unit: "px"; from: 0; to: 5000; value: draft.clockX; onModified: (v) => page.edit("clockX", v) }
                        HighlightableNumberField { visible: draft.clockAnchor === "free"; width: parent.width; label: "Y"; highlightId: "clock_placement_position"; unit: "px"; from: 0; to: 5000; value: draft.clockY; onModified: (v) => page.edit("clockY", v) }
                        ToggleRow { width: parent.width; label: "Lock on desktop"; highlightId: "clock_placement_lock"; checked: draft.clockLocked; onToggled: (v) => page.edit("clockLocked", v) }
                    }
                }
            }
        }
    }

    // --- weather tab -------------------------------------------------------
    Component {
        id: weatherTab
        Column {
            id: wxCol
            spacing: 22

            Rectangle {
                width: wxCol.width
                height: 200
                radius: Theme.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#191320" }
                    GradientStop { position: 1.0; color: "#241a16" }
                }
                border.width: 1
                border.color: Theme.line
                clip: true

                WeatherPreview {
                    anchors.fill: parent
                    anchors.margins: 1
                    opacity: draft.weatherEnabled ? 1 : 0.32
                    design: draft.weatherDesign
                    unit: draft.weatherUnit
                    scope: draft.weatherScope
                    animate: draft.weatherAnimate
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 12
                    width: wxTag.width + 18
                    height: 20
                    radius: Theme.radius
                    color: Qt.rgba(0, 0, 0, 0.4)
                    Text {
                        id: wxTag
                        anchors.centerIn: parent
                        text: draft.weatherEnabled ? "LIVE PREVIEW" : "DISABLED"
                        color: Theme.dim
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 2
                    }
                }
            }

            Row {
                id: wxRow
                width: wxCol.width
                spacing: 56
                readonly property real colW: (width - spacing) / 2

                Column {
                    width: wxRow.colW
                    spacing: 30

                    GeneralLinkSection {
                        width: parent.width
                        title: "LOCATION"
                        highlightId: "weather_location"
                        note: "Shared desktop-wide, on General: the bar, sidebar, and this widget all follow it."
                        highlight: "general_weather_location"
                    }

                    SettingSection {
                        width: parent.width
                        title: "WIDGET"
                        ToggleRow { width: parent.width; label: "Enabled"; highlightId: "weather_widget_enabled"; checked: draft.weatherEnabled; onToggled: (v) => page.edit("weatherEnabled", v) }
                        ChoiceRow {
                            width: parent.width; label: "Design"
                            highlightId: "weather_widget_design"
                            options: [{ "key": "card", "label": "Card" }, { "key": "minimal", "label": "Minimal" }, { "key": "strip", "label": "Strip" }]
                            current: draft.weatherDesign
                            onChosen: (k) => page.edit("weatherDesign", k)
                        }
                    }

                    SettingSection {
                        width: parent.width
                        title: "READOUT"
                        ChoiceRow {
                            width: parent.width; label: "Unit"
                            highlightId: "weather_readout_unit"
                            options: [{ "key": "C", "label": "\u00b0C" }, { "key": "F", "label": "\u00b0F" }]
                            current: draft.weatherUnit
                            onChosen: (k) => page.edit("weatherUnit", k)
                        }
                        ChoiceRow {
                            width: parent.width; label: "Forecast"
                            highlightId: "weather_readout_scope"
                            options: [{ "key": "today", "label": "Today" }, { "key": "week", "label": "Week" }]
                            current: draft.weatherScope
                            onChosen: (k) => page.edit("weatherScope", k)
                        }
                        ToggleRow { width: parent.width; label: "Live animations"; highlightId: "weather_readout_animate"; checked: draft.weatherAnimate; onToggled: (v) => page.edit("weatherAnimate", v) }
                    }
                }

                Column {
                    width: wxRow.colW
                    spacing: 30

                    SettingSection {
                        width: parent.width
                        title: "SIZE & SHAPE"
                        SliderRow { width: parent.width; label: "Size"; highlightId: "weather_size_scale"; from: 0.5; to: 2.5; step: 0.05; decimals: 2; value: draft.weatherScale; onModified: (v) => page.edit("weatherScale", v) }
                        ChoiceRow {
                            width: parent.width; label: "Background"
                            highlightId: "weather_size_bg"
                            options: [{ "key": "none", "label": "None" }, { "key": "card", "label": "Card" }, { "key": "glass", "label": "Glass" }]
                            current: draft.weatherBg
                            onChosen: (k) => page.edit("weatherBg", k)
                        }
                        HighlightableNumberField { visible: draft.weatherBg !== "none"; width: parent.width; label: "Corner radius"; highlightId: "weather_size_radius"; unit: "px"; from: 0; to: 60; value: draft.weatherRadius; onModified: (v) => page.edit("weatherRadius", v) }
                        SliderRow { width: parent.width; label: "Opacity"; highlightId: "weather_size_opacity"; percent: true; from: 0.2; to: 1; step: 0.01; value: draft.weatherOpacity; onModified: (v) => page.edit("weatherOpacity", v) }
                    }

                    SettingSection {
                        width: parent.width
                        title: "PLACEMENT"
                        Dropdown { width: parent.width; label: "Anchor"; highlightId: "weather_placement_anchor"; options: page.anchorOptions; current: draft.weatherAnchor; onChosen: (k) => page.edit("weatherAnchor", k) }
                        HighlightableNumberField { visible: draft.weatherAnchor === "free"; width: parent.width; label: "X"; highlightId: "weather_placement_position"; unit: "px"; from: 0; to: 5000; value: draft.weatherX; onModified: (v) => page.edit("weatherX", v) }
                        HighlightableNumberField { visible: draft.weatherAnchor === "free"; width: parent.width; label: "Y"; highlightId: "weather_placement_position"; unit: "px"; from: 0; to: 5000; value: draft.weatherY; onModified: (v) => page.edit("weatherY", v) }
                        ToggleRow { width: parent.width; label: "Lock on desktop"; highlightId: "weather_placement_lock"; checked: draft.weatherLocked; onToggled: (v) => page.edit("weatherLocked", v) }
                    }
                }
            }
        }
    }

    // --- calendar tab ------------------------------------------------------
    Component {
        id: calendarTab
        Column {
            id: calCol
            spacing: 22

            Rectangle {
                width: calCol.width
                height: 260
                radius: Theme.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#191320" }
                    GradientStop { position: 1.0; color: "#241a16" }
                }
                border.width: 1
                border.color: Theme.line
                clip: true

                CalendarPreview {
                    anchors.fill: parent
                    anchors.margins: 1
                    opacity: draft.calEnabled ? 1 : 0.32
                    design: draft.calDesign
                    accentChoice: draft.calAccent
                    weekStart: draft.calWeekStart
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 12
                    width: calTag.width + 18
                    height: 20
                    radius: Theme.radius
                    color: Qt.rgba(0, 0, 0, 0.4)
                    Text {
                        id: calTag
                        anchors.centerIn: parent
                        text: draft.calEnabled ? "LIVE PREVIEW" : "DISABLED"
                        color: Theme.dim
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 2
                    }
                }
            }

            Text {
                width: calCol.width
                text: "Notes you leave on a day sync with the pill's calendar, and back."
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Row {
                id: calRow
                width: calCol.width
                spacing: 56
                readonly property real colW: (width - spacing) / 2

                Column {
                    width: calRow.colW
                    spacing: 30

                    SettingSection {
                        width: parent.width
                        title: "WIDGET"
                        ToggleRow { width: parent.width; label: "Enabled"; highlightId: "cal_widget_enabled"; checked: draft.calEnabled; onToggled: (v) => page.edit("calEnabled", v) }
                        Dropdown {
                            width: parent.width; label: "Design"
                            highlightId: "cal_widget_design"
                            options: [{ "key": "month", "label": "Month" }, { "key": "minimal", "label": "Minimal" }, { "key": "agenda", "label": "Agenda" }, { "key": "week", "label": "Week" }, { "key": "heat", "label": "Heatmap" }]
                            current: draft.calDesign
                            onChosen: (k) => page.edit("calDesign", k)
                        }
                        ChoiceRow {
                            width: parent.width; label: "Accent"
                            highlightId: "cal_widget_accent"
                            options: [{ "key": "wallust", "label": "Wallust" }, { "key": "brand", "label": "Brand" }, { "key": "mono", "label": "Mono" }]
                            current: draft.calAccent
                            onChosen: (k) => page.edit("calAccent", k)
                        }
                    }

                    SettingSection {
                        width: parent.width
                        title: "WEEK"
                        ChoiceRow {
                            width: parent.width; label: "Starts on"
                            highlightId: "cal_week"
                            options: [{ "key": "mon", "label": "Monday" }, { "key": "sun", "label": "Sunday" }]
                            current: draft.calWeekStart
                            onChosen: (k) => page.edit("calWeekStart", k)
                        }
                    }
                }

                Column {
                    width: calRow.colW
                    spacing: 30

                    SettingSection {
                        width: parent.width
                        title: "SIZE & SHAPE"
                        SliderRow { width: parent.width; label: "Size"; highlightId: "cal_size_scale"; from: 0.5; to: 2.5; step: 0.05; decimals: 2; value: draft.calScale; onModified: (v) => page.edit("calScale", v) }
                        ChoiceRow {
                            width: parent.width; label: "Background"
                            highlightId: "cal_size_bg"
                            options: [{ "key": "none", "label": "None" }, { "key": "card", "label": "Card" }, { "key": "glass", "label": "Glass" }]
                            current: draft.calBg
                            onChosen: (k) => page.edit("calBg", k)
                        }
                        HighlightableNumberField { visible: draft.calBg !== "none"; width: parent.width; label: "Corner radius"; highlightId: "cal_size_radius"; unit: "px"; from: 0; to: 60; value: draft.calRadius; onModified: (v) => page.edit("calRadius", v) }
                        SliderRow { width: parent.width; label: "Opacity"; highlightId: "cal_size_opacity"; percent: true; from: 0.2; to: 1; step: 0.01; value: draft.calOpacity; onModified: (v) => page.edit("calOpacity", v) }
                    }

                    SettingSection {
                        width: parent.width
                        title: "PLACEMENT"
                        Dropdown { width: parent.width; label: "Anchor"; highlightId: "cal_placement_anchor"; options: page.anchorOptions; current: draft.calAnchor; onChosen: (k) => page.edit("calAnchor", k) }
                        HighlightableNumberField { visible: draft.calAnchor === "free"; width: parent.width; label: "X"; highlightId: "cal_placement_position"; unit: "px"; from: 0; to: 5000; value: draft.calX; onModified: (v) => page.edit("calX", v) }
                        HighlightableNumberField { visible: draft.calAnchor === "free"; width: parent.width; label: "Y"; highlightId: "cal_placement_position"; unit: "px"; from: 0; to: 5000; value: draft.calY; onModified: (v) => page.edit("calY", v) }
                        ToggleRow { width: parent.width; label: "Lock on desktop"; highlightId: "cal_placement_lock"; checked: draft.calLocked; onToggled: (v) => page.edit("calLocked", v) }
                    }
                }
            }
        }
    }

    // --- bottom: status + actions ------------------------------------------
    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        height: 60
        radius: Theme.radius
        color: page.dirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.08) : Theme.surfaceLo
        border.width: 1
        border.color: page.dirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.4) : Theme.line
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
            color: page.dirty ? Theme.ember : Theme.ok
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }

        Text {
            anchors.left: statusDot.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: page.dirty ? "Previewing unsaved changes" : "Saved \u00b7 live on your desktop"
            color: page.dirty ? Theme.bright : Theme.dim
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            HubButton { anchors.verticalCenter: parent.verticalCenter; label: "Reset to defaults"; icon: "refresh"; onClicked: page.resetDefaults() }
            HubButton { anchors.verticalCenter: parent.verticalCenter; label: "Revert"; icon: "close"; enabled: page.dirty; onClicked: page.revert() }
            HubButton { anchors.verticalCenter: parent.verticalCenter; label: "Save"; icon: "check"; primary: true; enabled: page.dirty; onClicked: page.save() }
        }
    }
}
