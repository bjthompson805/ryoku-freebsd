pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Singletons"

// Recording: the quality knobs behind the bar's one-tap screen recorder. Writes
// ~/.config/ryoku/recording.json, read by ryoku-cmd-screenrecord (env vars still
// override). The under-the-hood card asks the recorder which encoder will
// actually run.
Item {
    id: page

    FileView {
        id: cfg
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/recording.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property int fps: 60
            property string quality: "very_high"
            property string codec: "h264"
            property string encoder: "gpu"
        }

        Component.onCompleted: if (!cfg.text()) cfg.writeAdapter()
    }

    // live readout: which encoder the recorder resolves for this machine.
    property string infoEncoder: ""
    Process {
        id: info
        command: [(Quickshell.env("HOME") || "") + "/.config/hypr/scripts/ryoku-cmd-screenrecord", "--info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.infoEncoder = JSON.parse(this.text).encoder || "";
                } catch (e) {}
            }
        }
    }
    Component.onCompleted: info.running = true

    readonly property var fpsOptions: [{ "key": "30", "label": "30 fps" }, { "key": "60", "label": "60 fps" }, { "key": "120", "label": "120 fps" }]
    readonly property var qualityOptions: [{ "key": "medium", "label": "Medium" }, { "key": "high", "label": "High" }, { "key": "very_high", "label": "Very high" }, { "key": "ultra", "label": "Ultra" }]
    readonly property var codecOptions: [{ "key": "h264", "label": "H.264 (most compatible)" }, { "key": "hevc", "label": "HEVC / H.265 (crisper)" }, { "key": "av1", "label": "AV1 (best, newer GPUs)" }]
    readonly property var encoderOptions: [{ "key": "gpu", "label": "GPU (VAAPI)" }, { "key": "cpu", "label": "CPU (software)" }]

    Flickable {
        anchors.fill: parent
        anchors.margins: 4
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Column {
            id: col
            width: parent.width
            spacing: 26

            Text {
                width: col.width
                wrapMode: Text.WordWrap
                text: "Ryoku records with wf-recorder, hardware-encoded on your GPU through VAAPI (it falls back to the CPU if the GPU encoder can't start). Start and stop from the bar's screen-capture Tools; these settings shape every recording. Files land in ~/Videos/Recordings."
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            SettingSection {
                width: col.width
                title: "QUALITY"
                description: "Higher framerate is smoother (120 gets closer to a high-refresh panel); higher quality and HEVC/AV1 are crisper but larger. Recordings are always constant framerate, so they play and edit correctly everywhere."

                Dropdown {
                    width: parent.width
                    label: "Framerate"
                    fieldWidth: 200
                    highlightId: "quality_framerate"
                    options: page.fpsOptions
                    current: String(adapter.fps)
                    onChosen: (k) => {
                        adapter.fps = parseInt(k);
                        cfg.writeAdapter();
                    }
                }
                Dropdown {
                    width: parent.width
                    label: "Quality"
                    fieldWidth: 200
                    highlightId: "quality_quality"
                    options: page.qualityOptions
                    current: adapter.quality
                    onChosen: (k) => {
                        adapter.quality = k;
                        cfg.writeAdapter();
                    }
                }
                Dropdown {
                    width: parent.width
                    label: "Codec"
                    fieldWidth: 200
                    highlightId: "quality_codec"
                    options: page.codecOptions
                    current: adapter.codec
                    onChosen: (k) => {
                        adapter.codec = k;
                        cfg.writeAdapter();
                    }
                }
            }

            SettingSection {
                width: col.width
                title: "ENCODER"
                description: "GPU encoding is fast and barely touches your CPU. CPU is a fallback if the GPU encoder misbehaves."

                Dropdown {
                    width: parent.width
                    label: "Encoder"
                    fieldWidth: 200
                    highlightId: "encoder_encoder"
                    options: page.encoderOptions
                    current: adapter.encoder
                    onChosen: (k) => {
                        adapter.encoder = k;
                        cfg.writeAdapter();
                    }
                }
            }

            SettingSection {
                width: col.width
                title: "UNDER THE HOOD"
                highlightId: "under_the_hood"
                description: "What the recorder resolves for this machine right now."

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: page.infoEncoder === "" ? "Detecting\u2026" : ("Recorder   wf-recorder\nEncoder    " + page.infoEncoder + "\nContainer  MP4  \u00b7  " + adapter.fps + "fps CFR  \u00b7  " + adapter.codec + "  \u00b7  " + adapter.quality)
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 12
                    lineHeight: 1.5
                }
            }
        }
    }
}
