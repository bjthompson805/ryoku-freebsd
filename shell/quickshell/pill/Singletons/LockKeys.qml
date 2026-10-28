pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Caps/Num/Scroll Lock state, read straight from the kernel's LED classdevs
// (/sys/class/leds/*::capslock etc.) rather than hyprctl devices -- hyprctl
// only reports caps/num (no scroll lock field at all) and only on request.
// Every keyboard's LED mirrors the same global toggle (checked against a
// real laptop keyboard plus two HID "keyboard" interfaces a gaming mouse
// exposes for its macro keys -- all three agreed in every state), so the
// first classdev found for each lock is representative; no need to fan out
// to every one.
//
// This polls (150ms) rather than using FileView's inotify-backed
// watchChanges: verified live that watchChanges never fires here. The LED
// core only calls sysfs_notify() on a userspace write() to the brightness
// file; a keyboard's own driver flips the value internally in response to
// the key press (led_set_brightness, no notify), so the value is always
// correct on read but nothing wakes an inotify watcher when it changes.
// A tiny sysfs read every 150ms is negligible cost either way.
Singleton {
    id: root

    readonly property bool capsLock: capsFile.path.length > 0 && capsFile.text().trim() === "1"
    readonly property bool numLock: numFile.path.length > 0 && numFile.text().trim() === "1"
    readonly property bool scrollLock: scrollFile.path.length > 0 && scrollFile.text().trim() === "1"

    property string capsPath: ""
    property string numPath: ""
    property string scrollPath: ""

    Process {
        running: true
        command: ["sh", "-c",
            "for k in capslock numlock scrolllock; do " +
            "p=$(ls -d /sys/class/leds/*::\"$k\" 2>/dev/null | head -1); " +
            "printf '%s=%s\\n' \"$k\" \"$p\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var eq = lines[i].indexOf("=");
                    if (eq < 0)
                        continue;
                    var key = lines[i].slice(0, eq);
                    var val = lines[i].slice(eq + 1);
                    if (key === "capslock")
                        root.capsPath = val;
                    else if (key === "numlock")
                        root.numPath = val;
                    else if (key === "scrolllock")
                        root.scrollPath = val;
                }
            }
        }
    }

    FileView {
        id: capsFile
        path: root.capsPath.length > 0 ? root.capsPath + "/brightness" : ""
        printErrors: false
    }

    FileView {
        id: numFile
        path: root.numPath.length > 0 ? root.numPath + "/brightness" : ""
        printErrors: false
    }

    FileView {
        id: scrollFile
        path: root.scrollPath.length > 0 ? root.scrollPath + "/brightness" : ""
        printErrors: false
    }

    Timer {
        interval: 150
        repeat: true
        running: capsFile.path.length > 0 || numFile.path.length > 0 || scrollFile.path.length > 0
        onTriggered: {
            if (capsFile.path.length > 0)
                capsFile.reload();
            if (numFile.path.length > 0)
                numFile.reload();
            if (scrollFile.path.length > 0)
                scrollFile.reload();
        }
    }
}
