pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."
import "../Singletons"

// display popout content: laptop panel backlight (brightnessctl), screen
// vibrance (a Hyprland screen_shader, via Singletons/Vibrance.qml), and per
// external monitor brightness (ddcutil), as HFader rows reusing Devices.qml
// (backlight/ddc) and Vibrance.qml (vibrance, shared with the hub's Comfort
// page). split out of the mixer's old Display section into its own module
// next to sound, since it isn't audio -- named "display" rather than
// "brightness" since it also covers vibrance and any future screen knob.
// panel brightness re-reads on popout open (hypridle can change it while
// closed); ddc monitor brightness reads once per monitor on load. writes
// debounce so a drag never floods i2c/sysfs. plain transparent Item -- the
// frame blob behind it IS the surface; Popout reads the reported implicit size
// to melt open to fit.
Item {
    id: root

    property real s: 1
    // popout open: re-syncs the panel readout each time it opens, since
    // hypridle can change it (dim-on-timeout, restore-on-resume) while closed.
    property bool open: false

    anchors.fill: parent

    implicitWidth: 300 * s
    implicitHeight: body.implicitHeight + 27 * s

    property real pendingVibrance: -1
    property real pendingPanel: -1

    onOpenChanged: if (root.open) { Devices.probePanelBrightness(); Vibrance.refresh(); }
    Component.onCompleted: { Devices.probePanelBrightness(); Vibrance.refresh(); }

    Timer {
        id: vibDebounce
        interval: 160
        onTriggered: if (root.pendingVibrance >= 0) {
            Vibrance.setVibrance(root.pendingVibrance);
            root.pendingVibrance = -1;
        }
    }

    Timer {
        id: panelCommit
        interval: 160
        onTriggered: if (root.pendingPanel >= 0) {
            Devices.setPanelBrightness(root.pendingPanel);
            root.pendingPanel = -1;
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
        spacing: 11 * root.s

        Row {
            spacing: 8 * root.s
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "light_mode"
                fill: 1
                color: Theme.brand
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "DISPLAY"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }

        Column {
            width: parent.width
            spacing: 6 * root.s

            HFader {
                width: parent.width
                s: root.s
                icon: "sun"
                lit: panelHover.hovered
                value: Devices.panelBrightness < 0 ? 0 : Devices.panelBrightness / 100
                valueLabel: Devices.panelBrightness < 0 ? "" : Devices.panelBrightness + "%"
                onMoved: (v) => { Devices.panelBrightness = Math.max(5, Math.min(100, Math.round(v * 100))); }
                onCommitted: (v) => {
                    root.pendingPanel = Math.max(5, Math.min(100, Math.round(v * 100)));
                    panelCommit.restart();
                }

                HoverHandler { id: panelHover }
            }

            HFader {
                width: parent.width
                s: root.s
                icon: "contrast"
                lit: vibHover.hovered
                value: Vibrance.vibrance / 100
                valueLabel: Vibrance.vibrance + "%"
                onMoved: (v) => Vibrance.vibrance = Math.round(v * 100)
                onCommitted: (v) => { root.pendingVibrance = v * 100; vibDebounce.restart(); }

                HoverHandler { id: vibHover }
            }

            Repeater {
                model: Devices.ddcMonitors

                HFader {
                    id: brFader
                    required property var modelData

                    property int pct: 75
                    property real pendingPct: -1

                    width: parent.width
                    s: root.s
                    icon: "sun"
                    lit: brHover.hovered
                    value: pct / 100
                    valueLabel: pct + "%"
                    onMoved: (v) => pct = Math.max(5, Math.min(100, Math.round(v * 100)))
                    onCommitted: (v) => {
                        pendingPct = Math.max(5, Math.min(100, Math.round(v * 100)));
                        brCommit.restart();
                    }

                    HoverHandler { id: brHover }

                    Timer {
                        id: brCommit
                        interval: 160
                        onTriggered: if (brFader.pendingPct >= 0) {
                            Devices.setBrightness(brFader.modelData.bus, brFader.pendingPct);
                            brFader.pendingPct = -1;
                        }
                    }

                    Process {
                        command: ["timeout", "3", "ddcutil", "getvcp", "10", "--bus", brFader.modelData.bus, "--brief"]
                        running: true
                        stdout: StdioCollector {
                            onStreamFinished: {
                                var v = Devices.parseBrightness(this.text);
                                if (v >= 0)
                                    brFader.pct = v;
                            }
                        }
                    }
                }
            }
        }
    }
}
