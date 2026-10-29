pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// power profile for the battery popout's tabs and the bar's battery badge,
// backed by powerd(8) in place of power-profiles-daemon. each profile is a
// powerd_flags line in rc.conf, so the choice survives a reboot; reading it
// needs no root, setting it goes through ryoku-priv, which restarts powerd.
// a hand-written powerd_flags matches no profile and leaves no tab lit.
Singleton {
    id: root

    // "saver" | "balanced" | "performance" | "" (powerd off or custom flags)
    property string profile: ""

    readonly property var flags: ({
        saver: "-a adaptive -b minimum",
        balanced: "",
        performance: "-a maximum -b hiadaptive"
    })

    function refresh() {
        readProc.running = true;
    }

    // flips at once; the re-read after ryoku-priv returns corrects it if the
    // change did not take.
    function set(p) {
        if (!(p in root.flags) || setProc.running)
            return;
        root.profile = p;
        setProc.command = ["sh", "-c",
            'if command -v doas >/dev/null 2>&1; then doas -n /usr/local/libexec/ryoku-priv power-profile "$1"; '
            + 'else sudo -n /usr/local/libexec/ryoku-priv power-profile "$1"; fi',
            "sh", p];
        setProc.running = true;
    }

    Process {
        id: readProc
        running: true
        command: ["sh", "-c", "echo \"$(sysrc -n powerd_enable 2>/dev/null)\"; sysrc -n powerd_flags 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                var on = /^yes$/i.test((lines[0] || "").trim());
                var f = (lines[1] || "").trim().replace(/\s+/g, " ");
                var match = "";
                for (var p in root.flags) {
                    if (root.flags[p] === f)
                        match = p;
                }
                root.profile = on ? match : "";
            }
        }
    }

    Process {
        id: setProc
        onExited: root.refresh()
    }
}
