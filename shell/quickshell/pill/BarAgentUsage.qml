pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// Selected-agent rate-limit readout for the bar: a sparkle glyph + the
// current provider's primary-window percentage, off AgentUsage.
// warn-tinted past 80%, same threshold BarStats/SysStats use. icon/text sized
// to match the battery readout in BarStatus (status.glyphPx + 1, 9.5). keeps
// the poller awake while shown. click opens the usage popout.
Item {
    id: agentUsage

    property real s: 1

    signal requestPopout(string name, real center)

    readonly property bool warn: AgentUsage.sessionPercent > 80

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Component.onCompleted: AgentUsage.active = true
    Component.onDestruction: AgentUsage.active = false

    function open(item) {
        const p = item.mapToItem(null, item.width / 2, item.height / 2);
        agentUsage.requestPopout("agentusage", p.x);
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 3 * agentUsage.s

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: "auto_awesome"
            fill: 1
            color: agentUsage.warn ? Theme.vermLit : Theme.subtle
            font.pixelSize: 15 * agentUsage.s
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: AgentUsage.available ? AgentUsage.sessionPercent + "%" : "–"
            color: agentUsage.warn ? Theme.vermLit : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9.5 * agentUsage.s
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: agentUsage.open(agentUsage)
    }
}
