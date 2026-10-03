import Quickshell
import Quickshell.Wayland
import QtQuick

// The frame is one surface covering the whole screen and cannot reserve
// space itself (a layer surface reserves on one edge only). These four
// invisible, input-less surfaces do it, so maximized windows stay inside.
Scope {
    id: root

    required property ShellScreen screen

    component Edge: PanelWindow {
        screen: root.screen
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        mask: Region {}
        // "dock": see Frame.qml
        WlrLayershell.namespace: "dock"
    }

    Edge {
        anchors.left: true
        exclusiveZone: Theme.frameBorder
    }

    Edge {
        anchors.top: true
        exclusiveZone: Theme.frameBorder
    }

    Edge {
        anchors.bottom: true
        exclusiveZone: Theme.frameBorder
    }

    Edge {
        anchors.right: true
        exclusiveZone: Theme.barWidth
    }
}
