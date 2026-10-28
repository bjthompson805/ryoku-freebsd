import QtQuick
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import "Singletons"

Item {
    id: root

    property real s: 1
    property bool suppressed: false
    property bool flashing: false
    property string kind: "volume"
    property bool armed: false
    property string lockKeyName: ""
    property bool lockKeyState: false
    property string shownTrackLine: ""
    property bool shownPlaying: false
    property string shownArtUrl: ""
    property string lastTrackLine: ""
    property bool lastPlaying: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property real volume: sink && sink.audio ? Math.max(0, Math.min(1, sink.audio.volume)) : 0

    property var stickyPlayer: null
    readonly property var player: {
        var list = Mpris.players.values;
        if (!list || list.length === 0)
            return null;
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].isPlaying)
                return list[i];
        }
        if (stickyPlayer && list.indexOf(stickyPlayer) >= 0)
            return stickyPlayer;
        return list[0];
    }
    readonly property bool playing: player !== null && player.isPlaying
    readonly property string trackLine: {
        if (!player)
            return "";
        var t = player.trackTitle ? player.trackTitle : "";
        var a = Theme.joinArtists(player.trackArtists, player.trackArtist);
        return a.length > 0 ? t + " · " + a : t;
    }

    readonly property real desiredW: 248 * s
    readonly property real desiredH: 44 * s

    function trackEvent() {
    }

    function flash(which) {
        if (!armed || suppressed || cooldownTimer.running)
            return;
        if (which === "track")
            return;
        kind = which;
        flashing = true;
        hideTimer.restart();
    }

    function flashLockKey(name, on) {
        lockKeyName = name;
        lockKeyState = on;
        flash("lockkey");
    }

    onSuppressedChanged: {
        if (suppressed) {
            hideTimer.stop();
            flashing = false;
        } else {
            cooldownTimer.restart();
        }
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: hideTimer
        interval: 1400
        onTriggered: root.flashing = false
    }

    Timer {
        id: cooldownTimer
        interval: 200
    }

    PwObjectTracker {
        objects: [root.sink].filter(Boolean)
    }

    Connections {
        target: root.sink && root.sink.audio ? root.sink.audio : null
        function onVolumesChanged() { root.flash("volume"); }
        function onMutedChanged() { root.flash("volume"); }
    }

    Connections {
        target: Devices
        function onPanelBrightnessUserChanged() { root.flash("brightness"); }
    }

    Connections {
        target: LockKeys
        function onCapsLockChanged() { if (Config.lockKeyOsdEnabled) root.flashLockKey("Caps Lock", LockKeys.capsLock); }
        function onNumLockChanged() { if (Config.lockKeyOsdEnabled) root.flashLockKey("Num Lock", LockKeys.numLock); }
        function onScrollLockChanged() { if (Config.lockKeyOsdEnabled) root.flashLockKey("Scroll Lock", LockKeys.scrollLock); }
    }

    onPlayerChanged: {
        Qt.callLater(function() {
            if (stickyPlayer !== player)
                stickyPlayer = player;
        });
        trackEvent();
    }

    Connections {
        target: root.player
        function onTrackTitleChanged() { root.trackEvent(); }
        function onPlaybackStateChanged() { root.trackEvent(); }
    }

    Item {
        id: volRow
        anchors.fill: parent
        opacity: root.kind === "volume" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        GlyphIcon {
            id: volGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s
            name: root.muted ? "speaker-off" : "speaker"
            color: root.muted ? Theme.dim : Theme.iconDim
            stroke: 1.7
        }

        Text {
            id: volPct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 32 * root.s
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.volume * 100) + "%"
            color: root.muted ? Theme.dim : Theme.cream
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        Rectangle {
            anchors.left: volGlyph.right
            anchors.leftMargin: 12 * root.s
            anchors.right: volPct.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            height: 4 * root.s
            radius: Theme.radius
            color: Theme.threadBg

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * root.volume
                radius: parent.radius
                color: root.muted ? Theme.vermDim : Theme.vermLit
                Behavior on width { NumberAnimation { duration: Motion.fast } }
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }
    }

    Item {
        id: backlightRow
        anchors.fill: parent
        opacity: root.kind === "brightness" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        GlyphIcon {
            id: backlightGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s
            name: "sun"
            color: Theme.iconDim
            stroke: 1.7
        }

        Text {
            id: backlightPct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 32 * root.s
            horizontalAlignment: Text.AlignRight
            text: Math.max(0, Devices.panelBrightness) + "%"
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        Rectangle {
            anchors.left: backlightGlyph.right
            anchors.leftMargin: 12 * root.s
            anchors.right: backlightPct.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            height: 4 * root.s
            radius: Theme.radius
            color: Theme.threadBg

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, Devices.panelBrightness) / 100
                radius: parent.radius
                color: Theme.vermLit
                Behavior on width { NumberAnimation { duration: Motion.fast } }
            }
        }
    }

    Item {
        id: lockKeyRow
        anchors.fill: parent
        opacity: root.kind === "lockkey" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        GlyphIcon {
            id: lockGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s
            name: "lock"
            color: root.lockKeyState ? Theme.iconDim : Theme.dim
            stroke: 1.7
        }

        Text {
            id: lockStateText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.lockKeyState ? "On" : "Off"
            color: root.lockKeyState ? Theme.vermLit : Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
        }

        Text {
            anchors.left: lockGlyph.right
            anchors.leftMargin: 12 * root.s
            anchors.right: lockStateText.left
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: root.lockKeyName
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    Item {
        id: trackRow
        anchors.fill: parent
        opacity: root.kind === "track" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        ClippingRectangle {
            id: coverBox
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 30 * root.s
            height: 30 * root.s
            radius: Theme.radius
            color: Theme.tileBg

            Image {
                id: cover
                anchors.fill: parent
                source: root.shownArtUrl
                sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: status === Image.Ready && root.shownArtUrl !== ""
            }
            GlyphIcon {
                anchors.centerIn: parent
                width: parent.width * 0.45
                height: width
                name: "music"
                color: Theme.subtle
                visible: !cover.visible
            }
        }

        GlyphIcon {
            id: trackGlyph
            anchors.left: coverBox.right
            anchors.leftMargin: 11 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * root.s
            height: 16 * root.s
            name: root.shownPlaying ? "play-s" : "pause-s"
            color: Theme.iconDim
            stroke: 1.7
        }

        Text {
            anchors.left: trackGlyph.right
            anchors.leftMargin: 10 * root.s
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.shownTrackLine
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11.5 * root.s
            font.weight: Font.DemiBold
            maximumLineCount: 1
            elide: Text.ElideRight
        }
    }
}
