import QtQuick
import QtQuick.Layouts
import org.kde.taskmanager as TaskManager
import qs
import qs.widgets

// Windows on the current desktop, from libtaskmanager, for the dock. Needs
// KWin to grant org_kde_plasma_window_management (see
// packaging/kde-quickshell.desktop). Left click activates (or minimizes the
// active window), middle click closes.
RowLayout {
    id: root

    spacing: 3

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
            color: {
                if (model.IsDemandingAttention)
                    return Theme.warning;
                return mouse.containsMouse || model.IsActive ? Theme.surfaceHover : "transparent";
            }

            Icon {
                anchors.centerIn: parent
                implicitWidth: 36
                implicitHeight: 36
                source: task.model.decoration
                colorize: false
            }

            // marks the active window
            Rectangle {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                }
                visible: task.model.IsActive
                width: 12
                height: 3
                radius: 1.5
                color: Theme.accent
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
