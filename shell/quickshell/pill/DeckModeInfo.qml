pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

// the details card under the Keep Awake / Game Mode tiles: what the mode does,
// and a switch for each part of it a user might not want. `mode` ("awake" |
// "game") picks the content and an empty string folds the card shut. every
// control writes straight to Flags, where the mode scripts and KeepAwakeGuard
// read it back, so a change lands while the mode is running.
Item {
    id: root

    property real s: 1
    property string mode: ""
    signal closeRequested()

    // outlives `mode` so the content doesn't blank while the card folds away.
    property string shown: "awake"
    onModeChanged: if (root.mode !== "") root.shown = root.mode

    readonly property var copy: ({
        awake: {
            title: "Keep Awake",
            body: "Stops the computer from idling. While it is on, nothing that waits for you to go quiet can act: the screen won't dim, lock, or turn off, and the machine won't suspend on its own. It stays on until you switch it off, even across restarts."
        },
        game: {
            title: "Game Mode",
            body: "A one-click tune for playing. It trades looks and battery for lower input lag, and puts everything back the moment you turn it off. Changes below apply right away."
        }
    })

    clip: true
    visible: implicitHeight > 0
    implicitHeight: root.mode !== "" ? card.implicitHeight : 0
    Behavior on implicitHeight { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: body.implicitHeight + pad * 2
        radius: Theme.radius
        color: Theme.tileBg
        border.width: 1
        border.color: Theme.border

        readonly property real pad: 12 * root.s

        Column {
            id: body
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: card.pad
            spacing: 10 * root.s

            Item {
                width: parent.width
                height: 16 * root.s

                MicroLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    label: root.copy[root.shown].title
                }
                Item {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 22 * root.s

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 11 * root.s
                        height: 11 * root.s
                        name: "close"
                        color: closeHov.hovered ? Theme.cream : Theme.iconDim
                        stroke: 1.8
                    }
                    HoverHandler { id: closeHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.closeRequested() }
                }
            }

            Text {
                width: parent.width
                text: root.copy[root.shown].body
                wrapMode: Text.WordWrap
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                lineHeight: 1.12
            }

            Rectangle { width: parent.width; height: 1; color: Theme.hair }

            Column {
                width: parent.width
                spacing: 12 * root.s
                visible: root.shown === "awake"

                ModeOption {
                    s: root.s
                    label: "Keep the screen on"
                    hint: "Off still blocks sleep, but the screen dims, locks, and turns off as usual."
                    checked: Flags.keepAwakeScreen
                    onToggled: Flags.keepAwakeScreen = !Flags.keepAwakeScreen
                }
                ModeOption {
                    s: root.s
                    visible: Battery.present
                    label: "Turn off when the battery is low"
                    hint: "Ends Keep Awake at 20% while unplugged, and tells you."
                    checked: Flags.keepAwakeLowBattery
                    onToggled: Flags.keepAwakeLowBattery = !Flags.keepAwakeLowBattery
                }
                ModeChoice {
                    s: root.s
                    label: "Turn off automatically after"
                    hint: "Counted from when Keep Awake was switched on."
                    choices: [
                        { value: 0, text: "Never" },
                        { value: 1, text: "1h" },
                        { value: 2, text: "2h" },
                        { value: 4, text: "4h" },
                        { value: 8, text: "8h" }
                    ]
                    value: Flags.keepAwakeHours
                    onChose: (v) => Flags.keepAwakeHours = v
                }
            }

            Column {
                width: parent.width
                spacing: 12 * root.s
                visible: root.shown === "game"

                ModeOption {
                    s: root.s
                    label: "Turn off blur, shadows, and animations"
                    hint: "Windows lose rounded corners, soft edges, and motion, so frames reach the screen sooner."
                    checked: Flags.gameModeVisuals
                    onToggled: Flags.gameModeVisuals = !Flags.gameModeVisuals
                }
                ModeOption {
                    s: root.s
                    label: "Allow tearing and variable refresh"
                    hint: "Lets a fullscreen game skip vsync for less input lag. Can show tear lines."
                    checked: Flags.gameModeTearing
                    onToggled: Flags.gameModeTearing = !Flags.gameModeTearing
                }
                ModeOption {
                    s: root.s
                    label: "Turn off Wi-Fi power saving"
                    hint: "Keeps the radio awake for steadier ping. Uses more battery."
                    checked: Flags.gameModeWifi
                    onToggled: Flags.gameModeWifi = !Flags.gameModeWifi
                }
                ModeOption {
                    s: root.s
                    label: "Turn on Do Not Disturb"
                    hint: "Silences notification pop-ups while you play. You may miss a message."
                    checked: Flags.gameModeDnd
                    onToggled: Flags.gameModeDnd = !Flags.gameModeDnd
                }
            }
        }
    }
}
