pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Singletons"

// The Profile dossier, shared by every root that shows a Profile section (the
// Hub's Profile page, beside ProfileCard; the shell pill's sidebar Profile
// tab, as a `showMasthead: false` subclass -- see pill/ProfileDossier.qml).
// the field sheet beside the specimen card, drawn in the same carbon
// vocabulary as the card itself, never as a generic stat dashboard. A
// timestamp masthead (optional -- some hosts already carry a clock
// elsewhere), a vitals strip read off hairline-split columns, runtime spec
// lines (label, rule, then value: the card's type-line motif), a package
// wave, the look, and the wallust palette as one spectrum. Extended values
// come from SysInfo; the clock ticks locally. No addresses are shown, so the
// shot is safe to post.
Item {
    id: panel

    // false hides the LOCAL TIME masthead + the divider under it (Column
    // exclusion collapses their space automatically) -- overridden by
    // pill/ProfileDossier.qml, whose host already has a clock elsewhere.
    property bool showMasthead: true

    // hairline tokens: not every root's Theme names these the same way (the
    // Hub's has `line`/`surfaceLo`; the shell pill's has `hair`/`tileBg`
    // instead) -- overridden by pill/ProfileDossier.qml, default to the Hub's
    // own Theme for its unmodified usage.
    property color lineColor: Theme.line
    property color lineSoftColor: Theme.lineSoft
    property color surfaceLoColor: Theme.surfaceLo

    // false (the Hub default): the footer docks to this Item's own bottom, so
    // the host must give the whole panel a fixed/anchored height (ProfilePage
    // matches it to the specimen card's). true: the footer instead flows as
    // the last row of the content column, and the panel reports its own
    // natural height via implicitHeight -- for a host that stacks the panel
    // in a Flickable instead of pairing it beside a fixed-height card (the
    // sidebar's Profile tab) -- overridden by pill/ProfileDossier.qml.
    property bool footerFlows: false

    implicitHeight: panel.footerFlows ? col.height : 0

    property var now: new Date()
    Timer {
        interval: 1000
        running: panel.showMasthead
        repeat: true
        triggeredOnStart: true
        onTriggered: panel.now = new Date()
    }
    readonly property string clockTime: Config.clock24h ? Qt.formatDateTime(panel.now, "HH:mm") : Qt.formatDateTime(panel.now, "h:mm AP")
    readonly property string clockDate: Qt.formatDate(panel.now, "ddd · dd MMM yyyy").toUpperCase()
    readonly property var palette: SysInfo.sysPalette.length > 0 ? SysInfo.sysPalette.split(",") : []

    // ── Reusable bits, all in the card's mono/hairline idiom ─────────────────
    component MicroLabel: Row {
        id: ml
        property string label: ""
        spacing: 8
        Rectangle {
            width: 5
            height: 5
            radius: Theme.radius
            color: Theme.brand
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: ml.label
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 2.4
            font.capitalization: Font.AllUppercase
        }
    }

    // A spec line: label, a hairline that eats the gap, then the value, the
    // same shape as the card's SYSTEM type line, reused.
    component SpecRow: Row {
        id: sr
        property string k: ""
        property string v: ""
        width: parent ? parent.width : 0
        height: 31
        spacing: 12

        Text {
            id: srk
            anchors.verticalCenter: parent.verticalCenter
            text: sr.k
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1.6
            font.capitalization: Font.AllUppercase
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(8, sr.width - srk.implicitWidth - srv.implicitWidth - 2 * sr.spacing)
            height: 1
            color: panel.lineSoftColor
        }
        Text {
            id: srv
            anchors.verticalCenter: parent.verticalCenter
            text: sr.v
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    // A vitals column: big tabular figure over a mono micro-label.
    component Stat: Column {
        id: st
        property string value: "-"
        property string label: ""
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: st.value
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 21
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: st.label
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 8
            font.letterSpacing: 1.4
            font.capitalization: Font.AllUppercase
        }
    }

    component VDiv: Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: 30
        Layout.alignment: Qt.AlignVCenter
        color: panel.lineColor
    }

    // the edition footer, aligned with the specimen's own edition strip. two
    // placements below share this: docked to the panel's bottom (the Hub
    // default, paired with a fixed-height card) or flowing as the content
    // column's last row (`footerFlows`, the sidebar's stacked/scrollable use).
    component FooterBlock: Column {
        spacing: 9
        Rectangle { width: parent.width; height: 1; color: panel.lineColor }
        Item {
            width: parent.width
            height: 12
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "SYSTEM DOSSIER · 力"
                color: Theme.faint
                font.family: Theme.mono
                font.pixelSize: 9
                font.weight: Font.DemiBold
                font.letterSpacing: 1.8
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "RYOKU · " + SysInfo.codename
                color: Theme.cream
                font.family: Theme.mono
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1.8
            }
        }
    }

    // ── Content ─────────────────────────────────────────────────────────────
    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 24

        // Masthead: a local-time stamp, label + figure left, date + uptime right.
        // hidden (and its space collapsed by the Column above) when the host
        // already carries a clock elsewhere.
        Item {
            width: parent.width
            height: 60
            visible: panel.showMasthead

            Column {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                spacing: 0
                Text {
                    text: "LOCAL TIME"
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 2.2
                }
                Text {
                    text: panel.clockTime
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 42
                    font.weight: Font.Black
                    font.letterSpacing: -0.5
                    font.features: { "tnum": 1 }
                }
            }
            Column {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                spacing: 5
                Text {
                    anchors.right: parent.right
                    text: panel.clockDate
                    color: Theme.subtle
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.letterSpacing: 1.4
                }
                Text {
                    anchors.right: parent.right
                    text: "UPTIME · " + SysInfo.sysUptime
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.letterSpacing: 1.4
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: panel.lineColor; visible: panel.showMasthead }

        // Vitals: figures split by hairlines, no boxes.
        Column {
            width: parent.width
            spacing: 12
            MicroLabel { label: "Vitals" }
            RowLayout {
                width: parent.width
                spacing: 0
                Stat { Layout.fillWidth: true; value: SysInfo.sysLoad; label: "Load" }
                VDiv {}
                Stat { Layout.fillWidth: true; value: SysInfo.sysTemp; label: "CPU" }
                VDiv {}
                Stat { Layout.fillWidth: true; value: SysInfo.sysProcs; label: "Proc" }
                VDiv {}
                Stat { Layout.fillWidth: true; value: SysInfo.sysBattery; label: "Batt" }
                VDiv {}
                Stat { Layout.fillWidth: true; value: SysInfo.sysMonitors; label: "Disp" }
            }
        }

        // Runtime spec lines.
        Column {
            width: parent.width
            spacing: 2
            MicroLabel { label: "Runtime" }
            Item { width: 1; height: 6 }
            SpecRow { k: "Compositor"; v: "Hyprland v" + SysInfo.sysHyprVer }
            SpecRow { k: "Architecture"; v: SysInfo.sysArch }
            SpecRow { k: "Swap"; v: SysInfo.sysSwap }
        }

        // Packages: a Ryoku wave filled to the share you installed yourself.
        Column {
            width: parent.width
            spacing: 12
            MicroLabel { label: "Packages" }
            WaveMeter {
                width: parent.width
                s: 1.5
                frac: {
                    const total = Math.max(1, parseInt(SysInfo.sysPackages) || 1);
                    const mine = (parseInt(SysInfo.sysPkgExplicit) || 0) + (parseInt(SysInfo.sysPkgAur) || 0);
                    return mine / total;
                }
            }
            Text {
                text: SysInfo.sysPkgExplicit + " explicit   ·   " + SysInfo.sysPkgAur + " aur   ·   " + SysInfo.sysPackages + " total"
                color: Theme.subtle
                font.family: Theme.mono
                font.pixelSize: 10
                font.letterSpacing: 1
                font.capitalization: Font.AllUppercase
            }
        }

        // Look spec lines.
        Column {
            width: parent.width
            spacing: 2
            MicroLabel { label: "Look" }
            Item { width: 1; height: 6 }
            SpecRow { k: "Cursor"; v: SysInfo.sysCursor }
            SpecRow { k: "UI Font"; v: Theme.font }
            SpecRow { k: "Mono"; v: Theme.mono }
        }

        // wallust palette as a single contiguous spectrum.
        Column {
            width: parent.width
            spacing: 12
            MicroLabel { label: "Palette" }
            Rectangle {
                width: parent.width
                height: 22
                radius: Theme.radius
                clip: true
                color: panel.surfaceLoColor
                border.width: 1
                border.color: panel.lineColor
                Row {
                    anchors.fill: parent
                    anchors.margins: 1
                    Repeater {
                        model: panel.palette
                        Rectangle {
                            required property string modelData
                            width: (parent.width) / Math.max(1, panel.palette.length)
                            height: parent.height
                            color: modelData
                        }
                    }
                }
            }
        }

        // flowing placement: the panel's natural last row, under `footerFlows`.
        FooterBlock { width: parent.width; visible: panel.footerFlows }
    }

    // docked placement: pinned to the panel's own bottom (the Hub default,
    // paired with a fixed-height card).
    FooterBlock {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !panel.footerFlows
    }
}
