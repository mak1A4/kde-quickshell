import Quickshell
import Quickshell.Wayland
import QtQuick

// The frame is one surface covering the whole screen and cannot reserve
// space itself (a layer surface reserves on one edge only). These four
// invisible, input-less surfaces do it, so maximized windows stay inside,
// `Theme.windowGap` away from the frame on every side.
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
        exclusiveZone: Theme.frameBorder + Theme.windowGap
    }

    // the gap has room for the notch that comes out of this edge's middle
    // while threads are at work (ai/Notch.qml): it would lie on a maximized
    // window's tab bar
    Edge {
        anchors.top: true
        exclusiveZone: Theme.frameBorder + Theme.windowGap
    }

    Edge {
        anchors.bottom: true
        exclusiveZone: Theme.frameBorder + Theme.windowGap
    }

    Edge {
        anchors.right: true
        exclusiveZone: Theme.barWidth + Theme.windowGap
    }
}
