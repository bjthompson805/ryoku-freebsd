import QtQuick

Rectangle {
    id: btn
    property string icon: ""
    property bool active: false
    property bool dim: false
    property string tip: ""
    property string keys: ""

    signal clicked()

    width: 32
    height: 32
    radius: 7
    color: active ? "#e2342a" : (ma.containsMouse && !dim ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

    readonly property color idle: "#c7bfae"

    Icon {
        anchors.centerIn: parent
        name: btn.icon
        size: 18
        tint: btn.active ? "#ffffff" : (btn.dim ? Qt.rgba(0.77, 0.80, 0.85, 0.35) : btn.idle)
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: { if (!btn.dim) btn.clicked(); }
    }

    Tooltip { text: btn.tip; keys: btn.keys; shown: ma.containsMouse }
}
