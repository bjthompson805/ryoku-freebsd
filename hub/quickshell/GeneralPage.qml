pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Singletons"

// General: desktop-wide preferences that aren't owned by any one surface.
// Starts with the clock format (12h/24h) -- it used to live on Desktop
// Widgets, but it drives every clock in the shell (bar, sidebar, launcher,
// Hub, and the desktop widget), not just the widget, so it belongs here
// instead. Weather location/units moved here from Shell -> Global, and
// clock seconds from Desktop Widgets' Clock tab, for the same reason: each
// drives more than the one surface it used to live on. Writes
// ~/.config/ryoku/general.json, watched live by every surface's Config
// singleton. Same live-preview-then-Save contract as every other Hub
// settings page: edits apply immediately (so the desktop reflects them as
// you go), but only Save moves the baseline; Revert or leaving with unsaved
// edits puts the saved state back.
Item {
    id: page

    readonly property var keys: ["clock24h", "clockSeconds", "weatherLocation", "weatherUnit"]

    readonly property var defaults: ({
        "clock24h": true, "clockSeconds": false, "weatherLocation": "", "weatherUnit": "auto"
    })

    property bool loaded: false
    property var committedVals: ({})

    QtObject {
        id: draft
        property bool clock24h: true
        property bool clockSeconds: false
        property string weatherLocation: ""
        property string weatherUnit: "auto"
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

    // a later external write to general.json reloaded into the adapter. pull
    // it into any key the user hasn't locally edited, leaving edited keys'
    // drafts and baselines untouched (mirrors WidgetsPage.qml/
    // ShellSettingsPage.qml -- unlikely to fire for this file in practice
    // since only this page writes it, but keeps the same contract).
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

    // throttle live writes: apply immediately, then at most once per interval
    // while the value keeps changing, with a trailing write.
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

    // one-time carry-forward of weatherLocation/weatherUnit from shell.json,
    // where they used to live before the move to General. Gated on
    // adapter.weatherMigrated so it only ever runs once, the first time this
    // page loads post-move; shell.json's copy is never consulted again after.
    function migrateWeather() {
        if (adapter.weatherMigrated)
            return;
        var old = shellCfg.text();
        if (old) {
            try {
                var parsed = JSON.parse(old);
                if (parsed.weatherLocation) adapter.weatherLocation = parsed.weatherLocation;
                if (parsed.weatherUnit) adapter.weatherUnit = parsed.weatherUnit;
            } catch (e) {
                console.log("general: shell.json weather migration parse failed: " + e);
            }
        }
        adapter.weatherMigrated = true;
        cfg.writeAdapter();
    }

    // same carry-forward for clockSeconds, from widgets.json where Desktop
    // Widgets' Clock tab used to own it.
    function migrateClockSeconds() {
        if (adapter.clockSecondsMigrated)
            return;
        var old = widgetsCfg.text();
        if (old) {
            try {
                var parsed = JSON.parse(old);
                if (typeof parsed.clockSeconds === "boolean") adapter.clockSeconds = parsed.clockSeconds;
            } catch (e) {
                console.log("general: widgets.json clockSeconds migration parse failed: " + e);
            }
        }
        adapter.clockSecondsMigrated = true;
        cfg.writeAdapter();
    }

    FileView {
        id: cfg
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/general.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: { if (!page.loaded) { page.migrateWeather(); page.migrateClockSeconds(); page.adopt(); page.loaded = true; } else { page.adoptExternal(); } }
        onLoadFailed: { if (!page.loaded) { page.migrateWeather(); page.migrateClockSeconds(); page.adopt(); page.loaded = true; } }

        JsonAdapter {
            id: adapter
            property bool clock24h: true
            property bool clockSeconds: false
            property string weatherLocation: ""
            property string weatherUnit: "auto"
            property bool weatherMigrated: false
            property bool clockSecondsMigrated: false
        }
    }

    // read-only, one-shot: only consulted by migrateWeather() above, on a
    // general.json that hasn't carried weatherLocation/weatherUnit forward
    // yet. shell.json remains ShellSettingsPage's file to write.
    FileView {
        id: shellCfg
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/shell.json"
        blockLoading: true
        watchChanges: false
        printErrors: false
    }

    // read-only, one-shot: only consulted by migrateClockSeconds() above, on
    // a general.json that hasn't carried clockSeconds forward yet. widgets.json
    // remains WidgetsPage's file to write.
    FileView {
        id: widgetsCfg
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/widgets.json"
        blockLoading: true
        watchChanges: false
        printErrors: false
    }

    // leaving the page (or closing Hub) with unsaved edits puts the saved
    // state back, so a preview is never left applied by accident -- same as
    // every other draft-gated Hub settings page.
    Component.onDestruction: {
        if (page.loaded && page.dirty) {
            for (var i = 0; i < page.keys.length; i++) {
                var k = page.keys[i];
                adapter[k] = page.committedVals[k];
            }
            cfg.writeAdapter();
        }
    }

    Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bar.top
        anchors.margins: 4
        anchors.bottomMargin: 18
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Column {
            id: col
            width: parent.width
            spacing: 26

            SettingSection {
                width: col.width
                title: "TIME"

                ToggleRow {
                    width: parent.width
                    label: "24-hour clock (applies everywhere: the bar, sidebar, launcher, Hub, and the desktop clock widget)"
                    highlightId: "time_24h"
                    checked: draft.clock24h
                    onToggled: (v) => page.edit("clock24h", v)
                }
                ToggleRow {
                    width: parent.width
                    label: "Show seconds (applies to the bar and the desktop clock widget)"
                    highlightId: "time_seconds"
                    checked: draft.clockSeconds
                    onToggled: (v) => page.edit("clockSeconds", v)
                }
            }

            SettingSection {
                width: col.width
                title: "WEATHER"

                SettingField {
                    width: parent.width; label: "Location"
                    highlightId: "general_weather_location"
                    fieldWidth: 200
                    placeholder: "Auto (from IP)"
                    value: draft.weatherLocation
                    onCommitted: (v) => page.edit("weatherLocation", v)
                }
                ChoiceRow {
                    width: parent.width; label: "Units"
                    highlightId: "weather_units"
                    options: [{ "key": "auto", "label": "Auto" }, { "key": "celsius", "label": "°C" }, { "key": "fahrenheit", "label": "°F" }]
                    current: draft.weatherUnit
                    onChosen: (k) => page.edit("weatherUnit", k)
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
            text: page.dirty ? "Previewing unsaved changes" : "Saved · live on your desktop"
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

            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Reset to defaults"
                icon: "refresh"
                onClicked: page.resetDefaults()
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Revert"
                icon: "close"
                enabled: page.dirty
                onClicked: page.revert()
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Save"
                icon: "check"
                primary: true
                enabled: page.dirty
                onClicked: page.save()
            }
        }
    }
}
