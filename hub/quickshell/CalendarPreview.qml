pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

/**
 * A live, plain-QML preview of the desktop calendar widget for the Desktop
 * Widgets section, so the chosen face, accent and week start show at a glance
 * without leaning over the hub to the wallpaper. It mirrors the live faces in
 * ryoku/shell/quickshell/widgets/calendar; the accent follows your real wallust
 * palette (Wallust singleton), the rest is bright ink as on the wallpaper.
 * Sample notes are illustrative; the running widget reads the shared event store.
 */
Item {
    id: preview

    property string design: "month"
    property string accentChoice: "wallust"
    property string weekStart: "mon"

    readonly property color ink: "#f5f3ff"
    readonly property color inkSoft: "#d2d7ef"
    readonly property color inkDim: "#9aa3c8"
    readonly property color faint: Qt.rgba(0.96, 0.95, 1, 0.42)
    readonly property color hair: Qt.rgba(0.96, 0.95, 1, 0.13)
    readonly property color brand: "#F25623"
    readonly property color accent: preview.accentChoice === "brand" ? preview.brand
        : (preview.accentChoice === "mono" ? preview.ink : Wallust.accent)

    property var now: new Date()
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: preview.now = new Date() }

    readonly property int ws: preview.weekStart === "sun" ? 0 : 1
    readonly property var wdMin: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    readonly property var wdShort: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var wdLong: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    readonly property int year: now.getFullYear()
    readonly property int month: now.getMonth()
    readonly property int dom: now.getDate()
    // sample days carrying a note dot, so the event marker is visible in the hub.
    readonly property var marked: [preview.dom, Math.min(preview.dom + 3, 28), Math.max(1, preview.dom - 5)]

    function pad2(n) { return (n < 10 ? "0" : "") + n; }
    function offset(y, m) { return (new Date(y, m, 1).getDay() - preview.ws + 7) % 7; }
    function dim(y, m) { return new Date(y, m + 1, 0).getDate(); }
    function order() {
        var out = [];
        for (var i = 0; i < 7; i++) out.push((preview.ws + i) % 7);
        return out;
    }
    function isWeekend(jw) { return jw === 0 || jw === 6; }
    function hasEv(d) { return preview.marked.indexOf(d) >= 0; }
    // sample heat level (0..4) so the heatmap preview shows a spread of intensity
    // without real events. deterministic from the day number.
    function heatLevel(d) { return d <= 0 ? 0 : (d * 7 + 3) % 5; }
    function tileColor(level) {
        if (level <= 0) return Qt.rgba(0.96, 0.95, 1, 0.05);
        if (preview.accentChoice === "wallust") return Wallust.colorAt(0.15 + (level - 1) / 3 * 0.8);
        return Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.2 + (level - 1) / 3 * 0.65);
    }

    Loader {
        anchors.centerIn: parent
        sourceComponent: preview.design === "minimal" ? minimalC
            : (preview.design === "agenda" ? agendaC : (preview.design === "week" ? weekC : (preview.design === "heat" ? heatC : monthC)))
    }

    component EvRow: Row {
        property string t: ""
        property string body: ""
        spacing: 8
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 3; height: 12; radius: Theme.radius; color: preview.accent }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 34; text: parent.t; color: preview.inkDim; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10 }
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.body; color: preview.ink; font.family: "Inter"; font.pixelSize: 11 }
    }

    // --- month -------------------------------------------------------------
    Component {
        id: monthC
        Column {
            id: mCol
            readonly property int off: preview.offset(preview.year, preview.month)
            readonly property int len: preview.dim(preview.year, preview.month)
            readonly property int rows: Math.ceil((off + len) / 7)
            readonly property real colW: 30
            spacing: 8

            Item {
                width: mCol.colW * 7
                height: 24
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u529b"; color: preview.brand; font.family: "Noto Sans CJK JP"; font.pixelSize: 15; font.weight: Font.Medium }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: preview.months[preview.month] + " " + preview.year; color: preview.ink; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    Text { text: "\u2039"; color: preview.inkDim; font.family: "Inter"; font.pixelSize: 16 }
                    Text { text: "\u203a"; color: preview.inkDim; font.family: "Inter"; font.pixelSize: 16; leftPadding: 12 }
                }
            }

            Rectangle { width: mCol.colW * 7; height: 1; color: preview.hair }

            Row {
                Repeater {
                    model: preview.order()
                    Item {
                        id: wdh
                        required property int modelData
                        width: 30; height: 16
                        Text { anchors.centerIn: parent; text: preview.wdMin[wdh.modelData]; color: preview.isWeekend(wdh.modelData) ? preview.faint : preview.inkDim; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium }
                    }
                }
            }

            Grid {
                columns: 7
                rowSpacing: 2
                Repeater {
                    model: mCol.rows * 7
                    Item {
                        id: mcell
                        required property int index
                        readonly property int jw: preview.order()[index % 7]
                        readonly property int dayNum: index - mCol.off + 1
                        readonly property bool inMonth: dayNum >= 1 && dayNum <= mCol.len
                        readonly property bool current: inMonth && dayNum === preview.dom
                        width: 30; height: 28
                        Rectangle {
                            anchors.centerIn: parent; width: 24; height: 24; radius: Theme.radius
                            visible: mcell.current
                            color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.16)
                            border.width: 1; border.color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.55)
                        }
                        Text {
                            anchors.centerIn: parent
                            text: mcell.inMonth ? mcell.dayNum : ""
                            color: mcell.current ? preview.accent : (preview.isWeekend(mcell.jw) ? preview.inkDim : preview.ink)
                            font.family: "Inter"; font.pixelSize: 11; font.weight: mcell.current ? Font.DemiBold : Font.Normal
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.verticalCenter; anchors.topMargin: 9
                            width: 3; height: 3; radius: 1.5
                            visible: mcell.inMonth && preview.hasEv(mcell.dayNum)
                            color: mcell.current ? preview.accent : Qt.rgba(0.96, 0.95, 1, 0.5)
                        }
                    }
                }
            }
        }
    }

    // --- minimal -----------------------------------------------------------
    Component {
        id: minimalC
        Column {
            spacing: 12
            Row {
                spacing: 14
                Text { anchors.verticalCenter: parent.verticalCenter; text: preview.dom; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 72; font.weight: Font.Bold }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    Text { text: preview.wdLong[preview.now.getDay()]; color: preview.accent; font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold }
                    Text { text: preview.months[preview.month] + " " + preview.year; color: preview.inkDim; font.family: "Inter"; font.pixelSize: 15; font.weight: Font.Medium }
                }
            }
            Column {
                spacing: 6
                Text { text: "UP NEXT"; color: preview.faint; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 2 }
                EvRow { t: "09:30"; body: "Standup" }
                EvRow { t: "all"; body: "Pay rent" }
            }
        }
    }

    // --- agenda ------------------------------------------------------------
    Component {
        id: agendaC
        Column {
            spacing: 10
            Row {
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "\u529b"; color: preview.brand; font.family: "Noto Sans CJK JP"; font.pixelSize: 15; font.weight: Font.Medium }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "AGENDA"; color: preview.inkDim; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 2 }
            }
            Repeater {
                model: 3
                Row {
                    id: arow
                    required property int index
                    readonly property date d: new Date(preview.year, preview.month, preview.dom + index)
                    readonly property bool current: index === 0
                    spacing: 14
                    Rectangle {
                        width: 42; height: 44; radius: Theme.radius
                        color: arow.current ? Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.16) : Qt.rgba(0.96, 0.95, 1, 0.04)
                        border.width: 1; border.color: arow.current ? Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.5) : preview.hair
                        Column {
                            anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: arow.d.getDate(); color: arow.current ? preview.accent : preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18; font.weight: Font.Bold }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: preview.wdShort[arow.d.getDay()].toUpperCase(); color: arow.current ? preview.accent : preview.inkDim; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 4; width: 200
                        EvRow { visible: arow.current; t: "09:30"; body: "Standup" }
                        EvRow { visible: arow.current; t: "14:00"; body: "Review" }
                        Text { visible: !arow.current; text: "\u2014"; color: preview.faint; font.family: "Inter"; font.pixelSize: 11 }
                    }
                }
            }
        }
    }

    // --- week --------------------------------------------------------------
    Component {
        id: weekC
        Column {
            id: wCol
            readonly property int back: (preview.now.getDay() - preview.ws + 7) % 7
            spacing: 10
            Row {
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "\u529b"; color: preview.brand; font.family: "Noto Sans CJK JP"; font.pixelSize: 14; font.weight: Font.Medium }
                Text { anchors.verticalCenter: parent.verticalCenter; text: preview.months[preview.month] + " " + preview.year; color: preview.ink; font.family: "Inter"; font.pixelSize: 12; font.weight: Font.DemiBold }
            }
            Row {
                Repeater {
                    model: 7
                    Item {
                        id: wcell
                        required property int index
                        readonly property date d: new Date(preview.year, preview.month, preview.dom - wCol.back + index)
                        readonly property bool current: d.getDate() === preview.dom && d.getMonth() === preview.month
                        width: 40; height: 58
                        Column {
                            anchors.centerIn: parent; spacing: 5
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: preview.wdMin[wcell.d.getDay()]; color: preview.isWeekend(wcell.d.getDay()) ? preview.faint : preview.inkDim; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium }
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter; width: 28; height: 28
                                Rectangle {
                                    anchors.fill: parent; radius: Theme.radius; visible: wcell.current
                                    color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.16)
                                    border.width: 1; border.color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.55)
                                }
                                Text { anchors.centerIn: parent; text: wcell.d.getDate(); color: wcell.current ? preview.accent : (preview.isWeekend(wcell.d.getDay()) ? preview.inkDim : preview.ink); font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; font.weight: wcell.current ? Font.Bold : Font.Medium }
                            }
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 3; height: 3; radius: 1.5; visible: preview.hasEv(wcell.d.getDate()); color: wcell.current ? preview.accent : Qt.rgba(0.96, 0.95, 1, 0.5) }
                        }
                    }
                }
            }
        }
    }

    // --- heat --------------------------------------------------------------
    Component {
        id: heatC
        Column {
            id: hCol
            readonly property int off: preview.offset(preview.year, preview.month)
            readonly property int len: preview.dim(preview.year, preview.month)
            readonly property int rows: Math.ceil((off + len) / 7)
            readonly property real colW: 30
            spacing: 8

            Item {
                width: hCol.colW * 7
                height: 22
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u529b"; color: preview.brand; font.family: "Noto Sans CJK JP"; font.pixelSize: 15; font.weight: Font.Medium }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: preview.months[preview.month] + " " + preview.year; color: preview.ink; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
                }
            }

            Row {
                Repeater {
                    model: preview.order()
                    Item {
                        id: hwd
                        required property int modelData
                        width: 30; height: 16
                        Text { anchors.centerIn: parent; text: preview.wdMin[hwd.modelData]; color: preview.isWeekend(hwd.modelData) ? preview.faint : preview.inkDim; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium }
                    }
                }
            }

            Grid {
                columns: 7
                rowSpacing: 3
                columnSpacing: 3
                Repeater {
                    model: hCol.rows * 7
                    Item {
                        id: hcell
                        required property int index
                        readonly property int dayNum: index - hCol.off + 1
                        readonly property bool inMonth: dayNum >= 1 && dayNum <= hCol.len
                        readonly property bool current: inMonth && dayNum === preview.dom
                        readonly property int level: inMonth ? preview.heatLevel(dayNum) : 0
                        width: 30; height: 30
                        Rectangle {
                            anchors.centerIn: parent; width: 26; height: 26; radius: Theme.radius
                            visible: hcell.inMonth
                            color: hcell.level > 0 ? preview.tileColor(hcell.level) : Qt.rgba(0.96, 0.95, 1, 0.04)
                            border.width: hcell.current ? 1 : 0
                            border.color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.9)
                            Text {
                                anchors.centerIn: parent
                                text: hcell.dayNum
                                color: hcell.level >= 3 ? "#13131b" : (hcell.current ? preview.accent : (hcell.level > 0 ? preview.ink : preview.inkDim))
                                font.family: "Inter"; font.pixelSize: 11; font.weight: (hcell.current || hcell.level >= 3) ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                }
            }

            Row {
                spacing: 4
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Less"; color: preview.faint; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium }
                Repeater {
                    model: 5
                    Rectangle {
                        id: hleg
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11; height: 11; radius: Theme.radius
                        color: hleg.index > 0 ? preview.tileColor(hleg.index) : Qt.rgba(0.96, 0.95, 1, 0.06)
                        border.width: hleg.index === 0 ? 1 : 0
                        border.color: Qt.rgba(0.96, 0.95, 1, 0.2)
                    }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "More"; color: preview.faint; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium }
            }
        }
    }
}
