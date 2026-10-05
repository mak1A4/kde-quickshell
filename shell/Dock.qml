import QtQuick
import QtQuick.Layouts
import qs.launcher
import qs.widgets

// The dock: a launcher button and the open windows, hidden until the pointer
// touches the bottom frame edge, then sliding up from behind it. When the
// launcher opens, the same panel grows into it. Fill the frame with this
// item. `area` is the visible part (for the input region), `blob` its
// background rectangle for the frame shader.
Item {
    id: root

    // the screen this dock is on, to tell whether the launcher is meant for it
    required property var screen

    property bool shown: false
    readonly property bool wanted: sensor.hovered || panelHover.hovered
    readonly property bool launcherOpen: Launcher.open && (Launcher.screen === null || Launcher.screen === screen)
    readonly property bool visibleNow: shown || launcherOpen

    // 1 = fully below the edge, 0 = out; overshoots below 0 on the way out
    property real offset: visibleNow ? 0 : 1
    readonly property bool hidden: offset >= 1
    property real w: launcherOpen ? launcher.implicitWidth : row.implicitWidth + Theme.padding * 2
    property real h: launcherOpen ? launcher.implicitHeight : Theme.dockHeight
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

    // after the launcher closes, the dock stays only if the pointer is on it
    onLauncherOpenChanged: {
        if (launcherOpen)
            shown = true;
        else if (!wanted)
            hide.restart();
    }

    Behavior on offset {
        Anim {}
    }

    Behavior on w {
        Anim {}
    }

    Behavior on h {
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
            // Exactly the background's size, and clipping: while the dock grows
            // into the launcher, or the launcher resizes as you type, content
            // laid out for the final size is uncovered, never drawn outside it.
            clip: true

            HoverHandler {
                id: panelHover
            }

            // with the launcher open the frame takes clicks everywhere to
            // dismiss it; those on the panel itself must stop here
            MouseArea {
                anchors.fill: parent
                enabled: root.launcherOpen
                acceptedButtons: Qt.AllButtons
            }

            // dock content: launcher button, divider, open windows
            RowLayout {
                id: row

                // Centred, and on the dock's own strip at the bottom: while the
                // panel is launcher-sized the row stays where the dock is,
                // instead of riding the top edge as the panel grows or shrinks.
                x: (panel.width - implicitWidth) / 2
                y: panel.height - Theme.dockHeight + (Theme.dockHeight - implicitHeight) / 2
                spacing: Theme.spacing
                opacity: root.visibleNow && !root.launcherOpen ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    SwapFade {
                        incoming: !root.launcherOpen
                    }
                }

                Rectangle {
                    id: launcherButton

                    readonly property string hintTitle: "Applications"
                    readonly property list<string> hintLines: ["Search and start apps"]

                    implicitWidth: 48
                    implicitHeight: 48
                    radius: 12
                    color: launcherHover.hovered ? Theme.surfaceHover : "transparent"

                    Behavior on color {
                        ColorAnim {}
                    }

                    Icon {
                        anchors.centerIn: parent
                        implicitWidth: 30
                        implicitHeight: 30
                        source: "applications-all-symbolic"
                    }

                    HoverHandler {
                        id: launcherHover

                        onHoveredChanged: Popouts.hover(launcherButton, hovered)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Launcher.show(root.screen)
                    }
                }

                Rectangle {
                    implicitWidth: 1.5
                    implicitHeight: 30
                    color: Theme.surface
                }

                // imports org.kde.taskmanager, hence Guarded
                Guarded {
                    name: "taskbar"
                    source: Qt.resolvedUrl("modules/Taskbar.qml")
                }
            }

            // created only while open (and until it has faded out)
            Loader {
                id: launcherLoader

                // Centred by hand: the panel is centred on the screen and its
                // width is animated, and this exactly undoes the panel's own
                // movement, so the content stands still. A centre anchor
                // places by whole and half pixels depending on whether the
                // panel's width is odd: the content wobbled by up to a pixel
                // while the panel grew, and slid sideways as the width
                // settled after overshooting.
                x: (panel.width - width) / 2
                anchors.bottom: parent.bottom
                active: root.launcherOpen || opacity > 0
                opacity: root.launcherOpen ? 1 : 0
                sourceComponent: LauncherPanel {}

                Behavior on opacity {
                    SwapFade {
                        incoming: root.launcherOpen
                    }
                }
            }

            // size of the launcher content; a fallback keeps the dock from
            // collapsing in the instant before the loader has it
            QtObject {
                id: launcher

                readonly property real implicitWidth: launcherLoader.item?.implicitWidth ?? 540
                readonly property real implicitHeight: launcherLoader.item?.implicitHeight ?? Theme.dockHeight
            }
        }
    }
}
