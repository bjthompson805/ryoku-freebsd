pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "Singletons"

// Profile section = a showcase screen built to be screenshotted with a rice.
// specimen card on the left (the hero), extended system stats dossier on the
// right, ambient backdrop ties them together. card is the hub-palette twin of
// the shell pill's system card.
Item {
    id: page

    // specimen is height-bound. keep it under ~42% of the width so the dossier
    // has room on the right.
    readonly property real cardW: Math.round(Math.min((page.height - 44) * 0.585, page.width * 0.42, 440))

    ShowcaseBackdrop { anchors.fill: parent }

    // Dimmed Lady Justice, bleeding off the right edge behind the dossier, the
    // website's beauty panel motif as an ambient backdrop. Marble + irezumi read
    // faintly through the stats; a left fade dissolves her into the page.
    Image {
        id: justice
        source: "art/marble-justice.png"
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        opacity: 0.42
        height: parent.height
        width: height
        anchors.right: parent.right
        anchors.rightMargin: -parent.width * 0.04
        anchors.verticalCenter: parent.verticalCenter
        layer.enabled: true
        layer.effect: MultiEffect {
            // dim + desaturate so she sits behind the data, not over it
            brightness: -0.18
            saturation: -0.35
        }
    }
    // left-edge fade so she dissolves into the canvas (dim-out like the site)
    Rectangle {
        anchors.fill: justice
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.bgBot }
            GradientStop { position: 0.45; color: "transparent" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // specimen, left and lifted.
    ProfileCard {
        id: hero
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        cardWidth: page.cardW

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.55)
            shadowBlur: 1.0
            shadowVerticalOffset: 12
            autoPaddingEnabled: true
        }
    }

    // hairline rule down the gutter, specimen | dossier.
    Rectangle {
        anchors.left: hero.right
        anchors.leftMargin: 21
        anchors.top: hero.top
        anchors.bottom: hero.bottom
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        width: 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.16; color: Qt.alpha(Theme.cream, 0.09) }
            GradientStop { position: 0.84; color: Qt.alpha(Theme.cream, 0.09) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // dossier, right, spans the specimen's height.
    ProfileStats {
        anchors.left: hero.right
        anchors.leftMargin: 44
        anchors.right: parent.right
        anchors.rightMargin: 26
        anchors.top: hero.top
        anchors.topMargin: 8
        anchors.bottom: hero.bottom
    }
}
