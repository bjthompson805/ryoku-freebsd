pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "Singletons"

// status cluster in the reference iconography: Material Symbols for volume,
// network, bluetooth, battery and notifications, tinted like caelestia's
// m3secondary rail. `vertical` stacks the glyphs.
//
// each glyph opens its own popout on CLICK, positioned at the glyph: the popout
// grows from the bar edge at the icon (down from a top bar, up from a bottom
// bar), like the reference. requestPopout carries the popout name + the icon's
// along-axis centre in window coords (the popout's own coordinate space). the
// bell opens the inbox notification-centre popout at the bell, like the glyphs.
Grid {
    id: status

    property real s: 1
    property bool vertical: false

    signal requestPopout(string name, real center)

    // open a named popout anchored at an icon: report the icon's centre along
    // the bar axis (x on a top/bottom bar, y on a side bar) in window coords.
    function open(name, item) {
        const p = item.mapToItem(null, item.width / 2, item.height / 2);
        requestPopout(name, vertical ? p.y : p.x);
    }

    // the bell's along-axis centre in window coords, kept live so the toast
    // popout grows from the bell without a click (Notifs.popups drives it).
    // recomputes when the cluster's layout shifts (icon widths, battery text,
    // scale) or a popup arrives; the bell is stationary otherwise.
    readonly property real bellCenter: {
        void status.width; void status.height; void status.s; void Notifs.popups;
        const p = bellIcon.mapToItem(null, bellIcon.width / 2, bellIcon.height / 2);
        return vertical ? p.y : p.x;
    }

    readonly property real glyphPx: 14 * s

    columns: vertical ? 1 : 9
    columnSpacing: 9 * s
    rowSpacing: 7 * s
    verticalItemAlignment: Grid.AlignVCenter
    horizontalItemAlignment: Grid.AlignHCenter

    // volume: click opens the mixer.
    Item {
        id: volIcon
        width: status.glyphPx + 4 * status.s
        height: status.glyphPx + 4 * status.s

        readonly property var sink: Audio.sink
        readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
        readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

        MaterialIcon {
            anchors.centerIn: parent
            text: volIcon.muted ? "volume_off"
                : (volIcon.vol > 0.5 ? "volume_up"
                : (volIcon.vol > 0 ? "volume_down" : "volume_mute"))
            fill: 1
            color: volIcon.muted ? Theme.faint : Theme.subtle
            font.pixelSize: status.glyphPx
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: status.open("mixer", volIcon)
            onWheel: (w) => {
                if (!volIcon.sink || !volIcon.sink.audio)
                    return;
                volIcon.sink.audio.muted = false;
                volIcon.sink.audio.volume = Math.max(0, Math.min(1, volIcon.vol + (w.angleDelta.y > 0 ? 1 : -1) * 0.03));
            }
        }
    }

    // display: click opens the display popout (panel backlight, vibrance,
    // any external ddc monitor). split out of the mixer since it isn't audio;
    // named "display" rather than "brightness" since it covers more than just
    // the backlight level.
    Item {
        id: dispIcon
        visible: Config.barShowDisplay
        width: status.glyphPx + 4 * status.s
        height: status.glyphPx + 4 * status.s

        GlyphIcon {
            anchors.centerIn: parent
            // "brightness_high"/"brightness_low" read as a vague badge/rosette
            // at this size; a sun with short vs. long rays reads as low/high
            // brightness without the "dark mode" connotation a moon carries.
            width: status.glyphPx
            height: status.glyphPx
            name: Devices.panelBrightness > 50 ? "sun-bright" : "sun-dim"
            color: Theme.subtle
            stroke: 1.7
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: status.open("display", dispIcon)
            onWheel: (w) => {
                const cur = Devices.panelBrightness < 0 ? 50 : Devices.panelBrightness;
                Devices.setPanelBrightness(cur + (w.angleDelta.y > 0 ? 3 : -3));
            }
        }
    }

    // network: click opens the network popout.
    Item {
        id: netIcon
        width: status.glyphPx + 4 * status.s
        height: status.glyphPx + 4 * status.s

        MaterialIcon {
            anchors.centerIn: parent
            text: {
                if (Network.kind === "ethernet")
                    return "lan";
                if (!Network.wifiRadio)
                    return "wifi_off";
                if (Network.kind !== "wifi")
                    return "signal_wifi_off";
                return Network.level > 0.8 ? "signal_wifi_4_bar"
                    : (Network.level > 0.55 ? "network_wifi_3_bar"
                    : (Network.level > 0.3 ? "network_wifi_2_bar" : "network_wifi_1_bar"));
            }
            fill: 1
            color: Network.kind === "" ? Theme.faint : Theme.subtle
            font.pixelSize: status.glyphPx
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: status.open("network", netIcon)
        }
    }

    // bluetooth: click opens the bluetooth popout.
    Item {
        id: btIcon
        visible: Bluetooth.defaultAdapter !== null
        width: status.glyphPx + 4 * status.s
        height: status.glyphPx + 4 * status.s

        readonly property var adapter: Bluetooth.defaultAdapter
        readonly property bool anyConnected: Bluetooth.devices.values.some(function (d) { return d && d.connected; })

        MaterialIcon {
            anchors.centerIn: parent
            text: !btIcon.adapter || !btIcon.adapter.enabled ? "bluetooth_disabled"
                : (btIcon.anyConnected ? "bluetooth_connected" : "bluetooth")
            fill: 1
            color: btIcon.adapter && btIcon.adapter.enabled ? Theme.subtle : Theme.faint
            font.pixelSize: status.glyphPx
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: status.open("bluetooth", btIcon)
        }
    }

    // battery: click opens the battery popout.
    Item {
        id: battIcon
        visible: Battery.present
        width: battRow.implicitWidth
        height: battRow.implicitHeight

        Row {
            id: battRow
            spacing: 3 * status.s

            // battery glyph + power-mode badge: the level bars stay the
            // battery truth, a small corner glyph rides on top while off
            // the charger and running a non-balanced profile (plus for
            // Saver, bolt for Performance -- a speedometer doesn't read at
            // badge size).
            Item {
                id: battGlyph
                anchors.verticalCenter: parent.verticalCenter
                width: battLevel.implicitWidth
                height: battLevel.implicitHeight

                readonly property bool badged: !Battery.charging
                    && (PowerProfiles.profile === PowerProfile.PowerSaver || PowerProfiles.profile === PowerProfile.Performance)
                readonly property bool saver: PowerProfiles.profile === PowerProfile.PowerSaver

                MaterialIcon {
                    id: battLevel
                    text: {
                        if (Battery.charging)
                            return "battery_charging_full";
                        const f = Battery.frac;
                        if (f > 0.95) return "battery_full";
                        if (f > 0.8) return "battery_6_bar";
                        if (f > 0.65) return "battery_5_bar";
                        if (f > 0.5) return "battery_4_bar";
                        if (f > 0.35) return "battery_3_bar";
                        if (f > 0.2) return "battery_2_bar";
                        return "battery_1_bar";
                    }
                    fill: 1
                    color: Battery.low ? Theme.vermLit : (Battery.charging ? Theme.flameGlow : Theme.subtle)
                    font.pixelSize: status.glyphPx + 1 * status.s
                }

                Rectangle {
                    visible: battGlyph.badged
                    width: 10 * status.s
                    height: 10 * status.s
                    radius: width / 2
                    color: Theme.cardBot
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -2 * status.s
                    anchors.bottomMargin: -2 * status.s

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: battGlyph.saver ? "add" : "bolt"
                        fill: 1
                        color: battGlyph.saver ? Theme.subtle : Theme.flameGlow
                        font.pixelSize: 9 * status.s
                    }
                }
            }
            Text {
                visible: !status.vertical
                anchors.verticalCenter: parent.verticalCenter
                text: Battery.pct + "%"
                color: Battery.low ? Theme.vermLit : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 9.5 * status.s
                font.weight: Font.Medium
                font.features: ({ "tnum": 1 })
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: status.open("battery", battIcon)
        }
    }

    // notifications: the bell, filled with an accent tint while something waits.
    // opens the inbox notification-centre popout at the bell.
    Item {
        id: bellIcon
        width: status.glyphPx + 4 * status.s
        height: status.glyphPx + 4 * status.s

        MaterialIcon {
            anchors.centerIn: parent
            text: Flags.dndActive ? "notifications_off"
                : (Notifs.unread > 0 ? "notifications_unread" : "notifications")
            fill: Notifs.unread > 0 && !Flags.dndActive ? 1 : 0
            color: Flags.dndActive ? Theme.vermLit
                : (Notifs.unread > 0 ? Theme.cream : Theme.subtle)
            font.pixelSize: status.glyphPx
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: status.open("inbox", bellIcon)
        }
    }

    // webcam bridge: shows only while the non-UVC libcamera->v4l2loopback
    // bridge is up (see Singletons/Webcam.qml, ryoku-cmd-webcam-bridge). the
    // one cool-toned glyph in an otherwise all-warm status cluster, so "a
    // background process is relaying your camera" reads as distinct from
    // every ember-toned feature glyph here. click opens a popout explaining
    // what it is and showing its live status.
    Item {
        id: webcamBridgeIcon
        visible: Webcam.bridgeOn
        width: status.glyphPx + 4 * status.s
        height: status.glyphPx + 4 * status.s

        MaterialIcon {
            anchors.centerIn: parent
            text: "videocam"
            fill: Webcam.streaming ? 1 : 0
            color: Theme.bridgeGlow
            font.pixelSize: status.glyphPx
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: status.open("webcamBridge", webcamBridgeIcon)
        }
    }

    // keep-awake shows only while it burns.
    MaterialIcon {
        visible: Flags.keepAwake
        text: "coffee"
        color: Theme.flameGlow
        font.pixelSize: status.glyphPx
    }

    // game mode shows only while it's on.
    MaterialIcon {
        visible: Flags.gameMode
        text: "sports_esports"
        color: Theme.flameGlow
        font.pixelSize: status.glyphPx
    }
}
