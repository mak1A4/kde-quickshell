import QtQuick
import qs

// Loads a module that imports optional KDE QML modules. A failed import would
// otherwise take the whole shell down; here it becomes a visible error: a
// label, or just an error icon where there is no room (`compact`, the bar).
Item {
    id: root

    required property string name
    property bool compact: false
    property alias source: loader.source
    property alias active: loader.active
    readonly property bool failed: loader.status === Loader.Error
    readonly property Item error: compact ? errorIcon : errorLabel
    // the compact error icon explains itself on hover
    readonly property string hintTitle: failed && compact ? name + ": module not loadable" : ""
    readonly property list<string> hintLines: ["See `qs log` for the import error"]

    implicitWidth: failed ? error.implicitWidth : loader.implicitWidth
    implicitHeight: failed ? error.implicitHeight : loader.implicitHeight

    Loader {
        id: loader

        anchors.verticalCenter: parent.verticalCenter
    }

    Label {
        id: errorLabel

        anchors.verticalCenter: parent.verticalCenter
        visible: root.failed && !root.compact
        color: Theme.error
        padding: Theme.padding
        text: root.name + ": module not loadable"
    }

    HoverHandler {
        enabled: root.failed && root.compact
        onHoveredChanged: Popouts.hover(root, hovered)
    }

    Icon {
        id: errorIcon

        visible: root.failed && root.compact
        source: "data-error"
        color: Theme.error
    }
}
