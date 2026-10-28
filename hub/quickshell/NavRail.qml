pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import "Singletons"

// nav rail = three bands. fixed top (pinned "top": Profile, showcase), scrolling
// middle (the grouped sections), fixed foot (pinned "bottom": Updates, so its
// badge stays visible). middle groups are drawers that animate open/closed.
// headers borrow the Profile dossier look (brand dot, mono label, hairline
// between groups). the group holding the current section is always open (brighter
// label, no chevron); expand/collapse-all in the header tucks the rest. a sliding
// selector marks the active row in the middle; pinned bands draw their own.
Rectangle {
    id: rail

    property var sections: []
    property string current: "displays"
    property alias query: search.text
    signal navigate(string section)
    signal escaped()

    function focusSearch() { search.focusInput(); }

    readonly property int navTop: 96 + 54 + 8
    readonly property int navItemH: 44
    readonly property int groupHeaderH: 40
    readonly property int pinnedGap: 18          // gap + rule between bands

    // open state, derived (no init timing): a group is open iff it holds the
    // current section or the user expanded it. default {} => only the current
    // group is open, rail starts tucked.
    property var userExpanded: ({})

    readonly property var pinnedTop: rail.sections.filter(s => s.pinned === "top")
    readonly property var pinnedBottom: rail.sections.filter(s => s.pinned === "bottom")
    readonly property var groupedSections: rail.sections.filter(s => !s.pinned)

    readonly property var groups: {
        var seen = ({});
        var out = [];
        for (var i = 0; i < rail.groupedSections.length; i++) {
            var g = rail.groupedSections[i].group;
            if (!seen[g]) { seen[g] = true; out.push(g); }
        }
        return out;
    }

    function groupOf(key) {
        for (var i = 0; i < rail.sections.length; i++)
            if (rail.sections[i].key === key)
                return rail.sections[i].group || "";
        return "";
    }
    function sectionPinned(key) {
        for (var i = 0; i < rail.sections.length; i++)
            if (rail.sections[i].key === key)
                return rail.sections[i].pinned || "";
        return "";
    }

    function isExpanded(group) {
        return group === rail.groupOf(rail.current) || rail.userExpanded[group] === true;
    }

    readonly property bool allExpanded: {
        for (var i = 0; i < rail.groups.length; i++)
            if (!rail.isExpanded(rail.groups[i]))
                return false;
        return true;
    }

    function expandAll() {
        var e = ({});
        for (var i = 0; i < rail.groups.length; i++)
            e[rail.groups[i]] = true;
        rail.userExpanded = e;
    }
    function collapseAll() { rail.userExpanded = ({}); }   // current group stays
    function toggleGroup(g) {
        if (g === rail.groupOf(rail.current))
            return;                       // current group never collapses
        var e = Object.assign({}, rail.userExpanded);
        e[g] = !e[g];
        rail.userExpanded = e;
    }
    function toggleAll() { if (rail.allExpanded) rail.collapseAll(); else rail.expandAll(); }

    // absolute y of a grouped row within the scrolling band. header per group,
    // items only while the group is open, so the selector lands on the visible
    // row.
    function itemY(key) {
        var y = 0;
        var last = null;
        for (var i = 0; i < rail.groupedSections.length; i++) {
            var s = rail.groupedSections[i];
            if (s.group !== last) {
                y += rail.groupHeaderH;
                last = s.group;
            }
            if (s.key === key)
                return y;
            if (rail.isExpanded(s.group))
                y += rail.navItemH;
        }
        return 0;
    }

    color: Theme.rail

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.line
    }

    // pinned row (top/bottom band): a NavButton with its own selection pill, since
    // the sliding selector only roams the middle band.
    component PinnedRow: Item {
        id: pin
        property var section: ({})
        width: parent ? parent.width : 0
        height: rail.navItemH

        Rectangle {
            visible: rail.current === pin.section.key
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            radius: 11
            color: Theme.keyTop
            border.width: 1
            border.color: Theme.line
        }

        NavButton {
            anchors.fill: parent
            icon: pin.section.icon
            label: pin.section.name
            badge: pin.section.key === "updates" ? (Updates.available ? Updates.behind : 0) : 0
            selected: rail.current === pin.section.key
            onClicked: rail.navigate(pin.section.key)
        }
    }

    // hairline framing the scrolling band off the pinned bands.
    component BandRule: Item {
        width: parent ? parent.width : 0
        height: rail.pinnedGap
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 24
            anchors.rightMargin: 18
            height: 1
            color: Theme.line
        }
    }

    // brand + search
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // brand masthead: RYOKU ARCH wordmark centred over a dimmed 力 backdrop
        // (soft warm glow + faint grid, echoes the Profile portrait window).
        Item {
            id: masthead
            width: parent.width
            height: 96
            clip: true

            Canvas {
                id: backdrop
                anchors.fill: parent
                property color em: Theme.ember
                property color cr: Theme.cream
                onEmChanged: requestPaint()
                onCrChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    function rgba(c, a) {
                        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")";
                    }
                    var g = ctx.createRadialGradient(width * 0.5, height * 0.44, 0, width * 0.5, height * 0.44, width * 0.6);
                    g.addColorStop(0, rgba(backdrop.em, 0.10));
                    g.addColorStop(1, rgba(backdrop.em, 0));
                    ctx.fillStyle = g;
                    ctx.fillRect(0, 0, width, height);
                    ctx.strokeStyle = rgba(backdrop.cr, 0.03);
                    ctx.lineWidth = 1;
                    var step = 22;
                    for (var x = step; x < width; x += step) {
                        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
                    }
                    for (var y = step; y < height; y += step) {
                        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                    }
                }
            }

            // dimmed 力, dropped behind the wordmark.
            Text {
                anchors.centerIn: parent
                text: "\u529b"
                color: Theme.ember
                opacity: 0.15
                font.family: Theme.font
                font.pixelSize: 84
                font.weight: Font.Black
            }

            // wordmark + subtitle, centred.
            Column {
                anchors.centerIn: parent
                spacing: 3

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Text {
                        text: "RYOKU"
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.weight: Font.Black
                        font.letterSpacing: 3
                    }
                    Text {
                        text: "ARCH"
                        color: Theme.ember
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.weight: Font.Black
                        font.letterSpacing: 3
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "system and shell settings"
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    font.letterSpacing: 0.5
                }
            }
        }

        // search row, with the expand/collapse-all toggle tucked at its right so
        // the brand owns the full row above.
        Item {
            width: parent.width
            height: 54

            Item {
                id: expandAllBtn
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: expandHover.hovered ? Theme.keyTop : "transparent"
                    border.width: expandHover.hovered ? 1 : 0
                    border.color: Theme.line
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                }

                Icon {
                    anchors.centerIn: parent
                    name: rail.allExpanded ? "collapse" : "expand"
                    size: 17
                    weight: 1.9
                    tint: expandHover.hovered ? Theme.ember : Theme.faint
                    Behavior on tint { ColorAnimation { duration: Theme.quick } }
                }

                HoverHandler { id: expandHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: rail.toggleAll() }
            }

            SearchField {
                id: search
                anchors.left: parent.left
                anchors.right: expandAllBtn.left
                anchors.leftMargin: 16
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                placeholder: "Search\u2026"
                onEscaped: rail.escaped()
            }
        }
    }

    // ── fixed top band: pinned "top" items (Profile) ────────────────────────
    Column {
        id: topBand
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: rail.navTop
        spacing: 0

        Repeater {
            model: rail.pinnedTop
            delegate: PinnedRow {
                required property var modelData
                width: topBand.width
                section: modelData
            }
        }
        BandRule { visible: rail.pinnedTop.length > 0; height: rail.pinnedTop.length > 0 ? rail.pinnedGap : 0 }
    }

    // ── fixed foot band: pinned "bottom" items (Updates) ────────────────────
    Column {
        id: bottomBand
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: 8
        spacing: 0

        BandRule { visible: rail.pinnedBottom.length > 0; height: rail.pinnedBottom.length > 0 ? rail.pinnedGap : 0 }
        Repeater {
            model: rail.pinnedBottom
            delegate: PinnedRow {
                required property var modelData
                width: bottomBand.width
                section: modelData
            }
        }
    }

    // ── scrolling middle band: the grouped drawers ──────────────────────────
    Flickable {
        id: navFlick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBand.bottom
        anchors.bottom: bottomBand.top
        clip: true
        contentHeight: listCol.height
        boundsBehavior: Flickable.StopAtBounds
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        // sliding selection indicator (hidden when a pinned item is current).
        Rectangle {
            id: selector
            x: 12
            width: navFlick.width - 24
            height: 42
            radius: 11
            y: rail.itemY(rail.current) + (rail.navItemH - height) / 2
            color: Theme.keyTop
            border.width: 1
            border.color: Theme.line
            opacity: rail.query.length > 0 ? 0.4 : (rail.sectionPinned(rail.current) !== "" ? 0 : 1)
            Behavior on y { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }
            Behavior on opacity { NumberAnimation { duration: Theme.quick } }
        }

        Column {
            id: listCol
            width: navFlick.width
            spacing: 0

            Repeater {
                model: rail.groupedSections

                delegate: Column {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property bool firstOfGroup: row.index === 0 || rail.groupedSections[row.index - 1].group !== row.modelData.group
                    readonly property bool groupOpen: rail.isExpanded(row.modelData.group)
                    readonly property bool currentGroup: row.modelData.group === rail.groupOf(rail.current)
                    width: parent.width

                    // group header: rule between groups, brand accent dot, mono
                    // label. current group brightens and drops its chevron (never
                    // collapses).
                    Item {
                        width: parent.width
                        height: row.firstOfGroup ? rail.groupHeaderH : 0
                        visible: row.firstOfGroup

                        Rectangle {
                            visible: row.index > 0
                            anchors.top: parent.top
                            anchors.topMargin: 9
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 24
                            anchors.rightMargin: 18
                            height: 1
                            color: Theme.line
                        }

                        Row {
                            id: hdrRow
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 9
                            spacing: 9

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: 1.5
                                color: Theme.brand
                            }

                            Text {
                                id: groupLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.group
                                color: row.currentGroup ? Theme.subtle : (hdrHover.hovered ? Theme.cream : Theme.faint)
                                font.family: Theme.mono
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 2.2
                                font.capitalization: Font.AllUppercase
                                Behavior on color { ColorAnimation { duration: Theme.quick } }
                            }

                            Icon {
                                visible: !row.currentGroup
                                anchors.verticalCenter: parent.verticalCenter
                                name: "chevron"
                                size: 12
                                weight: 2
                                tint: hdrHover.hovered ? Theme.cream : Theme.faint
                                rotation: row.groupOpen ? 0 : -90
                                Behavior on rotation { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }
                                Behavior on tint { ColorAnimation { duration: Theme.quick } }
                            }
                        }

                        HoverHandler { id: hdrHover; enabled: !row.currentGroup; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !row.currentGroup; onTapped: rail.toggleGroup(row.modelData.group) }
                    }

                    // the row itself, height-animated as the drawer opens/closes.
                    Item {
                        width: parent.width
                        height: row.groupOpen ? rail.navItemH : 0
                        visible: height > 0.5
                        clip: true
                        Behavior on height { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }

                        NavButton {
                            width: parent.width
                            height: rail.navItemH
                            icon: row.modelData.icon
                            label: row.modelData.name
                            selected: rail.current === row.modelData.key
                            onClicked: rail.navigate(row.modelData.key)
                        }
                    }
                }
            }
        }
    }

    Text {
        id: footer
        anchors.left: parent.left
        anchors.leftMargin: 26
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        text: "\u529b  ryoku desktop"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 11
        font.weight: Font.Medium
    }
}
