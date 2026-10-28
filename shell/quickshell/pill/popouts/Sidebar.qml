pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import ".."
import "../Singletons"

// the LEFT sidebar's content, tabbed: PROFILE (the system specimen tile +
// dossier, a static twin of the Hub Profile page) and STASH (the stash
// board + future add-ons, unchanged -- SidebarStash.qml embedded wholesale
// with its own eyebrow suppressed, since this tab strip already names it). a
// bare, transparent Item -- the shell Popout's blob behind it IS the surface
// and owns the melt/reveal; this panel just fills it. `open` gates the live
// work of whichever tab is showing so a hidden pane (and a shut sidebar)
// costs nothing.
Item {
    id: root

    property real s: 1
    property bool open: false
    // full-span sidebar: the blob fills the frame top-to-bottom, so these insets
    // push the content clear of a top bar and the bottom frame.
    property real topInset: 20 * s
    property real botInset: 20 * s

    // Stash' own enabled pane keys + current pane (unchanged contract,
    // passed straight through to the embedded SidebarStash).
    property var panes: []
    property string pane: ""
    signal paneSelected(string key)

    // the outer Profile/Stash tab, local to this sidebar (persisted via
    // Config.sidebarLeftTab).
    property string topTab: Config.sidebarLeftTab

    // true while a file drag is over the drop-accepting Stash pane, so the
    // shell can keep the sidebar open through a drag mid-grab.
    readonly property bool dragActive: stashPane.dragActive && root.topTab === "stash"

    anchors.fill: parent
    implicitWidth: 340 * s

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.hair
    }

    // thin fade-in thumb for the Profile tab's Flickable, matching the rest
    // of the shell's scrollbar look.
    component VScrollBar: QQC.ScrollBar {
        id: sb
        policy: QQC.ScrollBar.AsNeeded
        visible: size < 1
        width: 5 * root.s
        contentItem: Rectangle {
            implicitWidth: 3 * root.s
            radius: Theme.radius
            color: Theme.subtle
            opacity: sb.pressed ? 0.9 : (sb.hovered ? 0.7 : 0.4)
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
    }

    // outer tab: a mono uppercase label with an underline accent, the same
    // idiom as SidebarStash' glyph tabs but labelled (there are only two,
    // and "Profile"/"Stash" read better as words than icons).
    component TopTab: Item {
        id: tt
        property string label: ""
        property string key: ""
        readonly property bool sel: root.topTab === tt.key
        implicitWidth: ttLabel.implicitWidth
        height: 26 * root.s
        Text {
            id: ttLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: tt.label
            color: tt.sel ? Theme.cream : (ttHov.hovered ? Theme.subtle : Theme.dim)
            font.family: Theme.mono
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 2 * root.s
            font.capitalization: Font.AllUppercase
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: parent.width
            height: 2 * root.s
            radius: Theme.radius
            color: Theme.brand
            visible: tt.sel
        }
        HoverHandler { id: ttHov; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                Config.sidebarLeftTab = tt.key
                Config.persist()
            }
        }
    }

    // ── header: the Profile / Stash tab strip ────────────────────────────
    Row {
        id: topTabs
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.topInset
        anchors.leftMargin: 18 * root.s
        anchors.rightMargin: 18 * root.s
        spacing: 22 * root.s

        TopTab { label: "Profile"; key: "profile" }
        TopTab { label: "Stash"; key: "stash" }
    }

    Divider {
        id: headDiv
        anchors.top: topTabs.bottom
        anchors.topMargin: 10 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 18 * root.s
        anchors.rightMargin: 18 * root.s
    }

    // ── content area: the selected tab fills the rest ───────────────────────
    Item {
        id: content
        anchors.top: headDiv.bottom
        anchors.topMargin: 14 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.botInset

        // ── profile: the specimen tile + dossier, scrollable ────────────────
        Flickable {
            id: profileFlick
            anchors.fill: parent
            anchors.leftMargin: 18 * root.s
            anchors.rightMargin: 18 * root.s
            visible: root.topTab === "profile"
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: profileCol.implicitHeight
            QQC.ScrollBar.vertical: VScrollBar {}

            Column {
                id: profileCol
                width: profileFlick.width - 10 * root.s
                spacing: 20 * root.s

                ProfileTile {
                    cardWidth: profileCol.width
                }

                ProfileDossier {
                    width: profileCol.width
                }
            }
        }

        // ── stash: the stash board + future add-ons, embedded as-is ─────
        SidebarStash {
            id: stashPane
            anchors.fill: parent
            visible: root.topTab === "stash"
            s: root.s
            topInset: 0
            botInset: 0
            showHeader: false
            open: root.open && root.topTab === "stash"
            panes: root.panes
            pane: root.pane
            onPaneSelected: (k) => root.paneSelected(k)
        }
    }
}
