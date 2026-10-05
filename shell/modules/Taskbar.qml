import QtQuick
import QtQuick.Layouts
import org.kde.taskmanager as TaskManager
import qs
import qs.widgets

// Windows on the current desktop, from libtaskmanager, for the dock. Needs
// KWin to grant org_kde_plasma_window_management (see
// packaging/kde-quickshell.desktop). Left click activates (or minimizes the
// active window), middle click closes.
//
// The active window's icon has a rounded square behind it, tinted with the
// current desktop's colour (the one its dot has in the bar).
RowLayout {
    id: root

    spacing: 3

    // the current desktop's colour, by its position, as in modules/Workspaces.qml
    readonly property color desktopColor: {
        const index = Math.max(0, desktopInfo.desktopIds.indexOf(desktopInfo.currentDesktop));
        return Theme.desktopColors[index % Theme.desktopColors.length];
    }

    TaskManager.VirtualDesktopInfo {
        id: desktopInfo
    }

    TaskManager.ActivityInfo {
        id: activityInfo
    }

    TaskManager.TasksModel {
        id: tasks

        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        virtualDesktop: desktopInfo.currentDesktop
        activity: activityInfo.currentActivity
        filterByVirtualDesktop: true
        filterByActivity: true
        filterByScreen: false
    }

    // Unfiltered twin, only to tell "this desktop is empty" from "we see no
    // windows at all". libtaskmanager has no "denied" flag, so the latter is
    // ambiguous and says so.
    TaskManager.TasksModel {
        id: allTasks

        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
    }

    Label {
        visible: tasks.count === 0
        color: allTasks.count === 0 ? Theme.warning : Theme.fgDim
        text: allTasks.count === 0 ? "No windows (or KWin denied window management)" : "No windows on this desktop"
    }

    Repeater {
        model: tasks

        Rectangle {
            id: task

            required property var model
            required property int index
            readonly property string hintTitle: model.display ?? ""
            readonly property list<string> hintLines: model.AppName && model.AppName !== model.display ? [model.AppName] : []

            implicitWidth: 48
            implicitHeight: 48
            radius: 12
            opacity: model.IsMinimized ? 0.5 : 1
            // the square: the desktop's colour, faintly, for the active
            // window; grey under the pointer
            color: {
                if (model.IsDemandingAttention)
                    return Theme.warning;
                if (model.IsActive)
                    return Qt.tint(Theme.surface, Qt.alpha(root.desktopColor, 0.38));
                return mouse.containsMouse ? Theme.surfaceHover : "transparent";
            }

            Behavior on color {
                ColorAnim {}
            }

            Icon {
                anchors.centerIn: parent
                implicitWidth: 36
                implicitHeight: 36
                source: task.model.decoration
                colorize: false
            }

            HoverHandler {
                onHoveredChanged: Popouts.hover(task, hovered)
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: event => {
                    const modelIndex = tasks.makeModelIndex(task.index);
                    if (event.button === Qt.MiddleButton)
                        tasks.requestClose(modelIndex);
                    else if (task.model.IsActive)
                        tasks.requestToggleMinimized(modelIndex);
                    else
                        tasks.requestActivate(modelIndex);
                }
            }
        }
    }
}
