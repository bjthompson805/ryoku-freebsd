import QtQuick
import "Singletons"

// Keep Awake's optional off-switches, set in its details card
// (DeckModeInfo.qml): turn it back off after the chosen number of hours, or when
// the battery runs low. lives with the shell, not the deck, so it keeps
// counting while the sidebar is closed.
Item {
    id: root

    readonly property bool lowStop: Flags.keepAwake && Flags.keepAwakeLowBattery && Battery.low && Battery.discharging
    onLowStopChanged: if (root.lowStop) root.release("The battery is low")

    function release(reason) {
        Flags.keepAwake = false;
        Spawn.spawn(["notify-send", "-a", "Ryoku", "Keep Awake turned off", reason]);
    }

    // keepAwakeSince is persisted, so the limit holds across a shell restart.
    Timer {
        interval: 30000
        running: Flags.keepAwake && Flags.keepAwakeHours > 0 && Flags.keepAwakeSince > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (Date.now() - Flags.keepAwakeSince >= Flags.keepAwakeHours * 3600000)
                root.release("It reached its " + Flags.keepAwakeHours + "h limit");
        }
    }
}
