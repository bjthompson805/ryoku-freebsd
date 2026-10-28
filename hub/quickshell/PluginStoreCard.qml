import QtQuick
import QtQuick.Effects
import "Singletons"

// storefront tile for one downloadable plugin: live preview image up top, a
// warm scrim carrying name + official badge, tagline and host chips below on
// the warm surface. on hover the hairline warms to ember and the tile lifts a
// touch, so the grid reads like a polished app store and not a list of names.
// click = open the rich detail.
Rectangle {
    id: tile

    property var plugin: ({})
    property bool installed: false
    readonly property string preview: tile.plugin.preview || ((tile.plugin.screenshots && tile.plugin.screenshots.length > 0) ? tile.plugin.screenshots[0] : "")
    readonly property var hosts: tile.plugin.hosts || []

    signal opened()

    implicitWidth: 320
    implicitHeight: 286
    radius: Theme.radius
    color: hover.hovered ? Theme.surface : Theme.surfaceLo
    border.width: 1
    border.color: hover.hovered ? Theme.ember : Theme.line
    clip: true
    scale: hover.hovered ? 1.012 : 1.0
    Behavior on color { ColorAnimation { duration: Theme.quick } }
    Behavior on border.color { ColorAnimation { duration: Theme.quick } }
    Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

    // ── Preview image, top ──────────────────────────────────────────────────
    Item {
        id: shot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 168
        clip: true

        // quiet placeholder behind the image so a slow/missing load still reads.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.keyTop }
                GradientStop { position: 1.0; color: Theme.surfaceLo }
            }
            Icon {
                anchors.centerIn: parent
                name: tile.plugin.icon || "widgets"
                size: 34
                weight: 1.5
                tint: Theme.faint
                visible: img.status !== Image.Ready
            }
        }

        Image {
            id: img
            anchors.fill: parent
            source: tile.preview
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: 720
            // slow zoom-in on hover, like a featured store card.
            scale: hover.hovered ? 1.05 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.slow; easing.type: Theme.ease } }
        }

        // bottom scrim, keeps the name legible over any image.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 84
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
            }
        }

        // official / community badge, top-right.
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            width: badge.implicitWidth + 18
            height: 22
            radius: Theme.radius
            color: tile.plugin.official ? Qt.rgba(Theme.brand.r, Theme.brand.g, Theme.brand.b, 0.92)
                                         : Qt.rgba(0, 0, 0, 0.55)
            border.width: tile.plugin.official ? 0 : 1
            border.color: Theme.hair
            Row {
                id: badge
                anchors.centerIn: parent
                spacing: 5
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: tile.plugin.official ? "verified" : "users"
                    size: 11
                    weight: 2
                    tint: tile.plugin.official ? Theme.onAccent : Theme.subtle
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tile.plugin.official ? "Official" : "Community"
                    color: tile.plugin.official ? Theme.onAccent : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.3
                }
            }
        }

        // installed tick, top-left.
        Rectangle {
            visible: tile.installed
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 12
            width: 22; height: 22; radius: 11
            color: Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.92)
            Icon { anchors.centerIn: parent; name: "check"; size: 12; weight: 2.5; tint: "#0d1208" }
        }

        // name + brand mark over the scrim.
        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 14
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u529b"
                color: Theme.brand
                font.family: Theme.fontJp
                font.pixelSize: 15
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tile.plugin.name || tile.plugin.id || ""
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 19
                font.weight: Font.DemiBold
            }
        }
    }

    // ── Tagline + host chips, below ─────────────────────────────────────────
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: shot.bottom
        anchors.margins: 16
        spacing: 11

        Text {
            width: parent.width
            text: tile.plugin.tagline || tile.plugin.description || ""
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 13
            lineHeight: 1.3
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Row {
            spacing: 6
            Repeater {
                model: tile.hosts
                Rectangle {
                    required property var modelData
                    height: 20
                    width: hostLabel.implicitWidth + 16
                    radius: Theme.radius
                    color: Theme.keyBot
                    border.width: 1
                    border.color: Theme.line
                    Text {
                        id: hostLabel
                        anchors.centerIn: parent
                        text: modelData === "framePopout" ? "Frame popout"
                            : modelData === "desktopWidget" ? "Desktop widget"
                            : modelData
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    layer.enabled: hover.hovered
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.5)
        shadowBlur: 1.0
        shadowVerticalOffset: 8
        autoPaddingEnabled: true
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: tile.opened() }
}
