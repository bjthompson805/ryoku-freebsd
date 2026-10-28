import QtQuick
import QtQuick.Controls
import "Singletons"
import "fuzzy.js" as Fuzzy

// shortcut legend, read live. each category = ember header + hairline rule,
// then binds separated by faint dividers. categories = JSON from the ryoku-hub
// backend (parsed from the live binds.lua, so it never drifts from what's
// actually bound). the page's own search box (query) fuzzy-filters this same
// data into one flat, ranked group; the sidebar's global search (SearchResults)
// does the same across every section, this is just scoped to this page.
Flickable {
    id: page

    property var categories: []
    property string query: ""

    readonly property var hits: query.length > 0 ? Fuzzy.rank(query, categories) : []
    readonly property bool empty: query.length > 0 && hits.length === 0

    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ScrollBar.vertical: ScrollBar {
        id: sb
        policy: ScrollBar.AsNeeded
        width: 7
        contentItem: Rectangle {
            implicitWidth: 4
            radius: Theme.radius
            color: Theme.line
            opacity: sb.pressed ? 0.9 : (sb.hovered ? 0.7 : 0.4)
            Behavior on opacity { NumberAnimation { duration: Theme.quick } }
        }
    }

    Column {
        id: col
        width: page.width - 10
        spacing: 30
        topPadding: 6
        bottomPadding: 18

        KeybindGroup {
            visible: page.query.length > 0 && page.hits.length > 0
            width: col.width
            name: "Results"
            binds: page.hits
            tagged: true
        }

        Repeater {
            model: page.query.length === 0 ? page.categories : []

            delegate: KeybindGroup {
                width: col.width
                name: modelData.name
                binds: modelData.binds
            }
        }

        Item {
            visible: page.empty
            width: col.width
            height: 200

            Column {
                anchors.centerIn: parent
                spacing: 14

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "search"
                    size: 28
                    weight: 1.5
                    tint: Theme.faint
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No shortcuts match “" + page.query + "”"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
            }
        }

        Text {
            visible: page.query.length === 0
            width: col.width
            wrapMode: Text.WordWrap
            text: "Read live from Ryoku's binds plus your Hub custom shortcuts. Binds added by hand in ~/.config/hypr/user.lua don't appear here and aren't conflict-checked, so add custom shortcuts in the Custom tab."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 12
            lineHeight: 1.3
        }
    }
}
