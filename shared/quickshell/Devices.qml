pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// owns external monitor brightness (ddcutil) and the laptop panel backlight
// (brightnessctl). One real file, symlinked into every root's Singletons/
// that needs it (pill's mixer/DisplayPopout AND the Hub's Appearance page),
// same trick as SpawnCore.qml -- see that file's header for why a symlink
// instead of a copy. Screen vibrance used to live here too (as nvibrant, then
// as a Hyprland decoration:screen_shader GLSL saturation shader) but is now
// shared separately via Singletons/Vibrance.qml -- see VibranceCore.qml for
// the write-path details. ddc monitors come from `ddcutil detect` (one fader
// each). setvcp/getvcp wire format lives here so every caller agrees.
Singleton {
    id: root

    // ddc monitors from `ddcutil detect`: [{ bus, label }]. label = drm connector,
    // else just the i2c bus number.
    property var ddcMonitors: []

    function detect() {
        ddcDetect.running = true;
    }

    function setBrightness(bus, pct) {
        Spawn.spawn(["timeout", "3", "ddcutil", "setvcp", "10",
            String(pct), "--bus", bus, "--noverify"]);
    }

    // pull current brightness % out of a `ddcutil getvcp --brief` line. -1 = none.
    function parseBrightness(text) {
        var m = text.match(/C\s+(\d+)\s+/);
        return m ? parseInt(m[1], 10) : -1;
    }

    // --- laptop panel backlight (brightnessctl) -----------------------------
    // panelBrightness is the last known %, kept fresh for display. hypridle
    // dims/restores it independently of the shell (idle timeout, resume), so a
    // plain propertyChanged signal can't tell "the user just changed this" from
    // "we silently resynced to a value that moved while we weren't looking" --
    // panelBrightnessUserChanged exists so only the former flashes the OSD.
    property int panelBrightness: -1
    signal panelBrightnessUserChanged(int pct)

    function probePanelBrightness() {
        panelProbe.running = true;
    }

    // user-driven change (sidebar fader commit): apply to hardware, then flash.
    function setPanelBrightness(pct) {
        var clamped = Math.max(5, Math.min(100, Math.round(pct)));
        root.panelBrightness = clamped;
        Spawn.spawn(["brightnessctl", "set", clamped + "%"]);
        root.panelBrightnessUserChanged(clamped);
    }

    // user-driven change already applied elsewhere (a hardware key, via the
    // ryoku-shell daemon): just record it and flash, no hardware call.
    function reportPanelBrightness(pct) {
        root.panelBrightness = pct;
        root.panelBrightnessUserChanged(pct);
    }

    Process {
        id: panelProbe
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                var first = this.text.trim().split("\n")[0];
                var pct = parseInt((first.split(",")[3] || "").replace("%", ""), 10);
                if (!isNaN(pct))
                    root.panelBrightness = pct;
            }
        }
    }

    Process {
        id: ddcDetect
        command: ["ddcutil", "detect", "--brief"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var mons = [];
                var blocks = this.text.split(/\bDisplay \d+/);
                for (var i = 0; i < blocks.length; i++) {
                    var bus = /I2C bus:\s+\/dev\/i2c-(\d+)/.exec(blocks[i]);
                    var conn = /DRM connector:\s+card\d+-(\S+)/.exec(blocks[i]);
                    if (bus)
                        mons.push({ bus: bus[1], label: conn ? conn[1] : "BUS " + bus[1] });
                }
                root.ddcMonitors = mons;
            }
        }
    }
}
