pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "Singletons"

// add-ons = home for installed plugins. bento grid of cards (preview + name)
// opens that plugin's own settings, rendered from manifest.metadata.settings
// by PluginSettingsForm, plus its enable toggle, host, and a remove. every
// change goes through `ryoku-plugins-place` -> plugins.json; the shell watches
// the file, so the desktop retunes live.
//
// installed = discover.sh --all (manifest + placement merged). browsing and
// installing new ones lives in the Store; this page only manages what's here.
Item {
    id: page

    property var plugins: []
    property string view: "grid"      // grid | detail
    property var sel: ({})            // selected { id, dir, manifest, placement }
    property string busyId: ""
    property var catalog: []          // available versions, from the Store catalogue

    readonly property string shellDir: Quickshell.env("RYOKU_SHELL_DIR")
    readonly property string script: (shellDir && shellDir.length > 0)
        ? shellDir + "/quickshell/plugins/discover.sh"
        : (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickshell/plugins/discover.sh"

    function refresh() { listProc.running = false; listProc.running = true; }
    function loadCatalog() { catProc.running = false; catProc.running = true; }
    function catalogEntry(id) {
        for (var i = 0; i < page.catalog.length; i++) if (page.catalog[i].id === id) return page.catalog[i];
        return null;
    }
    // semver compare: 1 if a>b, 0 equal, -1 if a<b. missing parts = 0.
    function cmpSemver(a, b) {
        var pa = String(a || "0").split(".").map(function (n) { return parseInt(n, 10) || 0; });
        var pb = String(b || "0").split(".").map(function (n) { return parseInt(n, 10) || 0; });
        for (var i = 0; i < Math.max(pa.length, pb.length); i++) {
            var x = pa[i] || 0, y = pb[i] || 0;
            if (x !== y) return x < y ? -1 : 1;
        }
        return 0;
    }
    // an installed plugin -> the newer catalogue version, or "" when up to date
    // / unknown. Drives the Update button beside Remove.
    function updateFor(pl) {
        var inst = (pl && pl.manifest && pl.manifest.version) ? pl.manifest.version : "";
        var ce = page.catalogEntry(pl ? pl.id : "");
        var avail = ce ? (ce.version || "") : "";
        if (!inst || !avail) return "";
        return page.cmpSemver(avail, inst) > 0 ? avail : "";
    }
    function install(id) {
        page.busyId = id;
        installProc.command = ["ryoku-hub", "extras", "plugin", id];
        installProc.running = true;
    }
    function reselect() {
        if (!page.sel || !page.sel.id) return;
        for (var i = 0; i < page.plugins.length; i++)
            if (page.plugins[i].id === page.sel.id) { page.sel = page.plugins[i]; return; }
    }
    function place(id, field, a, b, c, d) {
        var args = ["ryoku-plugins-place", id, field];
        for (var v of [a, b, c, d]) if (v !== undefined) args.push("" + v);
        placeProc.command = args;
        placeProc.running = true;
    }
    function setSetting(id, key, value) {
        var obj = {};
        obj[key] = value;
        settingsProc.command = ["ryoku-plugins-place", id, "settings", JSON.stringify(obj)];
        settingsProc.running = true;
    }
    function removePlugin(id) {
        page.busyId = id;
        place(id, "forget");
        rmProc.command = ["ryoku-hub", "extras", "pluginremove", id];
        rmProc.running = true;
    }

    Component.onCompleted: { page.refresh(); page.loadCatalog(); }

    Process {
        id: listProc
        command: ["bash", page.script, "--all"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.plugins = JSON.parse(text || "[]"); } catch (e) { page.plugins = []; }
                page.reselect();
            }
        }
    }
    Process { id: placeProc; onExited: page.refresh() }
    Process { id: settingsProc; onExited: page.refresh() }
    Process { id: rmProc; onExited: { page.busyId = ""; page.view = "grid"; page.refresh(); } }
    Process {
        id: catProc
        command: ["ryoku-hub", "extras", "plugincatalog"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.catalog = (JSON.parse(text || "{}").plugins) || []; } catch (e) { page.catalog = []; } }
        }
    }
    Process { id: installProc; onExited: { page.busyId = ""; page.refresh(); page.loadCatalog(); } }

    ShowcaseBackdrop { anchors.fill: parent; visible: page.view === "grid" }

    // ── grid: installed plugins as bento cards ──────────────────────────────
    Flickable {
        anchors.fill: parent
        visible: page.view === "grid"
        contentHeight: grid.implicitHeight + 40
        clip: true

        Flow {
            id: grid
            width: parent.width
            spacing: 18
            topPadding: 4

            Repeater {
                model: page.plugins
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property var man: card.modelData.manifest || ({})
                    readonly property var place: card.modelData.placement || ({})
                    readonly property bool on: card.place.enabled === true
                    readonly property string preview: "file://" + card.modelData.dir + "/assets/preview-widget.png"

                    width: Math.max(280, (grid.width - 18 * 2) / 3)
                    height: 248
                    radius: Theme.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.cardTop }
                        GradientStop { position: 1.0; color: Theme.cardBot }
                    }
                    border.width: 1
                    border.color: cardHov.hovered ? Theme.ember : Theme.line
                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }
                    scale: cardHov.hovered ? 1.012 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(0, 0, 0, 0.45)
                        shadowBlur: 0.9
                        shadowVerticalOffset: 8
                        autoPaddingEnabled: true
                    }

                    // preview window.
                    Rectangle {
                        id: shot
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        height: 150
                        radius: Theme.radius
                        color: Theme.surfaceLo
                        clip: true

                        Image {
                            id: shotImg
                            anchors.fill: parent
                            source: card.preview
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 640
                            visible: status === Image.Ready
                        }
                        // fallback when there's no preview asset.
                        Icon {
                            anchors.centerIn: parent
                            visible: shotImg.status !== Image.Ready
                            name: card.man.defaults && card.man.defaults.icon ? card.man.defaults.icon : "widgets"
                            size: 30
                            tint: Theme.faint
                        }

                        // enabled pip.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            width: dotText.implicitWidth + 18
                            height: 20
                            radius: Theme.radius
                            color: card.on ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.18) : Qt.rgba(0, 0, 0, 0.4)
                            Text {
                                id: dotText
                                anchors.centerIn: parent
                                text: card.on ? "ON" : "OFF"
                                color: card.on ? Theme.ok : Theme.faint
                                font.family: Theme.mono
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.5
                            }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: shot.bottom
                        anchors.margins: 14
                        anchors.topMargin: 12
                        text: card.man.name || card.modelData.id
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 14
                        text: (card.place.host || (card.man.defaults && card.man.defaults.host) || "")
                            + ((card.man.metadata && card.man.metadata.settings && card.man.metadata.settings.length > 0)
                                ? "  ·  " + card.man.metadata.settings.length + " settings" : "")
                        color: Theme.dim
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        elide: Text.ElideRight
                    }

                    HoverHandler { id: cardHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { page.sel = card.modelData; page.view = "detail"; } }
                }
            }
        }

        // empty state.
        Column {
            visible: page.plugins.length === 0
            anchors.centerIn: parent
            spacing: 10
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "widgets"; size: 34; tint: Theme.faint }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No add-ons installed. Open the Store to browse and install."
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 13
            }
        }
    }

    // ── detail: one plugin's settings ───────────────────────────────────────
    Flickable {
        anchors.fill: parent
        visible: page.view === "detail"
        contentHeight: detailCol.implicitHeight + 40
        clip: true

        Column {
            id: detailCol
            width: parent.width
            spacing: 20

            // back + name + remove.
            Item {
                width: parent.width
                height: 34
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron"
                        size: 16
                        rotation: 90
                        tint: backHov.hovered ? Theme.bright : Theme.dim
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (page.sel.manifest && page.sel.manifest.name) ? page.sel.manifest.name : (page.sel.id || "")
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (page.sel.manifest && page.sel.manifest.version) ? ("v" + page.sel.manifest.version) : ""
                        visible: text !== ""
                        color: Theme.faint
                        font.family: Theme.mono
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }
                HoverHandler { id: backHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: page.view = "grid" }

                // remove.
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    // UPDATE: only when the catalogue has a newer version.
                    Rectangle {
                        visible: page.updateFor(page.sel) !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        height: 30
                        width: updLabel.implicitWidth + 22
                        radius: Theme.radius
                        color: updHov.hovered ? Theme.frameBg : "transparent"
                        border.width: 1
                        border.color: Theme.ember
                        opacity: page.busyId === page.sel.id ? 0.6 : 1
                        Behavior on color { ColorAnimation { duration: Theme.quick } }
                        Text {
                            id: updLabel
                            anchors.centerIn: parent
                            text: page.busyId === page.sel.id ? "UPDATING" : ("UPDATE " + page.updateFor(page.sel))
                            color: Theme.ember
                            font.family: Theme.mono
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.5
                        }
                        HoverHandler { id: updHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: page.busyId === ""; onTapped: page.install(page.sel.id) }
                    }

                    // REMOVE.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 30
                        width: rmLabel.implicitWidth + 22
                        radius: Theme.radius
                        color: "transparent"
                        border.width: 1
                        border.color: rmHov.hovered ? Theme.bad : Theme.line
                        Behavior on border.color { ColorAnimation { duration: Theme.quick } }
                        Text {
                            id: rmLabel
                            anchors.centerIn: parent
                            text: "REMOVE"
                            color: rmHov.hovered ? Theme.bad : Theme.dim
                            font.family: Theme.mono
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.5
                        }
                        HoverHandler { id: rmHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: page.removePlugin(page.sel.id) }
                    }
                }
            }

            // enable + host.
            SettingSection {
                width: parent.width
                title: "Placement"

                ToggleRow {
                    width: parent.width
                    label: "Enabled"
                    // fixed, single-instance panel bound to whichever addon
                    // is selected -- not a per-item repeat, valid highlight
                    // target.
                    highlightId: "addon_enabled"
                    checked: page.sel.placement && page.sel.placement.enabled === true
                    onToggled: (v) => page.place(page.sel.id, "enabled", v ? "true" : "false")
                }

                ChoiceRow {
                    width: parent.width
                    visible: (page.sel.manifest && page.sel.manifest.hosts && page.sel.manifest.hosts.length > 1) || false
                    label: "Show as"
                    highlightId: "addon_show_as"
                    options: ((page.sel.manifest && page.sel.manifest.hosts) || []).map(function (h) {
                        return { "key": h, "label": h === "framePopout" ? "Frame popout" : h === "desktopWidget" ? "Desktop widget" : h };
                    })
                    current: (page.sel.placement && page.sel.placement.host)
                        ? page.sel.placement.host
                        : ((page.sel.manifest && page.sel.manifest.defaults && page.sel.manifest.defaults.host) || "")
                    onChosen: (key) => page.place(page.sel.id, "host", key)
                }

                Text {
                    width: parent.width
                    text: "Desktop widgets are moved, resized and hidden on the wallpaper - drag the tile, or right-click it for its menu."
                    visible: (page.sel.placement && page.sel.placement.host === "desktopWidget") || false
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            // the plugin's own settings, rendered from its schema.
            PluginSettingsForm {
                width: parent.width
                visible: schema.length > 0
                schema: (page.sel.manifest && page.sel.manifest.metadata && page.sel.manifest.metadata.settings) || []
                values: (page.sel.placement && page.sel.placement.settings) || ({})
                onChanged: (key, value) => page.setSetting(page.sel.id, key, value)
            }

            Text {
                width: parent.width
                visible: !(page.sel.manifest && page.sel.manifest.metadata && page.sel.manifest.metadata.settings && page.sel.manifest.metadata.settings.length > 0)
                text: "This add-on has no configurable settings."
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 13
            }
        }
    }
}
