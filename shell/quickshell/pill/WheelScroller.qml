import QtQuick

// wheel-to-Flickable bridge for layer-shell surfaces (native WheelHandler is
// unreliable there). a button-less MouseArea turns wheel notches into clamped
// contentY steps on the target Flickable.
MouseArea {
    id: root

    property real s: 1
    required property Flickable flick

    acceptedButtons: Qt.NoButton

    onWheel: function(event) {
        var max = Math.max(0, flick.contentHeight - flick.height);
        flick.contentY = Math.max(0, Math.min(max, flick.contentY - event.angleDelta.y / 120 * 36 * s));
        event.accepted = true;
    }
}
