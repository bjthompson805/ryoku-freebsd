import QtQuick
import "Singletons"

// hold-to-confirm heat for destructive gestures (power tiles, wallpaper trash,
// clipboard wipe). `hold` fills 0->1 over Motion.heat while pressed, fires
// `confirmed` when full, drains on release/exit. release before full = drain;
// release shorter than `tapThreshold` ALSO fires `tapped` for sites whose
// hitbox doubles as a click target. `fired` keeps a release just after a
// confirm from being misread as a tap while the drain is still running.
Item {
    id: root

    visible: false

    property real hold: 0
    readonly property bool holding: hold > 0.001
    property real tapThreshold: 0
    property bool fired: false

    signal confirmed()
    signal tapped()

    function press() {
        fired = false;
        drain.stop();
        fill.restart();
    }

    function release() {
        fill.stop();
        if (fired || hold >= 1)
            return;
        if (tapThreshold > 0 && hold < tapThreshold)
            tapped();
        drain.restart();
    }

    function cancel() {
        fill.stop();
        drain.restart();
    }

    NumberAnimation {
        id: fill
        target: root
        property: "hold"
        from: 0
        to: 1
        duration: Motion.heat
        onFinished: {
            root.fired = true;
            root.confirmed();
            drain.restart();
        }
    }

    NumberAnimation {
        id: drain
        target: root
        property: "hold"
        to: 0
        duration: 180
    }
}
