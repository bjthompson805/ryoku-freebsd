pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Singletons"

// precise numeric control: label + steppers with manual entry. for exact
// values where the number matters (cores, RAM, disk, sizes, radii, gaps).
// hold a stepper to repeat. reports modified(value).
Item {
    id: root

    property string label: ""
    property string unit: ""
    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 1
    property int decimals: 0
    // size multiplier for a compact host (the pill's popouts pass their own `s`);
    // 1 is the Hub's native size. not `scale`: Item already has that transform.
    property real sizeScale: 1

    // Tab/Shift+Tab chaining: a bare TextInput has no built-in focus-chain
    // participation (unlike Controls' TextField), so a consumer stacking
    // several NumberFields wires them explicitly -- set tabTo/backtabTo to a
    // sibling field's focusTarget.
    property Item tabTo: null
    property Item backtabTo: null
    readonly property alias focusTarget: input

    // debounce a stepper hold-repeat's commits instead of firing modified()
    // per click: for a consumer whose commit is a slow round-trip (a CLI
    // subprocess, say) rather than an in-memory draft edit, per-click commits
    // both flood it and snap the display back mid-edit. Off by default (an
    // immediate commit is the snappier choice when nothing costly is behind
    // it); a consumer with a slow commit sets this true.
    property bool debounce: false

    signal modified(real value)

    implicitWidth: 320 * sizeScale
    implicitHeight: 38 * sizeScale

    function clampq(v) {
        var c = Math.max(root.from, Math.min(root.to, v));
        var p = Math.pow(10, root.decimals);
        return Math.round(c * p) / p;
    }
    // a typed edit only commits on blur/Enter -- a consumer that reads this
    // field's bound value from a separate button (Create, Grow/Set) needs to
    // flush a pending typed edit first, or a value typed and then acted on
    // without ever blurring the field is silently lost. Call before reading.
    // Rebinds rather than assigns the text: the blur that would restore the
    // binding never comes from a button, so an assignment here left the
    // display frozen and made the steppers look dead from then on.
    function commit() {
        var v = parseFloat(input.text);
        if (!isNaN(v))
            root.modified(root.clampq(v));
        input.text = Qt.binding(() => root.shown.toFixed(root.decimals));
    }
    // when debounced, steppers accumulate locally and commit once the hand
    // settles (350ms); otherwise every bump commits immediately.
    property real pending: NaN
    readonly property real shown: isNaN(pending) ? value : pending
    function bump(dir) {
        var v = root.clampq((isNaN(root.pending) ? root.value : root.pending) + dir * root.step);
        if (root.debounce) {
            root.pending = v;
            settle.restart();
        } else {
            root.modified(v);
        }
    }
    Timer {
        id: settle
        interval: 350
        onTriggered: {
            if (!isNaN(root.pending) && root.pending !== root.value)
                root.modified(root.pending);
            // don't clear pending here: for a field whose value comes from
            // polled server state (not a local mirror the field controls
            // itself), value won't reflect this commit until the backend
            // round-trip finishes and the next poll picks it up. Clearing
            // eagerly would flash the display back to the stale old value in
            // that gap. Keep showing the optimistic pending number until
            // value itself catches up to confirm it (below), instead.
        }
    }
    onValueChanged: if (!isNaN(pending) && value === pending) pending = NaN;

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - field.width - 14 * root.sizeScale
        elide: Text.ElideRight
        text: root.label
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 14 * root.sizeScale
        font.weight: Font.Medium
    }

    Row {
        id: field
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7 * root.sizeScale

        component StepKey: Rectangle {
            id: key
            property string glyph: "+"
            property int dir: 1
            // a press held past the repeat interval fires the Timer once while
            // still pressed, then TapHandler.onTapped fires again on release --
            // without this guard that's a double bump (e.g. two steps at once).
            property bool repeated: false
            width: 30 * root.sizeScale
            height: 30 * root.sizeScale
            radius: Theme.radius
            color: tap.pressed ? Theme.keyTop : (hov.hovered ? Theme.surface : Theme.surfaceLo)
            border.width: 1
            border.color: hov.hovered ? Theme.ember : Theme.line
            Behavior on color { ColorAnimation { duration: Theme.quick } }
            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

            Text {
                anchors.centerIn: parent
                text: key.glyph
                color: hov.hovered ? Theme.bright : Theme.subtle
                font.family: Theme.mono
                font.pixelSize: (key.glyph === "−" ? 17 : 15) * root.sizeScale
                font.weight: Font.DemiBold
            }

            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: tap
                onPressedChanged: if (tap.pressed) key.repeated = false
                onTapped: if (!key.repeated) root.bump(key.dir)
            }
            Timer {
                interval: 90; repeat: true
                running: tap.pressed
                triggeredOnStart: false
                onTriggered: { root.bump(key.dir); key.repeated = true; }
            }
        }

        StepKey { anchors.verticalCenter: parent.verticalCenter; glyph: "−"; dir: -1 }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 86 * root.sizeScale
            height: 30 * root.sizeScale
            radius: Theme.radius
            color: Theme.surfaceLo
            border.width: 1
            border.color: input.activeFocus ? Theme.ember : Theme.line
            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

            TextInput {
                id: input
                anchors.fill: parent
                anchors.rightMargin: root.unit !== "" ? 24 * root.sizeScale : 0
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                KeyNavigation.tab: root.tabTo
                KeyNavigation.backtab: root.backtabTo
                text: root.shown.toFixed(root.decimals)
                color: Theme.bright
                font.family: Theme.mono
                font.pixelSize: 14 * root.sizeScale
                font.weight: Font.DemiBold
                selectByMouse: true
                clip: true
                validator: DoubleValidator {
                    bottom: root.from
                    top: root.to
                    decimals: root.decimals
                    notation: DoubleValidator.StandardNotation
                }
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                onActiveFocusChanged: {
                    if (activeFocus)
                        selectAll();
                    else
                        text = Qt.binding(() => root.shown.toFixed(root.decimals));
                }
                onEditingFinished: {
                    var v = parseFloat(text);
                    if (!isNaN(v)) {
                        var q = root.clampq(v);
                        root.modified(q);
                        text = q.toFixed(root.decimals);
                    }
                }
            }

            Text {
                visible: root.unit !== ""
                anchors.right: parent.right
                anchors.rightMargin: 9 * root.sizeScale
                anchors.verticalCenter: parent.verticalCenter
                text: root.unit
                color: Theme.faint
                font.family: Theme.mono
                font.pixelSize: 11 * root.sizeScale
                font.weight: Font.Medium
            }
        }

        StepKey { anchors.verticalCenter: parent.verticalCenter; glyph: "+"; dir: 1 }
    }
}
