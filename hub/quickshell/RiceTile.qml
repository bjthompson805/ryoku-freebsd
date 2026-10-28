import QtQuick
import "Singletons"

// one rice as a storefront tile: a big preview (or a warm placeholder when the
// rice has no image yet), the name over a scrim, an ACTIVE pill on the applied
// rice, and version / compatibility chips. click opens the detail.
Rectangle {
    id: tile

    property var rice: ({})
    signal opened()

    readonly property string preview: tile.rice.preview || tile.rice.posterUrl || ""
    readonly property bool active: !!tile.rice.active
    readonly property string compat: tile.rice.compat || "unknown"
    property bool store: false
    readonly property bool installed: !!tile.rice.installed

    // preview colours: from the rice's own look (local) or the store entry's
    // hints (catalog), used to draw a mockup when there is no image.
    readonly property bool hasImage: tile.preview !== ""
    readonly property color mockSurface: {
        var s = "";
        if (tile.rice.look && tile.rice.look.shell && tile.rice.look.shell.surfaceColor)
            s = tile.rice.look.shell.surfaceColor;
        else if (tile.rice.surface)
            s = tile.rice.surface;
        return s !== "" ? s : Theme.surfaceLo;
    }
    readonly property color mockAccent: {
        var a = "";
        if (tile.rice.look && tile.rice.look.hypr && tile.rice.look.hypr.appearance && tile.rice.look.hypr.appearance.activeBorder)
            a = tile.rice.look.hypr.appearance.activeBorder;
        else if (tile.rice.accent)
            a = tile.rice.accent;
        return a !== "" ? a : Theme.ember;
    }
    readonly property real mockRounding: {
        var r;
        if (tile.rice.look && tile.rice.look.hypr && tile.rice.look.hypr.appearance && tile.rice.look.hypr.appearance.rounding !== undefined)
            r = tile.rice.look.hypr.appearance.rounding;
        else
            r = tile.rice.rounding;
        return (r === undefined || r === null) ? 8 : r;
    }

    implicitWidth: 320
    implicitHeight: 250
    radius: Theme.radius
    color: hover.hovered ? Theme.surface : Theme.surfaceLo
    border.width: tile.active ? 2 : 1
    border.color: (tile.active || hover.hovered) ? Theme.ember : Theme.line
    clip: true
    scale: hover.hovered ? 1.012 : 1.0
    Behavior on color { ColorAnimation { duration: Theme.quick } }
    Behavior on border.color { ColorAnimation { duration: Theme.quick } }
    Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

    Item {
        id: shot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 150
        clip: true

        Rectangle {
            anchors.fill: parent
            visible: !tile.hasImage
            color: tile.mockSurface
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.62
                height: parent.height * 0.6
                radius: Math.min(tile.mockRounding, 26)
                color: Qt.lighter(tile.mockSurface, 1.35)
                border.width: 2
                border.color: tile.mockAccent
                Row {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 8
                    spacing: 5
                    Rectangle { width: 6; height: 6; radius: 3; color: tile.mockAccent }
                    Rectangle { width: 6; height: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.18) }
                    Rectangle { width: 6; height: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.18) }
                }
            }
        }

        Image {
            id: img
            anchors.fill: parent
            visible: tile.hasImage
            source: tile.preview
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: 720
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 66
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
            }
        }

        Rectangle {
            visible: tile.active
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: activeRow.implicitWidth + 16
            height: 22
            radius: Theme.radius
            color: Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.92)
            Row {
                id: activeRow
                anchors.centerIn: parent
                spacing: 5
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: "#0d1208" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ACTIVE"
                    color: "#0d1208"
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }
            }
        }
        Rectangle {
            visible: tile.store && tile.installed
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: instRow.implicitWidth + 16
            height: 22
            radius: Theme.radius
            color: Qt.rgba(0, 0, 0, 0.55)
            border.width: 1
            border.color: Theme.hair
            Row {
                id: instRow
                anchors.centerIn: parent
                spacing: 5
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 10; weight: 2; tint: Theme.ok }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "INSTALLED"
                    color: Theme.subtle
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            text: tile.rice.name || tile.rice.slug || ""
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 18
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: shot.bottom
        anchors.margins: 14
        spacing: 9

        Text {
            width: parent.width
            text: tile.rice.blurb || "A saved desktop look."
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12
            lineHeight: 1.3
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Row {
            spacing: 6
            Rectangle {
                visible: tile.compat === "older" || tile.compat === "newer"
                height: 20
                width: compatLabel.implicitWidth + 16
                radius: Theme.radius
                color: "transparent"
                border.width: 1
                border.color: tile.compat === "newer" ? Theme.bad : Theme.line
                Text {
                    id: compatLabel
                    anchors.centerIn: parent
                    text: tile.compat === "older" ? "older Ryoku" : "newer Ryoku"
                    color: tile.compat === "newer" ? Theme.bad : Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }
            }
            Rectangle {
                visible: (tile.rice.createdWith || "") !== ""
                height: 20
                width: verLabel.implicitWidth + 16
                radius: Theme.radius
                color: Theme.keyTop
                border.width: 1
                border.color: Theme.line
                Text {
                    id: verLabel
                    anchors.centerIn: parent
                    text: "v" + (tile.rice.createdWith || "")
                    color: Theme.subtle
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.weight: Font.Medium
                }
            }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: tile.opened() }
}
