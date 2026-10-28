import QtQuick
import QtQuick.Controls as QQC

// A hover label for a ryoshot control, opened the moment `shown` turns true. It
// is a Popup so it paints in the window overlay, above sibling buttons and the
// Beautify panel's clipped scroll area. It sits centred below its parent and
// flips above when that would run off the bottom of the screen.
QQC.Popup {
    id: tip

    property string text: ""
    property string keys: ""
    property bool shown: false

    readonly property int gap: 10
    // re-measured on every show: the toolbar moves with the selection, and a
    // binding cannot track a mapToItem result on its own.
    readonly property bool fitsBelow: {
        tip.shown;
        if (!tip.parent || !tip.parent.Window.window) return true;
        var p = tip.parent.mapToItem(null, 0, tip.parent.height);
        return p.y + tip.gap + tip.implicitHeight + tip.margins <= tip.parent.Window.height;
    }

    visible: shown && text !== "" && parent !== null && parent.visible
    x: Math.round((parent ? parent.width : 0) / 2 - width / 2)
    y: fitsBelow ? (parent ? parent.height : 0) + gap : -implicitHeight - gap
    margins: 8
    padding: 0
    modal: false
    focus: false
    closePolicy: QQC.Popup.NoAutoClose
    transformOrigin: fitsBelow ? QQC.Popup.Top : QQC.Popup.Bottom

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 90; easing.type: Easing.OutCubic }
    }

    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: -2
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.35)
        }
        Rectangle {
            anchors.fill: parent
            radius: 7
            color: Qt.rgba(22 / 255, 17 / 255, 11 / 255, 0.97)
            border.width: 1
            border.color: Qt.rgba(243 / 255, 237 / 255, 225 / 255, 0.14)
        }
    }

    contentItem: Row {
        spacing: 8
        leftPadding: 10
        rightPadding: tip.keys !== "" ? 6 : 10
        topPadding: 6
        bottomPadding: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: tip.text
            color: "#f5efe4"
            font.family: "Space Grotesk"
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        Rectangle {
            visible: tip.keys !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: keyLabel.implicitWidth + 10
            height: 18
            radius: 4
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(243 / 255, 237 / 255, 225 / 255, 0.12)

            Text {
                id: keyLabel
                anchors.centerIn: parent
                text: tip.keys
                color: "#8f8378"
                font.family: "JetBrains Mono"
                font.pixelSize: 10
            }
        }
    }
}
