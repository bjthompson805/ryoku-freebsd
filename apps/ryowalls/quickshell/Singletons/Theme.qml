pragma Singleton
import QtQuick
import Quickshell

// App palette: the hub's tokens, kept in step by hand.
Singleton {
    readonly property color brand:     "#e2342a"
    readonly property color ember:     "#e83b30"
    readonly property color emberDeep: "#b81f19"
    readonly property color sun:       "#e2342a"
    readonly property color gold:      "#d9a441"

    readonly property color ok:        "#7fbf6a"
    readonly property color bad:       "#e05a5a"

    readonly property color bgTop:    "#16110b"
    readonly property color bgBot:    "#0f0c07"
    readonly property color rail:     "#120e08"
    readonly property color surface:  "#1b150e"
    readonly property color surfaceLo:"#140f09"
    readonly property color keyTop:   "#221a12"
    readonly property color keyBot:   "#17110b"
    readonly property color line:     Qt.rgba(243 / 255, 237 / 255, 225 / 255, 0.14)
    readonly property color lineSoft: Qt.rgba(243 / 255, 237 / 255, 225 / 255, 0.06)
    readonly property color lineStrong: Qt.rgba(236 / 255, 226 / 255, 205 / 255, 0.40)
    readonly property color shadow:   "#000000"

    readonly property color cardTop:  "#1b140d"
    readonly property color cardBot:  "#120d08"
    readonly property color frameBg:  Qt.rgba(226 / 255, 52 / 255, 42 / 255, 0.10)
    readonly property color hair:     Qt.rgba(243 / 255, 237 / 255, 225 / 255, 0.12)

    readonly property color bright:   "#f3ede1"
    readonly property color cream:    "#e6dccb"
    readonly property color subtle:   "#c7bfae"
    readonly property color dim:      "#8f8770"
    readonly property color faint:    "#5c5249"
    readonly property color onAccent: "#fbeee2"

    readonly property string display: "Fraunces"
    readonly property string font:    "Space Grotesk"
    readonly property string fontJp:  "Noto Sans CJK JP"
    readonly property string mono:    "JetBrainsMono Nerd Font"

    readonly property int radius:      0
    readonly property real border:     1
    readonly property int shadowStep:  6
    readonly property int shadowStepLg: 8

    readonly property int quick:  120
    readonly property int medium: 240
    readonly property int slow:   360
    readonly property int ease:   Easing.OutExpo
}
