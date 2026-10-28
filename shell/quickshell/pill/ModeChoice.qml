pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

// a labelled row of exclusive choices for a deck mode panel, for an option that
// is a number rather than a switch. `choices` is [{ value, text }]; the one
// matching `value` lights up and a tap reports its value through `chose`.
Item {
    id: root

    property real s: 1
    property string label: ""
    property string hint: ""
    property var choices: []
    property real value: 0
    signal chose(real v)

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 5 * root.s

        Text {
            width: parent.width
            text: root.label
            wrapMode: Text.WordWrap
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11.5 * root.s
            font.weight: Font.DemiBold
        }

        Row {
            id: seg
            width: parent.width
            spacing: 4 * root.s

            Repeater {
                model: root.choices

                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool chosen: chip.modelData.value === root.value

                    width: (seg.width - seg.spacing * (root.choices.length - 1)) / root.choices.length
                    height: 24 * root.s
                    radius: Theme.radius
                    color: chip.chosen ? Qt.alpha(Theme.brand, 0.16)
                        : (chipHov.hovered ? Theme.frameBg : "transparent")
                    border.width: 1
                    border.color: chip.chosen ? Theme.brand
                        : (chipHov.hovered ? Theme.frameBorder : Theme.border)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: chip.modelData.text
                        color: chip.chosen ? Theme.brand : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.DemiBold
                    }

                    HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.chose(chip.modelData.value) }
                }
            }
        }

        Text {
            width: parent.width
            text: root.hint
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * root.s
        }
    }
}
