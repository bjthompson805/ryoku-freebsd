pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import "Singletons"

// renders a plugin's settings from its declared schema (manifest.metadata.settings)
// using the native hub controls, so every plugin gets a real options panel
// without shipping QML. field types: choice -> Dropdown, toggle -> ToggleRow,
// slider -> SliderRow, text/image -> labelled input. fields grouped by `group`
// under mono section headers (hub's SettingSection idiom).
//
// form keeps a live `values` copy seeded from the plugin's saved settings, so
// controls reflect edits at once. every change also fires `changed(key, value)`
// for the host to persist (writes plugins.json via `ryoku-plugins-place`).
Column {
    id: form

    // schema: ordered [{ key, type, label, default, options, min, max, step, decimals, group, placeholder }]
    property var schema: []
    // values = the plugin's current settings (placement.settings). copied locally
    // on assignment so edits show without a round-trip.
    property var values: ({})
    property var _local: ({})
    onValuesChanged: form._local = JSON.parse(JSON.stringify(form.values || {}))
    Component.onCompleted: form._local = JSON.parse(JSON.stringify(form.values || {}))

    signal changed(string key, var value)

    spacing: 16

    function _val(field) {
        if (form._local && form._local[field.key] !== undefined)
            return form._local[field.key];
        return field.default;
    }
    function _set(key, value) {
        var n = JSON.parse(JSON.stringify(form._local || {}));
        n[key] = value;
        form._local = n;
        form.changed(key, value);
    }
    function _choices(field) {
        return (field.options || []).map(function (o) {
            return { "key": o.value, "label": o.label };
        });
    }

    Repeater {
        model: form.schema

        delegate: Column {
            id: fieldWrap
            required property var modelData
            required property int index
            width: form.width
            spacing: 12

            readonly property string grp: modelData.group || ""
            readonly property bool startsGroup: fieldWrap.index === 0
                || ((form.schema[fieldWrap.index - 1].group || "") !== fieldWrap.grp)

            // section header (mono caps + hairline), once per group.
            Item {
                width: parent.width
                height: 16
                visible: fieldWrap.startsGroup && fieldWrap.grp.length > 0
                Text {
                    id: gHead
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: fieldWrap.grp
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2
                }
                Rectangle {
                    anchors.left: gHead.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: Theme.lineSoft
                }
            }

            Loader {
                width: parent.width
                sourceComponent: {
                    switch (fieldWrap.modelData.type) {
                    case "choice": return cChoice;
                    case "toggle": return cToggle;
                    case "slider": return cSlider;
                    case "image": return cImage;
                    default: return cText;   // text + anything unknown
                    }
                }
                onLoaded: item.field = fieldWrap.modelData
            }
        }
    }

    // control templates, picked per field type.

    Component {
        id: cChoice
        Dropdown {
            property var field: ({})
            label: field.label || field.key
            options: form._choices(field)
            current: String(form._val(field))
            onChosen: (key) => form._set(field.key, key)
        }
    }

    Component {
        id: cToggle
        ToggleRow {
            property var field: ({})
            label: field.label || field.key
            checked: form._val(field) === true || form._val(field) === "true"
            onToggled: (v) => form._set(field.key, v)
        }
    }

    Component {
        id: cSlider
        SliderRow {
            property var field: ({})
            label: field.label || field.key
            from: field.min !== undefined ? field.min : 0
            to: field.max !== undefined ? field.max : 1
            step: field.step !== undefined ? field.step : 0.01
            decimals: field.decimals !== undefined ? field.decimals : 2
            value: Number(form._val(field))
            onModified: (v) => form._set(field.key, field.decimals === 0 ? Math.round(v) : v)
        }
    }

    Component {
        id: cText
        Item {
            id: tRow
            property var field: ({})
            implicitHeight: 38
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - box.width - 14
                elide: Text.ElideRight
                text: tRow.field.label || tRow.field.key
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Rectangle {
                id: box
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 220
                height: 30
                radius: Theme.radius
                color: Theme.surfaceLo
                border.width: 1
                border.color: input.activeFocus ? Theme.ember : Theme.line
                Behavior on border.color { ColorAnimation { duration: Theme.quick } }
                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    text: String(form._val(tRow.field) || "")
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 13
                    clip: true
                    selectByMouse: true
                    onEditingFinished: form._set(tRow.field.key, text)
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: input.text.length === 0 && !input.activeFocus
                        text: tRow.field.placeholder || ""
                        color: Theme.faint
                        font: input.font
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // image = labelled field that opens the system file chooser (portal).
    Component {
        id: cImage
        Item {
            id: imgRow
            property var field: ({})
            implicitHeight: 38
            readonly property string cur: String(form._val(imgRow.field) || "")
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - pickBox.width - 14
                elide: Text.ElideRight
                text: imgRow.field.label || imgRow.field.key
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Rectangle {
                id: pickBox
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 220
                height: 30
                radius: Theme.radius
                color: pickHover.hovered ? Theme.surface : Theme.surfaceLo
                border.width: 1
                border.color: pickHover.hovered ? Theme.ember : Theme.line
                Behavior on color { ColorAnimation { duration: Theme.quick } }
                Behavior on border.color { ColorAnimation { duration: Theme.quick } }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: pIcon.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideLeft
                    text: imgRow.cur.length === 0 ? "Choose image\u2026" : imgRow.cur.replace(/^.*\//, "")
                    color: imgRow.cur.length === 0 ? Theme.faint : Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 13
                }
                Icon {
                    id: pIcon
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    name: "image"
                    size: 14
                    tint: pickHover.hovered ? Theme.cream : Theme.dim
                }
                HoverHandler { id: pickHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: imgDlg.open() }
            }
            FileDialog {
                id: imgDlg
                title: "Choose an image"
                nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)", "All files (*)"]
                onAccepted: form._set(imgRow.field.key, "" + imgDlg.selectedFile)
            }
        }
    }
}
