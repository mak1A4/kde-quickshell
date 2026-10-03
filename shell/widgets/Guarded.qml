import QtQuick
import qs

// Loads a module that imports optional KDE QML modules. A failed import would
// otherwise take the whole bar down; here it becomes a visible error label.
Item {
    id: root

    required property string name
    property alias source: loader.source
    readonly property bool failed: loader.status === Loader.Error

    implicitWidth: failed ? error.implicitWidth : loader.implicitWidth
    implicitHeight: failed ? error.implicitHeight : loader.implicitHeight

    Loader {
        id: loader

        anchors.verticalCenter: parent.verticalCenter
    }

    Label {
        id: error

        anchors.verticalCenter: parent.verticalCenter
        visible: root.failed
        color: Theme.error
        text: root.name + ": module not loadable"
    }
}
