import QtQuick
import QtQuick.Layouts
import QtQml.Models
import org.kde.taskmanager as TaskManager
import qs
import qs.widgets

// Windows on the current desktop, from libtaskmanager, for the dock. Needs
// KWin to grant org_kde_plasma_window_management (see
// packaging/kde-quickshell.desktop). Left click activates (or minimizes the
// active window), middle click closes, right click opens a small menu.
//
// No hint over an icon: the dock is kept to the icons (there was one, the
// window's title and its application's name in a bubble above).
//
// The active window's icon has a rounded square behind it, tinted with the
// current desktop's colour (the one its dot has in the bar).
//
// An application can be pinned (the menu): its icon is then there without a
// window too, dimmed, and a click starts it. The pinned ones are KDE's
// "launchers", kept in Pins.qml.
//
// The order of the icons is the shell's own (Pins.order, by application),
// not the task list's: the rows are shown through a DelegateModel and put
// in that order whenever they change (arrange()). An application has one
// place, whether it is a launcher or a window just now, and keeps it over
// closing, starting again and a restart of the shell. Left to the task
// list (its manual sort mode), a pinned application had two places, its
// launcher's and its window's, and its icon jumped from one to the other
// when the window closed.
//
// An icon can be dragged along the row to another place. While it is
// dragged the others only make room; the order is changed once, when it is
// let go.
RowLayout {
    id: root

    spacing: 3

    // from one icon to the next
    readonly property real pitch: 48 + spacing
    // the icon being dragged and where it would go, as rows; -1: none
    property int dragFrom: -1
    property int dragTo: -1
    // the icon whose menu is open
    property Item menuFor: null
    // Dragging or choosing from a menu, the pointer leaves the dock; it
    // stays out meanwhile.
    readonly property bool busy: dragFrom >= 0 || menu.visible

    onBusyChanged: {
        if (busy)
            Pins.holder = root;
        else if (Pins.holder === root)
            Pins.holder = null;
    }
    Component.onDestruction: {
        if (Pins.holder === root)
            Pins.holder = null;
    }

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
        // the order of the icons is made further down
        sortMode: TaskManager.TasksModel.SortDisabled
        launcherList: Pins.pinned
        onLauncherListChanged: Pins.store(launcherList)
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

    ActionMenu {
        id: menu

        anchorItem: root.menuFor ?? root
    }

    // The application a row belongs to, for its place in the order: its
    // launcher's address, which a window and its launcher share. For a
    // window of no known application, whatever tells it from the others.
    function keyOf(model) {
        return String(model.LauncherUrlWithoutIcon ?? "") || "window:" + (model.AppId || model.AppName || model.display || "");
    }

    property bool arranging: false

    // Puts the icons in the order of Pins.order. An application not in it
    // yet goes to the end, of the row and of the order. Several windows of
    // one application stay together, in the order they have.
    function arrange() {
        if (arranging)
            return;
        arranging = true;
        const items = visual.items;
        const order = Array.from(Pins.order);
        const present = {};
        const ranked = [];
        for (let at = 0; at < items.count; at++) {
            const key = keyOf(items.get(at).model);
            let rank = order.indexOf(key);
            if (rank < 0)
                rank = order.push(key) - 1;
            present[key] = true;
            ranked.push({
                rank: rank,
                at: at
            });
        }
        // which of the present rows belongs at each place
        const wanted = ranked.slice().sort((a, b) => a.rank - b.rank || a.at - b.at).map(entry => entry.at);
        const now = ranked.map(entry => entry.at);
        for (let place = 0; place < wanted.length; place++) {
            const from = now.indexOf(wanted[place]);
            if (from === place)
                continue;
            items.move(from, place);
            now.splice(place, 0, now.splice(from, 1)[0]);
        }
        arranging = false;
        // Remembered: every application here or pinned, and the last 30 of
        // the others, so that the list does not grow with every program
        // ever started.
        let others = order.filter(key => !present[key] && !Pins.pinned.includes(key)).length;
        Pins.storeOrder(order.filter(key => present[key] || Pins.pinned.includes(key) || others-- <= 30));
    }

    // An icon was dragged from one place in the row to another: its
    // application goes before or after the one that is there.
    function dropped(from, to) {
        const items = visual.items;
        const moving = keyOf(items.get(from).model);
        const target = keyOf(items.get(to).model);
        if (moving === target)
            return;
        // the applications in the row, as they are, each once
        const row = [];
        for (let at = 0; at < items.count; at++) {
            const key = keyOf(items.get(at).model);
            if (!row.includes(key))
                row.push(key);
        }
        const next = row.filter(key => key !== moving);
        next.splice(next.indexOf(target) + (to > from ? 1 : 0), 0, moving);
        // into the order, in the places the row's applications have there
        const order = Array.from(Pins.order);
        const places = [];
        order.forEach((key, place) => {
            if (row.includes(key))
                places.push(place);
        });
        places.forEach((place, n) => order[place] = next[n]);
        Pins.storeOrder(order);
    }

    Connections {
        target: Pins

        function onOrderChanged() {
            Qt.callLater(root.arrange);
        }
    }

    Repeater {
        model: DelegateModel {
            id: visual

            model: tasks
            // rows came or went
            items.onChanged: Qt.callLater(root.arrange)
            delegate: taskDelegate
        }
    }

    Component {
        id: taskDelegate

        Rectangle {
            id: task

            required property var model
            // the row in the task list
            required property int index
            // the place in the dock
            readonly property int place: DelegateModel.itemsIndex
            // a pinned application without a window here
            readonly property bool launcher: model.IsLauncher ?? false
            // what pinning its application adds to the list; empty if it
            // cannot be told which application the window is
            readonly property url address: model.LauncherUrlWithoutIcon ?? ""
            readonly property bool pinned: {
                // asked again whenever the list changes
                tasks.launcherList;
                return String(address) !== "" && tasks.launcherPosition(address) !== -1;
            }

            // where the pointer has dragged it, and the room it makes for
            // another that is being dragged past it
            property real dragX: 0
            readonly property bool dragged: root.dragFrom === place
            readonly property real aside: {
                if (root.dragFrom < 0 || dragged)
                    return 0;
                if (root.dragFrom < place && place <= root.dragTo)
                    return -root.pitch;
                if (root.dragTo <= place && place < root.dragFrom)
                    return root.pitch;
                return 0;
            }
            property real shownAside: aside

            function openMenu() {
                const row = tasks.makeModelIndex(index);
                const actions = [];
                if (String(address) !== "") {
                    const address = task.address;
                    actions.push(pinned ? {
                        text: "Unpin from the Dock",
                        icon: "window-unpin-symbolic",
                        run: () => tasks.requestRemoveLauncher(address)
                    } : {
                        text: "Pin to the Dock",
                        icon: "window-pin-symbolic",
                        run: () => tasks.requestAddLauncher(address)
                    });
                }
                if (!launcher) {
                    if (model.CanLaunchNewInstance ?? false)
                        actions.push({
                            text: "New Window",
                            icon: "window-new-symbolic",
                            run: () => tasks.requestNewInstance(row)
                        });
                    actions.push({
                        text: "Close",
                        icon: "window-close-symbolic",
                        run: () => tasks.requestClose(row)
                    });
                }
                menu.open = false;
                menu.actions = actions;
                root.menuFor = task;
                menu.open = true;
            }

            implicitWidth: 48
            implicitHeight: 48
            radius: 12
            // Dimmed: a pinned application that is not running. A window is
            // not, minimized or not (it was, when every icon was a window:
            // the two would look the same).
            opacity: launcher ? 0.5 : 1
            z: dragged ? 1 : 0
            transform: Translate {
                x: task.dragged ? task.dragX : task.shownAside
            }

            // Only while something is dragged: when it is let go the list
            // changes and every icon is at once where it had moved to.
            Behavior on shownAside {
                enabled: root.dragFrom >= 0

                Anim {
                    kind: Anim.Fade
                }
            }
            // the square: the desktop's colour, faintly, for the active
            // window; grey under the pointer
            color: {
                if (model.IsDemandingAttention)
                    return Theme.warning;
                if (model.IsActive)
                    return Qt.tint(Theme.surface, Qt.alpha(root.desktopColor, 0.38));
                return mouse.containsMouse ? Theme.surfaceHover : Theme.none;
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

            MouseArea {
                id: mouse

                cursorShape: Qt.PointingHandCursor
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: event => {
                    const modelIndex = tasks.makeModelIndex(task.index);
                    if (event.button === Qt.RightButton)
                        task.openMenu();
                    else if (event.button === Qt.MiddleButton) {
                        if (!task.launcher)
                            tasks.requestClose(modelIndex);
                    } else if (task.model.IsActive)
                        tasks.requestToggleMinimized(modelIndex);
                    else
                        // a pinned application without a window is started
                        tasks.requestActivate(modelIndex);
                }
            }

            DragHandler {
                target: null
                yAxis.enabled: false
                acceptedButtons: Qt.LeftButton
                onActiveTranslationChanged: {
                    if (!active)
                        return;
                    // not past the ends of the row
                    task.dragX = Math.max(-task.place * root.pitch, Math.min((visual.items.count - 1 - task.place) * root.pitch, activeTranslation.x));
                    root.dragTo = task.place + Math.round(task.dragX / root.pitch);
                }
                onActiveChanged: {
                    if (active) {
                        root.dragTo = task.place;
                        root.dragFrom = task.place;
                        return;
                    }
                    const from = root.dragFrom;
                    const to = root.dragTo;
                    root.dragFrom = -1;
                    root.dragTo = -1;
                    task.dragX = 0;
                    if (from >= 0 && to !== from)
                        root.dropped(from, to);
                }
            }
        }
    }
}
