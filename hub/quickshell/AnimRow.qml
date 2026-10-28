pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// one animation leaf in the Animations list: enable switch, speed stepper,
// style + bezier pickers. laid out compactly so the whole tree reads as a table. the
// page owns the values and persists.
Rectangle {
    id: row

    property string leaf: ""
    property bool on: true
    property real speed: 1.0
    property string bezier: ""
    property var curveNames: []
    property string style: ""
    signal toggled(bool v)
    signal speedEdited(real v)
    signal bezierPicked(string b)
    signal stylePicked(string s)

    function styleOptionsFor(leaf) {
        if (leaf.indexOf("windows") === 0)
            return [{ "key": "", "label": "Default" }, { "key": "slide", "label": "Slide" }, { "key": "popin 80%", "label": "Pop in" }, { "key": "gnomed", "label": "Gnomed" }];
        if (leaf.indexOf("workspaces") === 0 || leaf.indexOf("specialWorkspace") === 0)
            return [{ "key": "", "label": "Default" }, { "key": "slide", "label": "Slide" }, { "key": "slidevert", "label": "Slide vertical" }, { "key": "fade", "label": "Fade" }, { "key": "slidefade", "label": "Slide + fade" }, { "key": "slidefadevert", "label": "Slide + fade vertical" }];
        if (leaf.indexOf("layers") === 0)
            return [{ "key": "", "label": "Default" }, { "key": "slide", "label": "Slide" }, { "key": "popin 90%", "label": "Pop in" }, { "key": "fade", "label": "Fade" }];
        return [];
    }
    readonly property var styleOptions: row.styleOptionsFor(row.leaf)
    readonly property bool hasStyle: row.styleOptions.length > 0

    height: 46
    radius: Theme.radius
    color: Theme.surfaceLo
    border.width: 1
    border.color: Theme.line

    Text {
        id: name
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: controls.left
        anchors.rightMargin: 12
        elide: Text.ElideRight
        text: row.leaf
        color: row.on ? Theme.bright : Theme.dim
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Row {
        id: controls
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        // enable
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            height: 22
            radius: Theme.radius
            color: row.on ? Theme.ember : Theme.keyTop
            border.width: 1
            border.color: row.on ? Theme.ember : Theme.line
            Behavior on color { ColorAnimation { duration: Theme.quick } }

            Rectangle {
                width: 16
                height: 16
                radius: 8
                y: 3
                x: row.on ? parent.width - width - 3 : 3
                color: row.on ? Theme.onAccent : Theme.dim
                Behavior on x { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: row.toggled(!row.on) }
        }

        // speed
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            component Step: Rectangle {
                id: st
                property string glyph: ""
                signal hit()
                width: 24
                height: 26
                radius: Theme.radius
                color: stHov.hovered ? Theme.keyTop : Theme.surface
                border.width: 1
                border.color: Theme.line
                Text {
                    anchors.centerIn: parent
                    text: st.glyph
                    color: Theme.cream
                    font.family: Theme.mono
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                HoverHandler { id: stHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: st.hit() }
            }

            Step { glyph: "\u2212"; onHit: row.speedEdited(Math.max(0.1, Math.round((row.speed - 0.1) * 10) / 10)) }
            Text {
                width: 44
                height: 26
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: row.speed.toFixed(1)
                color: Theme.bright
                font.family: Theme.mono
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Step { glyph: "+"; onHit: row.speedEdited(Math.min(10, Math.round((row.speed + 0.1) * 10) / 10)) }
        }

        Dropdown {
            anchors.verticalCenter: parent.verticalCenter
            visible: row.hasStyle
            width: 150
            fieldWidth: 150
            label: ""
            options: row.styleOptions
            current: row.style
            placeholder: row.style
            onChosen: (k) => row.stylePicked(k)
        }

        Dropdown {
            anchors.verticalCenter: parent.verticalCenter
            width: 150
            fieldWidth: 150
            label: ""
            options: row.curveNames
            current: row.bezier
            placeholder: "curve"
            onChosen: (k) => row.bezierPicked(k)
        }
    }
}
