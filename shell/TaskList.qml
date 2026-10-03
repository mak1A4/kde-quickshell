import QtQuick
import org.kde.taskmanager as TaskManager

// Window list from libtaskmanager. Needs KWin to grant
// org_kde_plasma_window_management (see packaging/kde-quickshell.desktop).
Row {
    id: root

    spacing: 6

    TaskManager.TasksModel {
        id: tasks

        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: false
    }

    // libtaskmanager exposes no "denied" flag, so an empty model is ambiguous.
    // Say so instead of rendering nothing.
    Text {
        visible: tasks.count === 0
        anchors.verticalCenter: parent.verticalCenter
        color: "#f9e2af"
        font.pixelSize: 13
        text: "no windows (or KWin denied window management)"
    }

    Repeater {
        model: tasks

        Rectangle {
            id: task

            required property var model
            required property int index

            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(label.implicitWidth, 180) + 16
            height: 22
            radius: 6
            color: task.model.IsActive ? "#45475a" : "transparent"

            Text {
                id: label

                anchors.centerIn: parent
                width: Math.min(implicitWidth, 180)
                elide: Text.ElideRight
                color: "#cdd6f4"
                font.pixelSize: 13
                text: task.model.display ?? ""
            }

            MouseArea {
                anchors.fill: parent
                onClicked: tasks.requestActivate(tasks.makeModelIndex(task.index))
            }
        }
    }
}
