pragma Singleton

import Quickshell
import QtQuick
import org.kde.taskmanager as TaskManager

// The window that was being worked in, to hand the keyboard back to.
//
// The frame is one surface that asks for the keyboard while the launcher, the
// palette or the notification list is open. KWin makes it the active window
// then, and leaves it that when it stops asking: nothing is typed into any
// window until one is clicked. So the frame calls remember() before it asks
// and giveBack() when it lets go (see Frame.qml), and the window that was
// active before is activated again.
Singleton {
    id: root

    // the window that was active when remember() was called, if any
    property var last: null
    // what is being run may open a window, which is to have the keyboard
    property bool expecting: false

    // Before the frame asks for the keyboard: the task model's active task
    // is not announced reliably, so it is read at this moment instead.
    // `holding`: the frame still has the keyboard from the last time, so no
    // window is active and the one remembered then still counts.
    function remember(holding) {
        const active = tasks.activeTask;
        if (active.valid)
            last = tasks.makePersistentModelIndex(active.row);
        else if (!holding)
            last = null;
    }

    // Called by whatever runs something that may open a window, before it
    // closes its panel. The frame then waits for that window (see Frame.qml):
    // activating the old one at once would cost the new one its right to
    // take the focus.
    function expectWindow() {
        expecting = true;
    }

    // With nothing remembered (the shell was reloaded while it had the
    // keyboard) or that window gone: the topmost one on this desktop.
    function giveBack() {
        if (last?.valid) {
            tasks.requestActivate(last);
            return;
        }
        let top = null;
        let order = -1;
        for (let row = 0; row < tasks.count; row++) {
            const index = tasks.index(row, 0);
            if (tasks.data(index, TaskManager.AbstractTasksModel.IsMinimized))
                continue;
            const stacking = tasks.data(index, TaskManager.AbstractTasksModel.StackingOrder);
            if (stacking > order) {
                order = stacking;
                top = index;
            }
        }
        if (top)
            tasks.requestActivate(top);
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
}
