import QtQuick
import Quickshell
import Quickshell.Io

// Shared screen-vibrance logic for every root that has a display/appearance
// fader for it (the shell's display popout, the hub's Appearance > Comfort
// page). Bakes a saturation multiplier into a GLSL decoration:screen_shader
// and applies it via `hyprctl eval` calling `hl.config({ decoration = {
// screen_shader = ... } })` -- vibrance used to shell out to nvibrant, but
// that only talks to NVIDIA's proprietary driver via NV-CONTROL, dead on any
// other GPU. A screen_shader saturation multiply runs identically on any
// vendor since it's just a compositor-side GL pass, not a hardware vendor
// extension. Ryoku's Hyprland runs the Lua config parser (see
// ryoku-cmd-game-mode), so `hyprctl keyword` is rejected outright -- `hyprctl
// eval` is the runtime-override path that config also uses. Hyprland only
// reloads screen_shader when the *path* passed in changes -- rewriting the
// same file in place is a no-op until something re-applies a genuinely
// different path -- so writes alternate between two shader files rather than
// editing one in place.
//
// persisted vibrance % = source of truth: `restore()` loads and pushes it
// once at startup so the tint survives a reboot; every later `setVibrance`
// rewrites the shader file AND the state file. Each root's own process gets
// its own instance of this singleton (quickshell roots don't share a QML
// engine), so a root whose UI can go stale while another root changes
// vibrance externally (e.g. the hub's Comfort tab, while the shell's own
// fader is the thing actually being dragged) still needs to poll the state
// file itself on top of this -- this module only owns the write path and the
// one-time startup read, not cross-process live sync.
//
// Not a singleton itself -- pragma Singleton types can't be used as an
// inheritance base -- so this is a plain component, symlinked (alongside
// VibranceSingleton.qml as Vibrance.qml) into every root's Singletons/
// directory that needs it. Same trick as SpawnCore.qml/SpawnSingleton.qml:
// one real file, symlinked everywhere, so deploy.sh and the OS installer's
// deploy_dir (which both dereference symlinks on copy-out) keep every
// deployed root's copy identical without a shared import.
QtObject {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"
    readonly property string stateFile: root.stateDir + "/vibrance-value"

    property int vibrance: 50
    // alternates "a"/"b" so each write targets a fresh path (see header).
    property string _shaderSlot: "b"

    // load saved vibrance % and apply once -> tint survives reboot. singletons
    // init lazily, so something at startup has to actually touch this for the
    // restore to fire.
    function restore() {
        var raw = vibState.text();
        var v = parseInt((raw || "50").trim());
        root.vibrance = isNaN(v) ? 50 : v;
        if (raw && raw.trim().length)
            applyVibrance(root.vibrance);
    }

    // set vibrance to `pct`%: push to the screen shader, save to state.
    // `vibrance` tracks the last value.
    function setVibrance(pct) {
        root.vibrance = Math.round(pct);
        applyVibrance(pct);
        saveVibrance(pct);
    }

    // pct 0-100 maps to a saturation multiplier of 0.0-2.0, with 50% left as
    // an exact identity (source colors, untouched). screen_shader has no
    // live-uniform mechanism, so the multiplier gets baked into a fresh GLSL
    // file each call; that file is written to whichever of the two
    // alternating paths isn't currently active, then `hyprctl eval` points
    // decoration:screen_shader at it so Hyprland actually reloads (see header).
    function applyVibrance(pct) {
        var sat = (Math.max(0, Math.min(100, pct)) / 50).toFixed(3);
        root._shaderSlot = root._shaderSlot === "a" ? "b" : "a";
        var path = root.stateDir + "/vibrance-" + root._shaderSlot + ".glsl";
        var shader = "#version 300 es\n"
            + "precision highp float;\n\n"
            + "in vec2 v_texcoord;\n"
            + "uniform sampler2D tex;\n"
            + "out vec4 fragColor;\n\n"
            + "void main() {\n"
            + "    vec4 pixColor = texture(tex, v_texcoord);\n"
            + "    float luma = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));\n"
            + "    vec3 result = mix(vec3(luma), pixColor.rgb, " + sat + ");\n"
            + "    fragColor = vec4(clamp(result, 0.0, 1.0), pixColor.a);\n"
            + "}\n";
        Spawn.spawn(["sh", "-c",
            'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1" && hyprctl eval "hl.config({ decoration = { screen_shader = \\"$1\\" } })"',
            "_", path, shader]);
    }

    function saveVibrance(pct) {
        Spawn.spawn(["sh", "-c",
            'mkdir -p "$(dirname "$1")" && printf "%s\n" "$2" > "$1"',
            "_", root.stateFile, String(Math.round(pct))]);
    }

    // Re-reads the persisted value from disk into `vibrance`, WITHOUT
    // pushing it back to the compositor. Each root gets its own instance of
    // this singleton (quickshell roots don't share a QML engine), so a root
    // whose UI can go stale while another root changes vibrance (e.g. the
    // hub's Comfort tab, while the shell's own fader is what's actually
    // being dragged, or vice versa) needs to explicitly catch up -- callers
    // should invoke this whenever their vibrance UI becomes visible, the
    // same way Devices.probePanelBrightness() re-syncs the backlight fader
    // on every popout open. A raw Process (not the vibState FileView below)
    // because FileView.text() only re-reads once, at first access -- it
    // doesn't notice the file changing again afterward.
    function refresh() {
        _refreshProc.running = true;
    }

    property Process _refreshProc: Process {
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "_", root.stateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text.trim(), 10);
                if (!isNaN(v))
                    root.vibrance = v;
            }
        }
    }

    // QtObject has no default property (that's why this is a named property
    // holding an inline FileView rather than a declared child -- see
    // SpawnCore.qml's _procComp etc. for the same reason/pattern).
    property FileView vibState: FileView {
        path: root.stateFile
        blockLoading: true
        printErrors: false
    }
}
