pragma Singleton
import QtQuick
import Quickshell

// Motion budget, matched to the shell tokens so the switcher's open/close and
// selection glides read like the rest of the desktop (docs/ui-ux.md: consistent
// durations, OutCubic/OutExpo, no bespoke curves).
Singleton {
    readonly property int fast:     140
    readonly property int standard: 300
    readonly property int window:   240
    readonly property int highlight: 90
    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeExpo:     Easing.OutExpo
}
