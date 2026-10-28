pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// bare bordered text box: a TextInput plus an inline checkmark button that
// appears whenever the typed text differs from the committed value. Used
// standalone (AppOverridesPage.qml's per-column match fields, sized and
// positioned by the caller) or wrapped by SettingField.qml for the common
// label-left/box-right layout.
//
// Commits on Enter, on losing focus, or a click on the checkmark -- whichever
// comes first. Losing focus only actually happens when the whole host window
// loses focus (clicking elsewhere inside the same window doesn't move
// keyboard focus off a plain TextInput on its own), so the checkmark is the
// one commit path that's always reachable with the mouse alone.
Rectangle {
    id: root

    property string value: ""
    property string placeholder: ""
    property bool mono: false
    signal committed(string text)

    readonly property bool pending: input.text !== root.value

    height: 30
    radius: Theme.radius
    color: Theme.surfaceLo
    border.width: 1
    border.color: input.activeFocus ? Theme.ember : Theme.line
    Behavior on border.color { ColorAnimation { duration: Theme.quick } }

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.right: applyBtn.visible ? applyBtn.left : parent.right
        anchors.rightMargin: applyBtn.visible ? 4 : 12
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        verticalAlignment: TextInput.AlignVCenter
        text: root.value
        color: Theme.bright
        font.family: root.mono ? Theme.mono : Theme.font
        font.pixelSize: 13
        clip: true
        selectByMouse: true
        onActiveFocusChanged: {
            if (activeFocus)
                selectAll();
            else
                text = Qt.binding(() => root.value);
        }
        onEditingFinished: root.committed(text)

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text === "" && !input.activeFocus
            text: root.placeholder
            color: Theme.faint
            font: input.font
        }
    }

    Item {
        id: applyBtn
        visible: root.pending
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: applyHover.hovered ? Theme.keyTop : "transparent"
        }

        Icon {
            anchors.centerIn: parent
            name: "check"
            size: 12
            weight: 2.2
            tint: applyHover.hovered ? Theme.ember : Theme.dim
            Behavior on tint { ColorAnimation { duration: Theme.quick } }
        }

        HoverHandler { id: applyHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.committed(input.text) }
    }
}
