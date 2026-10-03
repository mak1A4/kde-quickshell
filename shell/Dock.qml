import QtQuick
import qs.widgets

// Open windows, hidden until the pointer touches the bottom frame edge, then
// sliding up from behind it. Fill the frame with this item. `area` is the
// visible part (for the input region), `blob` its background rectangle for
// the frame shader.
Item {
    id: root

    property bool shown: false
    readonly property bool wanted: sensor.hovered || panelHover.hovered

    // 1 = fully below the edge, 0 = out; overshoots below 0 on the way out
    property real offset: shown ? 0 : 1
    readonly property bool hidden: offset >= 1
    property real w: taskbar.implicitWidth + Theme.padding * 2
    readonly property real h: Theme.dockHeight
    readonly property real slack: 36
    readonly property real edgeY: height - Theme.frameBorder

    readonly property rect area: Qt.rect(clip.x + panel.x, clip.y + panel.y, w, Math.max(0, edgeY - clip.y - panel.y))
    readonly property vector4d blob: {
        if (hidden)
            return Qt.vector4d(0, 0, 0, 0);
        const top = area.y;
        const bottom = edgeY + Theme.panelRounding;
        return Qt.vector4d(area.x + w / 2, (top + bottom) / 2, w / 2, (bottom - top) / 2);
    }

    onWantedChanged: {
        if (wanted) {
            hide.stop();
            shown = true;
        } else {
            hide.restart();
        }
    }

    Behavior on offset {
        Anim {}
    }

    Behavior on w {
        Anim {}
    }

    Timer {
        id: hide

        interval: 300
        onTriggered: root.shown = false
    }

    // the bottom border strip; always part of the frame's input region
    Item {
        x: Theme.frameBorder
        y: root.edgeY
        width: root.width - Theme.frameBorder - Theme.barWidth
        height: Theme.frameBorder

        HoverHandler {
            id: sensor
        }
    }

    // keeps the sliding panel from drawing over the border
    Item {
        id: clip

        x: Theme.frameBorder + (root.width - Theme.frameBorder - Theme.barWidth - width) / 2
        y: root.edgeY - height
        width: root.w + root.slack * 2
        height: root.h + root.slack
        clip: true
        visible: !root.hidden

        Item {
            id: panel

            x: root.slack
            y: root.slack + (root.h + Theme.panelSmoothing) * root.offset
            width: root.w
            height: root.h

            HoverHandler {
                id: panelHover
            }

            // imports org.kde.taskmanager, hence Guarded
            Guarded {
                id: taskbar

                x: Theme.padding
                y: (root.h - implicitHeight) / 2
                name: "taskbar"
                source: Qt.resolvedUrl("modules/Taskbar.qml")
                opacity: root.shown ? 1 : 0

                Behavior on opacity {
                    Anim {
                        kind: Anim.Fade
                    }
                }
            }
        }
    }
}
