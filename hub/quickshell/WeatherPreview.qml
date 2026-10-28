pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// live plain-QML preview of the desktop weather widget for the Desktop Widgets
// section. mirrors ryoku/shell/quickshell/widgets/weather with a representative
// animated sky cycling through conditions (so motion is visible in the hub),
// sample data, real wallust accent. layout / unit / scope match the live
// widget; forecast numbers are illustrative.
Item {
    id: preview

    property string design: "card"
    property string unit: "C"
    property string scope: "today"
    property bool animate: true

    readonly property color ink: "#f5f3ff"
    readonly property color inkDim: "#9aa3c8"
    readonly property color accent: Wallust.accent

    readonly property var cats: ["clear", "clouds", "rain", "snow"]
    readonly property var temps: [24, 19, 15, -1]
    readonly property var labels: ["Clear", "Cloudy", "Rain", "Snow"]
    property int idx: 0
    readonly property string category: cats[idx]
    readonly property int temp: temps[idx]
    readonly property string condition: labels[idx]
    Timer { interval: 4000; running: preview.animate; repeat: true; onTriggered: preview.idx = (preview.idx + 1) % 4 }

    readonly property var sampleDaily: [
        { "day": "Mon", "cat": "clear", "hi": 24, "lo": 13 },
        { "day": "Tue", "cat": "clouds", "hi": 21, "lo": 12 },
        { "day": "Wed", "cat": "rain", "hi": 18, "lo": 11 },
        { "day": "Thu", "cat": "clear", "hi": 23, "lo": 14 },
        { "day": "Fri", "cat": "snow", "hi": 2, "lo": -4 }
    ]

    Loader {
        anchors.centerIn: parent
        sourceComponent: preview.design === "minimal" ? minimalC : (preview.design === "strip" ? stripC : cardC)
    }

    // --- shared bits -------------------------------------------------------
    component PCloud: Item {
        property color tint: "#eef2ff"
        Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width; height: parent.height * 0.46; radius: height / 2; color: parent.tint }
        Rectangle { x: parent.width * 0.06; anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height * 0.16; width: parent.height * 0.6; height: width; radius: width / 2; color: parent.tint }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; width: parent.height * 0.84; height: width; radius: width / 2; color: parent.tint }
        Rectangle { x: parent.width * 0.9 - width; anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height * 0.14; width: parent.height * 0.64; height: width; radius: width / 2; color: parent.tint }
    }

    component MiniSky: Item {
        id: ms
        property string category: "clear"
        property bool animate: true
        readonly property real u: Math.min(width, height)
        clip: true

        property real phase: 0
        NumberAnimation on phase {
            running: ms.animate && (ms.category === "rain" || ms.category === "snow")
            from: 0; to: 1; duration: ms.category === "snow" ? 4200 : 1100; loops: Animation.Infinite
        }
        property real spin: 0
        NumberAnimation on spin { running: ms.animate && ms.category === "clear"; from: 0; to: 360; duration: 90000; loops: Animation.Infinite }

        // sun.
        Item {
            anchors.fill: parent
            visible: ms.category === "clear"
            Rectangle { anchors.centerIn: parent; width: ms.u * 0.62; height: width; radius: width / 2; color: Qt.rgba(1, 0.72, 0.34, 0.2) }
            Item {
                anchors.centerIn: parent; width: ms.u; height: ms.u; rotation: ms.spin
                Repeater {
                    model: 12
                    Item {
                        required property int index
                        anchors.fill: parent; rotation: index * 30
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: ms.u * 0.05; width: Math.max(2, ms.u * 0.02); height: ms.u * 0.1; radius: width / 2; color: Qt.rgba(1, 0.81, 0.52, 0.85) }
                    }
                }
            }
            Rectangle {
                anchors.centerIn: parent; width: ms.u * 0.44; height: width; radius: width / 2
                gradient: Gradient { GradientStop { position: 0.0; color: "#ffe3a8" } GradientStop { position: 1.0; color: "#ffb24d" } }
            }
        }

        // cloud + precip.
        Item {
            anchors.fill: parent
            visible: ms.category !== "clear"
            PCloud {
                width: parent.width * 0.72; height: parent.height * 0.4
                anchors.horizontalCenter: parent.horizontalCenter; y: parent.height * 0.08
                tint: ms.category === "rain" ? "#c4ccdf" : ms.category === "snow" ? "#dfe6f5" : "#eef2ff"
            }
            Repeater {
                model: ms.category === "rain" ? 10 : 0
                Rectangle {
                    required property int index
                    readonly property real off: (index * 0.382) % 1
                    readonly property real len: ms.height * 0.17
                    readonly property real span: ms.height + len
                    width: 2; height: len; radius: Theme.radius; rotation: 14; antialiasing: true
                    color: Qt.rgba(0.62, 0.76, 1, 0.82)
                    x: ms.width * (0.08 + ((index * 0.6180339) % 1) * 0.84)
                    y: ((ms.phase + off) % 1) * span - len + ms.height * 0.28
                }
            }
            Repeater {
                model: ms.category === "snow" ? 9 : 0
                Rectangle {
                    required property int index
                    readonly property real off: (index * 0.382) % 1
                    readonly property real d: Math.max(3, ms.width * 0.05)
                    readonly property real span: ms.height + d
                    width: d; height: d; radius: d / 2; color: "#f2f6ff"; opacity: 0.92
                    x: ms.width * (0.06 + ((index * 0.6180339) % 1) * 0.86) + Math.sin((ms.phase + off) * Math.PI * 2) * ms.width * 0.04
                    y: ((ms.phase + off) % 1) * span - d + ms.height * 0.22
                }
            }
        }
    }

    component DayCol: Column {
        property string day: ""
        property string cat: "clouds"
        property int hi: 0
        property int lo: 0
        spacing: 4
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.day; color: preview.inkDim; font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium }
        MiniSky { anchors.horizontalCenter: parent.horizontalCenter; width: 30; height: 30; category: parent.cat; animate: false }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.hi + "\u00b0"; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13; font.weight: Font.DemiBold }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.lo + "\u00b0"; color: preview.inkDim; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.weight: Font.Medium }
    }

    component WeekRow: Row {
        spacing: 16
        Repeater {
            model: preview.sampleDaily
            DayCol {
                required property var modelData
                day: modelData.day; cat: modelData.cat; hi: modelData.hi; lo: modelData.lo
            }
        }
    }

    component Stat: Column {
        property string label: ""
        property string value: ""
        spacing: 2
        Text { text: parent.value; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 19; font.weight: Font.DemiBold }
        Text { text: parent.label; color: preview.inkDim; font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 1 }
    }

    // --- designs -----------------------------------------------------------
    Component {
        id: cardC
        Column {
            spacing: 16
            Row {
                spacing: 16
                Rectangle {
                    width: 108; height: 108; radius: Theme.radius; clip: true
                    gradient: Gradient { GradientStop { position: 0.0; color: "#5b8fcf" } GradientStop { position: 1.0; color: "#9cc3ea" } }
                    MiniSky { anchors.fill: parent; category: preview.category; animate: preview.animate }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    Row {
                        spacing: 4
                        Text { text: preview.temp + "\u00b0"; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 56; font.weight: Font.Bold }
                        Text { anchors.top: parent.top; anchors.topMargin: 11; text: preview.unit; color: preview.inkDim; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 22; font.weight: Font.DemiBold }
                    }
                    Text { text: preview.condition; color: preview.accent; font.family: "Inter"; font.pixelSize: 19; font.weight: Font.DemiBold }
                }
            }
            Loader { sourceComponent: preview.scope === "week" ? weekC : todayC }
        }
    }

    Component {
        id: minimalC
        Row {
            spacing: 14
            MiniSky { width: 78; height: 78; anchors.verticalCenter: parent.verticalCenter; category: preview.category; animate: preview.animate }
            Column {
                anchors.verticalCenter: parent.verticalCenter; spacing: 2
                Row {
                    spacing: 3
                    Text { text: preview.temp + "\u00b0"; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 48; font.weight: Font.Bold }
                    Text { anchors.top: parent.top; anchors.topMargin: 9; text: preview.unit; color: preview.inkDim; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18; font.weight: Font.DemiBold }
                }
                Text { text: preview.condition; color: preview.accent; font.family: "Inter"; font.pixelSize: 16; font.weight: Font.DemiBold }
            }
        }
    }

    Component {
        id: stripC
        Row {
            spacing: 18
            Column {
                anchors.verticalCenter: parent.verticalCenter; spacing: 3
                MiniSky { anchors.horizontalCenter: parent.horizontalCenter; width: 60; height: 60; category: preview.category; animate: preview.animate }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; spacing: 2
                    Text { text: preview.temp + "\u00b0"; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 36; font.weight: Font.Bold }
                    Text { anchors.top: parent.top; anchors.topMargin: 5; text: preview.unit; color: preview.inkDim; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
            }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 96; color: Qt.rgba(1, 1, 1, 0.14) }
            Loader { anchors.verticalCenter: parent.verticalCenter; sourceComponent: preview.scope === "today" ? todayC : weekC }
        }
    }

    Component {
        id: todayC
        Row {
            spacing: 26
            Stat { label: "HUMIDITY"; value: "58%" }
            Stat { label: "WIND"; value: "12 km/h" }
        }
    }
    Component { id: weekC; WeekRow {} }
}
