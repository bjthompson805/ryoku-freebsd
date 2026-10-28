pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../Singletons"

// Agent usage popout content: provider limits, token history, and a source
// switcher. The Popout blob behind it is the surface; this panel only reports
// its implicit size.
Item {
    id: root

    property real s: 1
    property bool open: false

    // ticks while open so "resets in 47m" and "checked 8s ago" don't freeze
    // at the moment the popout was opened -- cheap, it only re-evaluates
    // text bindings. 5s (not 30s) so "checked Ns ago" reads as live enough
    // to actually reassure someone that clicking refresh did something.
    property real nowMs: Date.now()
    onOpenChanged: if (open) root.nowMs = Date.now()
    Timer {
        interval: 5000
        repeat: true
        running: root.open
        onTriggered: root.nowMs = Date.now()
    }

    anchors.fill: parent

    implicitWidth: 260 * s
    implicitHeight: body.implicitHeight + 27 * s

    function formatDuration(ms) {
        if (!(ms > 0))
            return "now";
        var minutes = Math.floor(ms / 60000);
        var hours = Math.floor(minutes / 60);
        var days = Math.floor(hours / 24);
        if (days > 0)
            return days + "d " + (hours % 24) + "h";
        if (hours > 0)
            return hours + "h " + (minutes % 60) + "m";
        return Math.max(1, minutes) + "m";
    }

    function resetLabel(resetAtMs) {
        if (!(resetAtMs > 0))
            return "";
        return "Resets in " + root.formatDuration(resetAtMs - root.nowMs);
    }

    // formatDuration's coarsest unit is minutes, too blunt for "just
    // attempted a second ago" -- the whole point of that half of the label
    // is proving something happened within the last few seconds.
    function _ago(ms) {
        var elapsed = Math.max(0, root.nowMs - ms);
        if (elapsed < 5000)
            return "just now";
        if (elapsed < 60000)
            return Math.round(elapsed / 1000) + "s ago";
        return root.formatDuration(elapsed) + " ago";
    }

    // two different questions, both worth answering separately: "how old is
    // the number on screen" (lastUpdatedMs -- only moves on a SUCCESSFUL
    // probe) vs "did it just try again" (lastCheckedMs -- moves on every
    // attempt, success or failure). A long rate-limit stretch can have
    // lastCheckedMs ticking every minute while the displayed percentage is
    // hours stale; collapsing them into one label would hide exactly that.
    function stalenessLabel() {
        var updated = AgentUsage.lastUpdatedMs > 0 ? "Updated " + root._ago(AgentUsage.lastUpdatedMs) : "";
        if (!AgentUsage.lastProbeFailed || !(AgentUsage.lastCheckedMs > 0))
            return updated;
        var checked = "retried " + root._ago(AgentUsage.lastCheckedMs);
        return updated.length > 0 ? updated + " · " + checked : "Checked " + root._ago(AgentUsage.lastCheckedMs);
    }

    function dayLabel(date) {
        var today = new Date(root.nowMs);
        var todayStr = today.getFullYear() + "-" + String(today.getMonth() + 1).padStart(2, "0") + "-" + String(today.getDate()).padStart(2, "0");
        if (date === todayStr)
            return "Today";
        var d = new Date(String(date) + "T00:00:00");
        if (isNaN(d.getTime()))
            return date;
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.hair
    }

    component SectionHeader: Text {
        width: parent ? parent.width : 0
        color: Theme.subtle
        font.family: Theme.font
        font.pixelSize: 9 * root.s
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.4 * root.s
    }

    component ProviderTab: Rectangle {
        id: providerTab
        property string provider: ""
        property string label: ""
        readonly property bool selected: AgentUsage.provider === provider

        width: (parent ? (parent.width - 12 * root.s) / 3 : 0)
        height: 24 * root.s
        color: providerTab.selected ? Qt.alpha(Theme.verm, 0.18) : Qt.alpha(Theme.bright, 0.05)
        border.width: 1
        border.color: providerTab.selected ? Theme.verm : Theme.hair

        Text {
            anchors.centerIn: parent
            text: providerTab.label
            color: providerTab.selected ? Theme.cream : Theme.dim
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: providerTab.selected ? Font.DemiBold : Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2 * root.s
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: AgentUsage.selectProvider(providerTab.provider)
        }
    }

    // one rate-limit window: eyebrow label + hero percent, a thin meter bar,
    // and a live "resets in" countdown underneath.
    component LimitRow: Column {
        id: limitRow
        property string label: ""
        property int percent: 0
        property real resetAtMs: -1
        property bool warn: false

        width: parent ? parent.width : 0
        spacing: 5 * root.s

        Item {
            width: parent.width
            height: Math.max(lLabel.implicitHeight, lValue.implicitHeight)

            Text {
                id: lLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: limitRow.label
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.Medium
            }
            Text {
                id: lValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: limitRow.percent + "%"
                color: limitRow.warn ? Theme.vermLit : Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * root.s
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }

        Rectangle {
            width: parent.width
            height: Math.max(1, 3 * root.s)
            radius: height / 2
            color: Qt.alpha(Theme.bright, 0.08)

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(1, limitRow.percent / 100))
                color: limitRow.warn ? Theme.vermLit : Theme.verm
            }
        }

        Text {
            visible: text.length > 0
            text: root.resetLabel(limitRow.resetAtMs)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9 * root.s
        }
    }

    // one day: label, bar (scaled to the week's peak), token count. today
    // rides in full tone; the rest are dimmed.
    component DayRow: Item {
        id: dayRow
        property string date: ""
        property int tokens: 0
        property real peak: 1
        property bool today: false

        width: parent ? parent.width : 0
        height: Math.max(dLabel.implicitHeight, dValue.implicitHeight) + 4 * root.s

        Text {
            id: dLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 30 * root.s
            text: root.dayLabel(dayRow.date)
            color: dayRow.today ? Theme.cream : Theme.dim
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: dayRow.today ? Font.DemiBold : Font.Medium
        }

        Rectangle {
            anchors.left: dLabel.right
            anchors.right: dValue.left
            anchors.leftMargin: 8 * root.s
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            height: Math.max(1, 3 * root.s)
            radius: height / 2
            color: Qt.alpha(Theme.bright, 0.08)

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(1, dayRow.tokens / Math.max(1, dayRow.peak)))
                color: dayRow.today ? Theme.verm : Qt.alpha(Theme.verm, 0.55)
            }
        }

        Text {
            id: dValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: AgentUsage.formatTokenCount(dayRow.tokens)
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.features: ({ "tnum": 1 })
        }
    }

    // one model: a filled backing bar sized to its share of the heaviest
    // model, name on the left, token count on the right.
    component ModelRow: Item {
        id: modelRow
        property string name: ""
        property int total: 0
        property real share: 0

        width: parent ? parent.width : 0
        height: mName.implicitHeight + 12 * root.s

        Rectangle {
            anchors.fill: parent
            radius: 6 * root.s
            color: Qt.alpha(Theme.bright, 0.05)
        }
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Math.max(0, Math.min(1, modelRow.share))
            radius: 6 * root.s
            color: Qt.alpha(Theme.verm, 0.16)
        }
        Text {
            id: mName
            anchors.left: parent.left
            anchors.leftMargin: 8 * root.s
            anchors.right: mTokens.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: modelRow.name
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            id: mTokens
            anchors.right: parent.right
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: AgentUsage.formatTokenCount(modelRow.total)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.features: ({ "tnum": 1 })
        }
    }

    Column {
        id: body
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 13 * root.s
        anchors.leftMargin: 16 * root.s
        anchors.rightMargin: 16 * root.s
        spacing: 14 * root.s

        // header: brand glyph + eyebrow + plan on the left, a manual refresh
        // button pinned top-right (the timers already poll on their own
        // cadence -- this is for "no, right now").
        Item {
            width: parent.width
            height: Math.max(headerRow.implicitHeight, refreshBtn.height)

            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.right: refreshBtn.left
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "auto_awesome"
                    fill: 1
                    color: Theme.brand
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: AgentUsage.providerName.toUpperCase()
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6 * root.s
                }
                Text {
                    visible: AgentUsage.planLabel.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: AgentUsage.planLabel
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.Medium
                }
            }

            RefreshButton {
                id: refreshBtn
                s: root.s
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spinning: AgentUsage.refreshing
                onClicked: AgentUsage.refreshNow()
            }
        }

        Row {
            width: parent.width
            spacing: 6 * root.s

            ProviderTab { provider: "claude"; label: "Claude" }
            ProviderTab { provider: "codex"; label: "Codex" }
            ProviderTab { provider: "antigravity"; label: "AGY" }
        }

        Row {
            visible: AgentUsage.provider === "antigravity"
            width: parent.width
            spacing: 6 * root.s

            Rectangle {
                id: subTabGemini
                readonly property bool selected: AgentUsage.antigravityModelGroup !== "claude_gpt"
                width: (parent.width - 6 * root.s) / 2
                height: 22 * root.s
                color: selected ? Qt.alpha(Theme.verm, 0.18) : Qt.alpha(Theme.bright, 0.04)
                border.width: 1
                border.color: selected ? Theme.verm : Theme.hair

                Text {
                    anchors.centerIn: parent
                    text: "Gemini Models"
                    color: subTabGemini.selected ? Theme.cream : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: subTabGemini.selected ? Font.DemiBold : Font.Medium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AgentUsage.selectAntigravityModelGroup("gemini")
                }
            }

            Rectangle {
                id: subTabPartner
                readonly property bool selected: AgentUsage.antigravityModelGroup === "claude_gpt"
                width: (parent.width - 6 * root.s) / 2
                height: 22 * root.s
                color: selected ? Qt.alpha(Theme.verm, 0.18) : Qt.alpha(Theme.bright, 0.04)
                border.width: 1
                border.color: selected ? Theme.verm : Theme.hair

                Text {
                    anchors.centerIn: parent
                    text: "Claude & GPT"
                    color: subTabPartner.selected ? Theme.cream : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: subTabPartner.selected ? Font.DemiBold : Font.Medium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AgentUsage.selectAntigravityModelGroup("claude_gpt")
                }
            }
        }

        Text {
            visible: text.length > 0
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: root.stalenessLabel()
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9 * root.s
        }

        // ---------- limits ----------
        Column {
            visible: AgentUsage.available
            width: parent.width
            spacing: 12 * root.s

            SectionHeader { text: "LIMITS" }
            LimitRow {
                label: AgentUsage.sessionLabel
                percent: AgentUsage.sessionPercent
                resetAtMs: AgentUsage.sessionResetsAtMs
                warn: AgentUsage.sessionPercent > 80
            }
            LimitRow {
                label: AgentUsage.weeklyLabel
                percent: AgentUsage.weeklyPercent
                resetAtMs: AgentUsage.weeklyResetsAtMs
                warn: AgentUsage.weeklyPercent > 80
            }
        }

        // shown whenever the most recent probe failed -- even with a
        // stale-but-real reading still up above (available is sticky, so it
        // alone can't gate this: a 429 five minutes ago must still be able
        // to say so here, not just the "never had any data" case).
        Text {
            visible: !AgentUsage.available || AgentUsage.lastProbeFailed
            width: parent.width
            wrapMode: Text.WordWrap
            text: AgentUsage.authHelpText
            color: (AgentUsage.available && AgentUsage.lastProbeFailed) ? Theme.vermLit : Theme.dim
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
        }

        // ---------- tokens by day ----------
        Divider { visible: usageSection.visible }
        Column {
            id: usageSection
            visible: AgentUsage.localStatsAvailable && AgentUsage.recentDays.length > 0
            width: parent.width
            spacing: 8 * root.s

            readonly property real peak: {
                var m = 1;
                for (var i = 0; i < AgentUsage.recentDays.length; i++)
                    m = Math.max(m, AgentUsage.recentDays[i].tokens || 0);
                return m;
            }

            SectionHeader { text: "TOKENS BY DAY" }
            Repeater {
                model: AgentUsage.recentDays
                delegate: DayRow {
                    required property var modelData
                    required property int index
                    width: usageSection.width
                    date: modelData.date
                    tokens: modelData.tokens
                    peak: usageSection.peak
                    today: index === AgentUsage.recentDays.length - 1
                }
            }
        }

        // ---------- tokens by model ----------
        Divider { visible: modelSection.visible }
        Column {
            id: modelSection
            visible: AgentUsage.localStatsAvailable && AgentUsage.modelUsage.length > 0
            width: parent.width
            spacing: 6 * root.s

            SectionHeader { text: "TOKENS BY MODEL" }
            Repeater {
                model: AgentUsage.modelUsage
                delegate: ModelRow {
                    required property var modelData
                    width: modelSection.width
                    name: modelData.name
                    total: modelData.total
                    share: modelData.total / Math.max(1, AgentUsage.modelUsage.length > 0 ? AgentUsage.modelUsage[0].total : 1)
                }
            }
        }
    }
}
