import QtQuick
import QtQuick.Layouts
import org.kde.taskmanager as TaskManager
import qs
import qs.widgets

// Windows on the current desktop, from libtaskmanager. Needs KWin to grant
// org_kde_plasma_window_management (see packaging/kde-quickshell.desktop).
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
    // ambiguous and gets a visible hint.
    TaskManager.TasksModel {
        id: allTasks

        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
    }

    Label {
        visible: allTasks.count === 0
        color: Theme.warning
        text: "no windows (or KWin denied window management)"
    }

    Repeater {
        model: tasks

        Pill {
            id: task

            required property var model
            required property int index

            color: task.model.IsDemandingAttention ? Theme.warning : (task.model.IsActive || hovered ? Theme.surfaceHover : "transparent")
            opacity: task.model.IsMinimized ? 0.5 : 1
            onClicked: button => {
                const modelIndex = tasks.makeModelIndex(task.index);
                if (button === Qt.MiddleButton)
                    tasks.requestClose(modelIndex);
                else if (button === Qt.LeftButton && task.model.IsActive)
                    tasks.requestToggleMinimized(modelIndex);
                else if (button === Qt.LeftButton)
                    tasks.requestActivate(modelIndex);
            }

            Icon {
                source: task.model.decoration
                colorize: false
            }

            Label {
                visible: task.model.IsActive
                Layout.maximumWidth: Theme.maxTextWidth
                text: task.model.display ?? ""
            }
        }
    }
}
