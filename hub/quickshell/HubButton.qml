import QtQuick
import QtQuick.Controls
import "Singletons"

// Profile dossier action button: small-radius carbon chip with a mono caps label,
// not a generic pill. primary = outlined ember stamp (ember as accent on border +
// label, never a fill); secondary = hairline ghost, border warms to ember on
// hover. hover brightens, press dips.
Item {
    id: btn

    property string label: ""
    property string icon: ""
    property bool primary: false
    signal clicked()

    readonly property real radius: Theme.radiusChip

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 38

    opacity: enabled ? 1 : 0.4
    scale: tap.pressed && btn.enabled ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

    // primary face. outlined ember stamp, ember is the accent, never a fill.
    Rectangle {
        anchors.fill: parent
        visible: btn.primary
        radius: btn.radius
        color: hover.hovered ? Theme.frameBg : "transparent"
        border.width: 1
        border.color: Theme.ember
        Behavior on color { ColorAnimation { duration: Theme.quick } }
    }

    // ghost (secondary). carbon tag, hairline border warming to ember.
    Rectangle {
        anchors.fill: parent
        visible: !btn.primary
        radius: btn.radius
        color: hover.hovered ? Theme.keyTop : "transparent"
        border.width: 1
        border.color: hover.hovered ? Theme.ember : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.quick } }
        Behavior on border.color { ColorAnimation { duration: Theme.quick } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Icon {
            visible: btn.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: btn.icon
            size: 14
            weight: 1.8
            tint: btn.primary ? (hover.hovered ? Qt.lighter(Theme.ember, 1.25) : Theme.ember) : (hover.hovered ? Theme.bright : Theme.cream)
            Behavior on tint { ColorAnimation { duration: Theme.quick } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            color: btn.primary ? (hover.hovered ? Qt.lighter(Theme.ember, 1.25) : Theme.ember) : (hover.hovered ? Theme.bright : Theme.cream)
            font.family: Theme.mono
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.letterSpacing: 1.5
            font.capitalization: Font.AllUppercase
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }
    }

    HoverHandler { id: hover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; enabled: btn.enabled; onTapped: btn.clicked() }

    // optional hover tooltip explaining what the button does, for the terse mono
    // labels that need a sentence. a Popup, so it renders in the window overlay
    // and paints above the page content below instead of being buried under it.
    // shows below the button after a short hover, never on tap.
    property string tooltip: ""

    Timer { id: tipGate; property bool ready: false; interval: 350; onTriggered: tipGate.ready = true }
    Connections {
        target: hover
        function onHoveredChanged() {
            if (hover.hovered) {
                tipGate.ready = false;
                tipGate.restart();
            } else {
                tipGate.stop();
                tipGate.ready = false;
            }
        }
    }

    Popup {
        id: tip
        x: 0
        y: btn.height + 8
        width: 264
        padding: 0
        visible: btn.tooltip !== "" && hover.hovered && tipGate.ready
        closePolicy: Popup.NoAutoClose
        modal: false
        focus: false
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.quick } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.quick } }

        background: Rectangle {
            color: Theme.surface
            radius: btn.radius
            border.width: 1
            border.color: Theme.line
        }

        contentItem: Text {
            text: btn.tooltip
            wrapMode: Text.WordWrap
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 12
            lineHeight: 1.25
            leftPadding: 12
            rightPadding: 12
            topPadding: 10
            bottomPadding: 10
        }
    }
}
