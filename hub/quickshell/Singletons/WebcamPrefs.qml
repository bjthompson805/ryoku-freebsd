pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Per-machine webcam calibration, read back by the shell's ryoku-cmd-webcam
// bridge (via jq) -- not something libcamera can infer itself. Some MIPI
// sensors (this repo's own dev machine included) are mounted physically
// upside-down in their laptop chassis with no rotation entry in libcamera's
// sensor database, so the bridge pipeline needs to know to flip the feed.
// Persists to ~/.config/ryoku/webcam.json, unrelated to camera.json (the
// shell's self-view Mirror bubble, a purely cosmetic on-screen flip).
Singleton {
    id: root

    property bool flip180: false

    readonly property string cfgPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/webcam.json"
    property bool loaded: false

    function save() {
        const j = JSON.stringify({
            flip180: root.flip180
        });
        Spawn.spawn(["sh", "-c",
            "mkdir -p \"$(dirname '" + root.cfgPath + "')\"; "
            + "printf '%s' '" + j + "' > '" + root.cfgPath + ".tmp'; "
            + "mv '" + root.cfgPath + ".tmp' '" + root.cfgPath + "'"]);
    }

    onFlip180Changed: if (root.loaded) root.save()

    FileView {
        id: cfg
        path: root.cfgPath
        blockLoading: true
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                const j = JSON.parse(cfg.text() || "{}");
                if (typeof j.flip180 === "boolean")
                    root.flip180 = j.flip180;
            } catch (e) {}
            root.loaded = true;
        }
        // A file that doesn't exist yet (first run, before any save() has
        // ever happened) fires this instead of onLoaded -- confirmed via a
        // standalone qs test, since FileView never calls onLoaded for ENOENT.
        // Without this, `loaded` would stay false forever, so the very first
        // toggle would never persist (onFlip180Changed is gated on `loaded`).
        onLoadFailed: (err) => {
            root.loaded = true;
        }
    }
}
