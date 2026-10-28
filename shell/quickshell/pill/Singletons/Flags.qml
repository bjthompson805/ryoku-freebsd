pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// session flags in a little JSON file, watched for outside changes so every
// daemon (pill, launcher) shares one DND / Keep-Awake / Game-Mode state. no
// extra notif server or idle inhibitor. flip in one surface, the rest catch
// up on the next file event, and it survives a daemon restart.
// keepAwakeSince = epoch ms Keep-Awake last turned on (0 when off), so every
// surface reads the same "how long" elapsed.
// the keepAwake* / gameMode* option flags are the deck's mode panels
// (DeckModeInfo.qml). ryoku-cmd-caffeine and ryoku-cmd-game-mode read them
// straight from this file, so a launcher toggle or a login re-apply honors them
// too; the defaults here are the full, original behavior.
Singleton {
    id: root

    property alias dnd: adapter.dnd
    property alias keepAwake: adapter.keepAwake
    property alias keepAwakeSince: adapter.keepAwakeSince
    property alias keepAwakeScreen: adapter.keepAwakeScreen
    property alias keepAwakeHours: adapter.keepAwakeHours
    property alias keepAwakeLowBattery: adapter.keepAwakeLowBattery
    property alias gameMode: adapter.gameMode
    property alias gameModeVisuals: adapter.gameModeVisuals
    property alias gameModeTearing: adapter.gameModeTearing
    property alias gameModeWifi: adapter.gameModeWifi
    property alias gameModeDnd: adapter.gameModeDnd
    property alias lidSleep: adapter.lidSleep

    // stamp when Keep-Awake turns on, clear when off, so no toggle site has
    // to track it. guarded so a file reload (stamp already set) doesn't
    // reset the running clock.
    onKeepAwakeChanged: {
        if (keepAwake && !adapter.keepAwakeSince)
            adapter.keepAwakeSince = Date.now();
        else if (!keepAwake)
            adapter.keepAwakeSince = 0;
    }

    // Game Mode's Do Not Disturb is derived, never written into `dnd`: that stays
    // the user's own setting, so leaving Game Mode (or dropping the option
    // mid-game) has nothing to restore. read this, not `dnd`, for "are
    // notifications held back".
    readonly property bool dndActive: dnd || (gameMode && gameModeDnd)

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku/flags.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        // atomic writes (temp + rename): a SIGTERM during a shell refresh, or
        // two surfaces writing at once, can't leave a half-written file that
        // fails parse on next load and silently drops Keep-Awake back to off.
        atomicWrites: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: adapter
            property bool dnd: false
            property bool keepAwake: false
            property real keepAwakeSince: 0
            property bool keepAwakeScreen: true
            property real keepAwakeHours: 0
            property bool keepAwakeLowBattery: false
            property bool gameMode: false
            property bool gameModeVisuals: true
            property bool gameModeTearing: true
            property bool gameModeWifi: true
            property bool gameModeDnd: true
            // true = logind's own default (lid close suspends). false = the
            // Lid Sleep quick-toggle's override: ryoku-cmd-lid-sleep blocks
            // logind's handle-lid-switch and just dpms the screen off/on
            // instead, see shell.qml's syncLidSleep.
            property bool lidSleep: true
        }
    }

    // seed only on a real first run (no content yet). guard on the loaded
    // text, not file.loaded, so a slow/failed load never overwrites a present
    // file from defaults and wipes Keep-Awake across a refresh.
    Component.onCompleted: if (!file.text()) file.writeAdapter();
}
