pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Caps/Num Lock state off Hyprland's main keyboard. FreeBSD has no LED
// classdevs to poll, so the lock-key binds (modules/binds.lua) run
// `ryoku-shell lockkeys` on release and the daemon reports the fresh state
// here; one read at startup seeds it so the first report flashes only a real
// change. Hyprland tracks no Scroll Lock.
Singleton {
    id: root

    property bool capsLock: false
    property bool numLock: false

    function report(caps, num) {
        root.capsLock = caps;
        root.numLock = num;
    }

    Process {
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var main = JSON.parse(this.text).keyboards.filter(function (k) { return k.main; })[0];
                    if (main)
                        root.report(main.capsLock, main.numLock);
                } catch (e) {}
            }
        }
    }
}
