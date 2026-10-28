pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

// shared ambient frame for showcase pages so they read as one family: soft glow
// blooms, faint spec grid, edge vignette, editorial corner ticks. decorative.
// drop it behind page content with `anchors.fill: parent`. used by ProfilePage,
// AddonsPage and StorePage.
Item {
    id: backdrop

    // canvas-safe "rgba(...)" from a Theme colour + alpha.
    function rgba(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")";
    }

    // ambient glow blooms. warmth low-left, cream wash top-right, deep at the
    // foot.
    Canvas {
        anchors.fill: parent
        property string cream: backdrop.rgba(Theme.cream, 0.06)
        property string warm: backdrop.rgba(Theme.brand, 0.10)
        property string deep: backdrop.rgba(Theme.ember, 0.05)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            function radial(cx, cy, r, color) {
                let g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
                g.addColorStop(0, color);
                g.addColorStop(1, "rgba(0,0,0,0)");
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, width, height);
            }
            ctx.globalCompositeOperation = "screen";
            radial(width * 0.29, height * 0.46, height * 0.72, warm);
            radial(width * 0.74, height * 0.30, width * 0.42, cream);
            radial(width * 0.55, height * 1.03, width * 0.55, deep);
        }
    }

    // faint spec grid. quiet technical texture.
    Canvas {
        anchors.fill: parent
        property string tint: backdrop.rgba(Theme.cream, 0.022)
        readonly property real step: 34
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.strokeStyle = tint;
            ctx.lineWidth = 1;
            for (let x = 0; x <= width; x += step) {
                ctx.beginPath();
                ctx.moveTo(x, 0);
                ctx.lineTo(x, height);
                ctx.stroke();
            }
            for (let y = 0; y <= height; y += step) {
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(width, y);
                ctx.stroke();
            }
        }
    }

    // vignette. darken the edges a touch so content holds the eye.
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            let r = Math.max(width, height) * 0.80;
            let g = ctx.createRadialGradient(width / 2, height * 0.46, r * 0.36, width / 2, height * 0.46, r);
            g.addColorStop(0, "rgba(0,0,0,0)");
            g.addColorStop(1, "rgba(0,0,0,0.22)");
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, width, height);
        }
    }

    // corner ticks: a light editorial frame around the page.
    Repeater {
        model: 4
        Item {
            id: tick
            required property int index
            readonly property bool onLeft: index % 2 === 0
            readonly property bool onTop: index < 2
            readonly property real len: 20
            width: len
            height: len
            anchors.left: onLeft ? parent.left : undefined
            anchors.right: onLeft ? undefined : parent.right
            anchors.top: onTop ? parent.top : undefined
            anchors.bottom: onTop ? undefined : parent.bottom
            anchors.margins: 10

            Rectangle {
                width: tick.len
                height: 1.5
                color: Theme.line
                anchors.top: tick.onTop ? parent.top : undefined
                anchors.bottom: tick.onTop ? undefined : parent.bottom
                anchors.left: tick.onLeft ? parent.left : undefined
                anchors.right: tick.onLeft ? undefined : parent.right
            }
            Rectangle {
                width: 1.5
                height: tick.len
                color: Theme.line
                anchors.top: tick.onTop ? parent.top : undefined
                anchors.bottom: tick.onTop ? undefined : parent.bottom
                anchors.left: tick.onLeft ? parent.left : undefined
                anchors.right: tick.onLeft ? undefined : parent.right
            }
        }
    }
}
