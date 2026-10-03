import QtQuick
import QtQuick.Layouts
import qs.widgets

// Text of the hovered item's hint: a bold title and dimmer detail lines.
// Keeps showing the last hint while its container animates closed.
ColumnLayout {
    id: root

    // the hovered item, or null
    required property Item source

    property string title: ""
    property list<string> lines: []

    spacing: 3

    Binding {
        root.title: root.source?.hintTitle ?? ""
        root.lines: root.source?.hintLines ?? []
        when: root.source !== null
        restoreMode: Binding.RestoreNone
    }

    Label {
        Layout.maximumWidth: 360
        font.bold: true
        text: root.title
    }

    Repeater {
        model: root.lines

        Label {
            required property string modelData

            Layout.maximumWidth: 360
            color: Theme.fgDim
            text: modelData
        }
    }
}
