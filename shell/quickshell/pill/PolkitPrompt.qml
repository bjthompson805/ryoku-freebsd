pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import "Singletons"

// In-shell polkit authentication agent: a themed password prompt that names
// the exact privileged command being authorized, replacing the stock
// hyprpolkitagent binary. Registering here means Hyprland no longer has to
// race hyprpolkitagent.service's WAYLAND_DISPLAY condition on login (see the
// autostart.lua comment this replaced) -- the agent just comes up with the
// shell.
//
// Its own always-mapped PanelWindow (like shell.qml's kbBounceWin), not a
// PillSurface: a polkit request can land while any app -- not just the pill
// -- has focus, so it can't ride the island's morph lifecycle. Visuals
// borrow KeyringSurface's password field and StashTaskOverlay's confirm-card
// shape. No fingerprint mode: Ryoku has no pam_fprintd / lid-state plumbing
// to drive one (Omarchy's version leans on omarchy-hw-laptop-closed, which
// doesn't exist here).
Item {
    id: root

    readonly property real s: Math.max(0.7, Math.min(1.6, Config.fontScale))
    readonly property bool dialogVisible: agent.isActive
    property bool submitted: false
    property bool errorFlash: false
    property int shakeOffset: 0

    function authorizationLabel(message) {
        var text = String(message || "Authentication is required");
        var match = text.match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i);
        return match ? ("Authorize running '" + match[1] + "'") : text;
    }

    function submit() {
        var flow = agent.flow;
        if (!flow || !flow.isResponseRequired) return;
        root.submitted = true;
        root.errorFlash = false;
        flow.submit(passwordField.text);
        passwordField.text = "";
    }

    function cancel() {
        var flow = agent.flow;
        passwordField.text = "";
        root.submitted = false;
        if (flow) flow.cancelAuthenticationRequest();
    }

    function refocus() {
        if (root.dialogVisible) passwordField.forceActiveFocus();
    }

    PolkitAgent {
        id: agent
        path: "/org/ryoku/PolkitAgent"

        onAuthenticationRequestStarted: {
            root.submitted = false;
            root.errorFlash = false;
            passwordField.text = "";
            Qt.callLater(root.refocus);
        }
        onIsRegisteredChanged: {
            if (!isRegistered)
                console.warn("ryoku polkit agent is not registered; another agent may be running");
        }
    }

    Connections {
        target: agent.flow

        function onIsResponseRequiredChanged() {
            if (!agent.flow || !agent.flow.isResponseRequired) passwordField.text = "";
            Qt.callLater(root.refocus);
        }

        function onAuthenticationFailed() {
            root.submitted = false;
            root.errorFlash = true;
            passwordField.text = "";
            errorTimer.restart();
            shakeAnim.restart();
            Qt.callLater(root.refocus);
        }
    }

    Timer {
        id: errorTimer
        interval: 1200
        onTriggered: root.errorFlash = false
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
    }

    PanelWindow {
        id: win
        visible: root.dialogVisible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "ryoku-polkit"

        anchors { top: true; bottom: true; left: true; right: true }

        Rectangle { anchors.fill: parent; color: Theme.shadow }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) {
                    root.cancel();
                    event.accepted = true;
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.refocus() }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.shakeOffset
            width: 320 * root.s
            height: col.implicitHeight + 44 * root.s
            radius: Theme.radius
            color: Qt.alpha(Theme.cardTop, 0.98)
            border.width: 1
            border.color: root.errorFlash ? Qt.alpha(Theme.vermLit, 0.6) : Theme.border
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

            MouseArea { anchors.fill: parent }

            Column {
                id: col
                anchors.centerIn: parent
                width: parent.width - 44 * root.s
                spacing: 13 * root.s

                Row {
                    spacing: 10 * root.s
                    width: parent.width

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32 * root.s
                        height: 32 * root.s
                        radius: width / 2
                        color: Qt.alpha(Theme.brand, 0.14)
                        border.width: 1
                        border.color: Qt.alpha(Theme.brand, 0.40)

                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 17 * root.s
                            height: 17 * root.s
                            name: "lock-round"
                            color: root.errorFlash ? Theme.vermLit : Theme.brand
                            stroke: 1.8
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 42 * root.s
                        text: root.authorizationLabel(agent.flow ? agent.flow.message : "")
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                    }
                }

                Text {
                    width: parent.width
                    visible: agent.flow && agent.flow.supplementaryMessage.length > 0
                    text: agent.flow ? agent.flow.supplementaryMessage : ""
                    color: agent.flow && agent.flow.supplementaryIsError ? Theme.vermLit : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    width: parent.width
                    height: 36 * root.s
                    radius: Theme.radius
                    color: Theme.tileBg
                    border.width: 1
                    border.color: passwordField.activeFocus ? Theme.frameBorder : Theme.border
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                    visible: agent.flow ? agent.flow.isResponseRequired : false

                    TextInput {
                        id: passwordField
                        anchors.fill: parent
                        anchors.leftMargin: 12 * root.s
                        anchors.rightMargin: 12 * root.s
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: root.errorFlash ? Theme.vermLit : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        echoMode: (agent.flow && agent.flow.responseVisible) ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        selectionColor: Qt.alpha(Theme.brand, 0.45)
                        readOnly: root.submitted
                        enabled: root.dialogVisible
                        onAccepted: root.submit()
                        Keys.onPressed: function (event) {
                            if (event.key === Qt.Key_Escape) {
                                root.cancel();
                                event.accepted = true;
                            }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: agent.flow && agent.flow.inputPrompt.length > 0 ? agent.flow.inputPrompt : "Password"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        visible: passwordField.text.length === 0
                    }
                }

                Text {
                    width: parent.width
                    visible: root.errorFlash
                    text: "Authentication failed, try again"
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                }

                Row {
                    width: parent.width
                    spacing: 9 * root.s
                    layoutDirection: Qt.RightToLeft

                    Rectangle {
                        width: (parent.width - parent.spacing) / 2
                        height: 32 * root.s
                        radius: Theme.radius
                        color: submitArea.containsMouse ? Theme.vermLit : Theme.brand
                        opacity: root.submitted ? 0.6 : 1
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            anchors.centerIn: parent
                            text: root.submitted ? "Checking…" : "Authenticate"
                            color: "#fdeee6"
                            font.family: Theme.font
                            font.pixelSize: 12 * root.s
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: submitArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.submitted
                            onClicked: root.submit()
                        }
                    }

                    Rectangle {
                        width: (parent.width - parent.spacing) / 2
                        height: 32 * root.s
                        radius: Theme.radius
                        color: cancelArea.containsMouse ? Theme.frameBg : Theme.tileBg
                        border.width: 1
                        border.color: Theme.border
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 12 * root.s
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: cancelArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancel()
                        }
                    }
                }
            }
        }
    }
}
