import QtQuick
import "Singletons"

// The red-sun disc, the website's single vermillion circle behind a subject.
// A soft radial glow that fades to nothing, so it reads as a sun on the dark
// canvas, not a flat dot. Use large and low-opacity as a backdrop motif.
Item {
    id: disc
    property real size: 300
    property color core: Theme.sun
    property real intensity: 0.9      // core alpha

    implicitWidth: size
    implicitHeight: size

    Canvas {
        id: cv
        anchors.fill: parent
        property color c: disc.core
        property real k: disc.intensity
        onCChanged: requestPaint()
        onKChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            function rgba(col, a) {
                return "rgba(" + Math.round(col.r * 255) + "," + Math.round(col.g * 255) + "," + Math.round(col.b * 255) + "," + a + ")";
            }
            var r = Math.min(width, height) / 2;
            var g = ctx.createRadialGradient(width / 2, height / 2, r * 0.15, width / 2, height / 2, r);
            g.addColorStop(0.0, rgba(cv.c, cv.k));
            g.addColorStop(0.62, rgba(cv.c, cv.k * 0.85));
            g.addColorStop(0.78, rgba(cv.c, cv.k * 0.32));
            g.addColorStop(1.0, rgba(cv.c, 0));
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2);
            ctx.fill();
        }
    }
}
