pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "Singletons"

// custom Hyprland window rules layered over the ones Ryoku ships, edited as a
// list through the shared HyprStore. each row matches by class and/or title
// and applies one action (a few carry a typed value). list edits aren't
// previewed live -- they apply on Save, so add/edit/delete rebuild the draft
// array and go through store.editList with a fresh reference.
Item {
    id: page

    HyprStore { id: store }

    readonly property var actionOptions: [
        { "key": "float", "label": "Float" },
        { "key": "tile", "label": "Tile" },
        { "key": "pin", "label": "Pin" },
        { "key": "fullscreen", "label": "Fullscreen" },
        { "key": "maximize", "label": "Maximize" },
        { "key": "center", "label": "Centre" },
        { "key": "size", "label": "Size (WxH)" },
        { "key": "move", "label": "Move (X,Y)" },
        { "key": "workspace", "label": "Workspace" },
        { "key": "opacity", "label": "Opacity" },
        { "key": "noblur", "label": "No blur" },
        { "key": "noborder", "label": "No border" },
        { "key": "noshadow", "label": "No shadow" },
        { "key": "norounding", "label": "Square corners" },
        { "key": "nodim", "label": "Never dim" },
        { "key": "noanim", "label": "No animations" },
        { "key": "opaque", "label": "Force opaque" },
        { "key": "xray", "label": "Blur X-ray" },
        { "key": "nofocus", "label": "Never take focus" },
        { "key": "stayfocused", "label": "Hold focus (dialogs)" },
        { "key": "keepaspectratio", "label": "Keep aspect ratio" },
        { "key": "pseudo", "label": "Pseudo-tile" },
        { "key": "immediate", "label": "Immediate (tearing)" },
        { "key": "idleinhibit", "label": "Block idle/sleep" },
        { "key": "suppressevent", "label": "Ignore app request" }
    ]
    // actions carrying a value: the text ones are free-form, idleinhibit and
    // suppressevent pick from a fixed set (via the inline Dropdown below).
    readonly property var valueActions: ["opacity", "size", "move", "workspace", "idleinhibit", "suppressevent"]
    readonly property var textValueActions: ["opacity", "size", "move", "workspace"]
    readonly property var idleInhibitOptions: [
        { "key": "always", "label": "Always" },
        { "key": "focus", "label": "Focus" },
        { "key": "fullscreen", "label": "Fullscreen" }
    ]
    readonly property var suppressEventOptions: [
        { "key": "maximize", "label": "Maximize" },
        { "key": "fullscreen", "label": "Fullscreen" },
        { "key": "activate", "label": "Activate" },
        { "key": "activatefocus", "label": "Activate focus" }
    ]
    function actionValueDefault(k) {
        return k === "idleinhibit" ? "always"
            : k === "suppressevent" ? "maximize" : "";
    }

    // every mutation replaces the whole list with a new array: editList wants
    // a fresh ref and the Repeater rebuilds its rows on each change, so text
    // edits commit on editing-finished, not per keystroke.
    function patch(i, key, val) {
        var a = store.windowRules.slice();
        a[i] = Object.assign({}, a[i]);
        a[i][key] = val;
        store.editList("windowRules", a);
    }
    // switching action resets the value to that action's default: the two
    // enumerated actions seed their first choice, everything else clears it.
    function setAction(i, key) {
        var a = store.windowRules.slice();
        a[i] = Object.assign({}, a[i]);
        a[i].action = key;
        a[i].value = page.actionValueDefault(key);
        store.editList("windowRules", a);
    }
    function addRule() {
        var a = store.windowRules.slice();
        a.push({ "class": "", "title": "", "action": "float", "value": "" });
        store.editList("windowRules", a);
    }
    function removeRule(i) {
        var a = store.windowRules.slice();
        a.splice(i, 1);
        store.editList("windowRules", a);
    }

    HubButton {
        id: addBtn
        anchors.right: parent.right
        anchors.top: parent.top
        label: "Add rule"
        icon: "plus"
        onClicked: page.addRule()
    }

    Text {
        id: intro
        anchors.left: parent.left
        anchors.right: addBtn.left
        anchors.rightMargin: 18
        anchors.verticalCenter: addBtn.verticalCenter
        wrapMode: Text.WordWrap
        text: "Custom window rules layered over the ones Ryoku ships. Match a window by its class and/or title, then pick what to do: float a dialog, pin a video, force it opaque, and more. Changes apply when you Save."
        color: Theme.subtle
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: addBtn.bottom
        anchors.topMargin: 22
        anchors.bottom: bar.top
        anchors.bottomMargin: 18
        contentWidth: width
        contentHeight: Math.max(col.height, height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            id: sb
            policy: ScrollBar.AsNeeded
            width: 7
            contentItem: Rectangle {
                implicitWidth: 4
                radius: Theme.radius
                color: Theme.line
                opacity: sb.pressed ? 0.9 : (sb.hovered ? 0.7 : 0.4)
                Behavior on opacity { NumberAnimation { duration: Theme.quick } }
            }
        }

        Column {
            id: col
            width: flick.width - 12
            spacing: 12

            Text {
                visible: store.windowRules.length === 0
                width: parent.width
                topPadding: 28
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "No custom rules yet. Add one to override how a specific window opens."
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 13
            }

            Repeater {
                model: store.windowRules

                delegate: Rectangle {
                    id: rrow
                    required property int index
                    required property var modelData

                    readonly property bool needsValue: page.valueActions.indexOf(rrow.modelData.action) >= 0
                    readonly property bool textValue: page.textValueActions.indexOf(rrow.modelData.action) >= 0
                    readonly property bool choiceValue: rrow.modelData.action === "idleinhibit"
                        || rrow.modelData.action === "suppressevent"
                    readonly property string valueHint: {
                        var a = rrow.modelData.action;
                        return a === "opacity" ? "0.0 - 1.0"
                            : a === "size" ? "1200x800"
                            : a === "move" ? "100,60"
                            : a === "workspace" ? "2" : "";
                    }
                    // fixed widths for action/value/delete; the two match
                    // fields split whatever space is left.
                    readonly property real gap: 10
                    readonly property real ddW: 150
                    readonly property real valW: 110
                    readonly property real tfW: (width - 24 - ddW - 30
                        - gap * (needsValue ? 4 : 3) - (needsValue ? valW : 0)) / 2

                    width: col.width
                    height: 56
                    radius: Theme.radius
                    color: Theme.surfaceLo
                    border.width: 1
                    border.color: Theme.line

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: rrow.gap

                        Rectangle {
                            width: rrow.tfW
                            height: 30
                            radius: Theme.radius
                            color: Theme.surfaceLo
                            border.width: 1
                            border.color: classInput.activeFocus ? Theme.ember : Theme.line
                            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                            TextInput {
                                id: classInput
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                text: rrow.modelData["class"] || ""
                                color: Theme.bright
                                font.family: Theme.mono
                                font.pixelSize: 13
                                clip: true
                                selectByMouse: true
                                onEditingFinished: {
                                    if (text !== (rrow.modelData["class"] || ""))
                                        page.patch(rrow.index, "class", text);
                                }

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: classInput.text === "" && !classInput.activeFocus
                                    text: "Match class"
                                    color: Theme.faint
                                    font: classInput.font
                                }
                            }
                        }

                        Rectangle {
                            width: rrow.tfW
                            height: 30
                            radius: Theme.radius
                            color: Theme.surfaceLo
                            border.width: 1
                            border.color: titleInput.activeFocus ? Theme.ember : Theme.line
                            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                            TextInput {
                                id: titleInput
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                text: rrow.modelData.title || ""
                                color: Theme.bright
                                font.family: Theme.font
                                font.pixelSize: 13
                                clip: true
                                selectByMouse: true
                                onEditingFinished: {
                                    if (text !== (rrow.modelData.title || ""))
                                        page.patch(rrow.index, "title", text);
                                }

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: titleInput.text === "" && !titleInput.activeFocus
                                    text: "Match title"
                                    color: Theme.faint
                                    font: titleInput.font
                                }
                            }
                        }

                        Dropdown {
                            width: rrow.ddW
                            height: 30
                            fieldWidth: rrow.ddW
                            options: page.actionOptions
                            current: rrow.modelData.action
                            onChosen: (k) => page.setAction(rrow.index, k)
                        }

                        Rectangle {
                            visible: rrow.textValue
                            width: rrow.valW
                            height: 30
                            radius: Theme.radius
                            color: Theme.surfaceLo
                            border.width: 1
                            border.color: valInput.activeFocus ? Theme.ember : Theme.line
                            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                            TextInput {
                                id: valInput
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                text: rrow.modelData.value || ""
                                color: Theme.bright
                                font.family: Theme.mono
                                font.pixelSize: 13
                                clip: true
                                selectByMouse: true
                                onEditingFinished: {
                                    if (text !== (rrow.modelData.value || ""))
                                        page.patch(rrow.index, "value", text);
                                }

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: valInput.text === "" && !valInput.activeFocus
                                    text: rrow.valueHint
                                    color: Theme.faint
                                    font: valInput.font
                                }
                            }
                        }

                        Dropdown {
                            visible: rrow.choiceValue
                            width: rrow.valW
                            height: 30
                            fieldWidth: rrow.valW
                            options: rrow.modelData.action === "idleinhibit"
                                ? page.idleInhibitOptions : page.suppressEventOptions
                            current: rrow.modelData.value || page.actionValueDefault(rrow.modelData.action)
                            onChosen: (k) => page.patch(rrow.index, "value", k)
                        }

                        Item {
                            id: delBtn
                            width: 30
                            height: 30

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radius
                                color: delHov.hovered ? Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, 0.12) : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.quick } }
                            }

                            Icon {
                                anchors.centerIn: parent
                                name: "trash"
                                size: 17
                                tint: delHov.hovered ? Theme.bad : Theme.dim
                                Behavior on tint { ColorAnimation { duration: Theme.quick } }
                            }

                            HoverHandler { id: delHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: page.removeRule(rrow.index) }
                        }
                    }
                }
            }
        }
    }

    // --- action bar (mirrors Shell Settings) -------------------------------
    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        height: 60
        radius: Theme.radius
        color: store.dirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.08) : Theme.surfaceLo
        border.width: 1
        border.color: store.dirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.4) : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.medium } }
        Behavior on border.color { ColorAnimation { duration: Theme.medium } }

        Rectangle {
            id: statusDot
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 9
            height: 9
            radius: 4.5
            color: store.dirty ? Theme.ember : Theme.ok
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }

        Text {
            anchors.left: statusDot.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: store.dirty ? "Unsaved changes" : "Saved \u00b7 applies on save"
            color: store.dirty ? Theme.bright : Theme.dim
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Clear all"
                icon: "trash"
                enabled: store.windowRules.length > 0
                onClicked: store.editList("windowRules", [])
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Revert"
                icon: "close"
                enabled: store.dirty
                onClicked: store.revert()
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Save"
                icon: "check"
                primary: true
                enabled: store.dirty
                onClicked: store.save()
            }
        }
    }
}
