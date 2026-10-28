import QtQuick
import "Singletons"

// Updates section header. ember rule + eyebrow, current -> latest bump line,
// meta line under it. editorial, not a boxed banner.
Item {
    id: status

    implicitHeight: textCol.implicitHeight

    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.top: parent.top
        width: 3
        height: textCol.implicitHeight
        radius: Theme.radius
        color: Theme.ember
        opacity: Updates.available ? 0.9 : 0.3
    }

    Column {
        id: textCol
        anchors.left: bar.right
        anchors.leftMargin: 18
        anchors.top: parent.top
        spacing: 9

        Text {
            text: Updates.available ? "UPDATE AVAILABLE" : "UP TO DATE"
            color: Theme.ember
            font.family: Theme.mono
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 2
        }

        Row {
            spacing: 13

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Updates.currentVersion
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: 25
                font.weight: Font.Medium
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Updates.available && Updates.latestVersion !== "" && Updates.latestVersion !== Updates.currentVersion
                text: "\u2192"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 22
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Updates.available && Updates.latestVersion !== "" && Updates.latestVersion !== Updates.currentVersion
                text: Updates.latestVersion
                color: Theme.bright
                font.family: Theme.mono
                font.pixelSize: 25
                font.weight: Font.DemiBold
            }
        }

        Text {
            text: Updates.available
                ? (Updates.behind + " update" + (Updates.behind === 1 ? "" : "s") + " pending  \u00b7  checked " + Updates.checkedAgo)
                : ("on " + Updates.branch + "  \u00b7  checked " + Updates.checkedAgo)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
}
