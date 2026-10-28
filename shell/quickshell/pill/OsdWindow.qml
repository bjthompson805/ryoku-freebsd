pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Singletons"

// Volume / brightness / lock keys OSD in its own small layer window, top-centre just
// below the bar. Re-homed from the floating pill: the Osd component still
// drives its own flashing on volume/brightness/lock key changes (via Pipewire,
// Devices, and LockKeys), so this window only maps while it flashes. Click-through,
// never takes focus, never reserves space, and displays over fullscreen windows.
PanelWindow {
    id: win

    required property var modelData
    readonly property real s: (modelData ? modelData.height / 1080 : 1) * Math.max(0.7, Math.min(1.6, Config.fontScale))

    // top/bottom bar (left/right collapse to top, as the overlay does).
    readonly property string barPos: Config.barEnabled ? (Config.barPosition === "bottom" ? "bottom" : "top") : ""
    readonly property bool barTop: barPos === "top"
    // clear the top bar band (or just the top frame lip), matching the
    // overlay's barVisibleH, then float a small gap below it.
    readonly property real frameLip: Math.max(0, Config.frameBorder - 50)
    readonly property real barVisibleH: frameLip + Config.barHeight * s
    readonly property real topInset: (barTop ? barVisibleH : frameLip) + 12 * s

    screen: modelData
    visible: osd.flashing
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "ryoku-osd"

    anchors.top: true
    margins.top: topInset

    implicitWidth: osd.desiredW
    implicitHeight: osd.desiredH

    // the surface material: warm surface fill + hairline border, fully
    // rounded like a small panel; no shadow (only the frame's inverted rect
    // casts one).
    Rectangle {
        anchors.fill: parent
        radius: Config.osdRadius * win.s
        color: Config.matchWallpaper ? Wallust.surface : Config.surfaceColor
        opacity: Config.osdOpacity
        border.width: 1.5
        border.color: Config.matchWallpaper ? Wallust.border : Config.lockedBorderColor
        antialiasing: true
    }

    Osd {
        id: osd
        anchors.fill: parent
        anchors.topMargin: 12 * win.s
        anchors.bottomMargin: 12 * win.s
        anchors.leftMargin: 18 * win.s
        anchors.rightMargin: 18 * win.s
        s: win.s
    }

    // click-through: the OSD is a passive readout, never eats a press.
    mask: Region {}
}
