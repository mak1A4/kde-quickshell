import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// The launcher's content. The Dock grows into this when the launcher opens.
// All logic is in the Launcher singleton.
//
// A rail of icons on the left, as the bar is one on the right: the
// favourites, all applications, each category of them, the places, the
// session. Beside it the chosen one's name and its list; below both the
// search field, where the dock was. Typing searches, and the results take
// the rail's room too.
//
// It has what KDE's menu has, and was first laid out as that is (a row for
// the user and the search on top, the categories as a list of names, a row
// of buttons at the bottom): that was KDE's menu in other colours.
//
// A right click on an application, or the Menu key, opens a menu for it: its
// own actions (a new window, ...), favourite or not, pinned to the dock or
// not. The menu is drawn in this panel, not a window of its own.
//
// Keys: Up/Down or Ctrl+P/N/K/J move in the list that has the keys, Left/Right
// (while nothing is typed) or Tab change between the rail and the list,
// PageUp/PageDown jump, Ctrl+D marks or unmarks a favourite, Enter
// activates, Escape closes (the menu first, if that is open).
Item {
    id: root

    readonly property int margin: 12
    readonly property int rowHeight: 48
    readonly property int rows: 8
    readonly property int railWidth: 42
    readonly property int headHeight: 36

    readonly property bool searching: Launcher.query.trim() !== ""
    readonly property var shown: searching ? Launcher.results : Launcher.listing
    readonly property var category: Launcher.categories.find(category => category.key === Launcher.category) ?? Launcher.categories[0]
    // which list the arrow keys move in: "list" or "rail"
    property string keys: "list"

    implicitWidth: 570
    implicitHeight: margin + body.height + margin + search.height + margin

    function focusSearch() {
        input.forceActiveFocus();
    }

    // another list: from its top
    onShownChanged: list.rewind()
    onSearchingChanged: {
        if (searching)
            keys = "list";
    }
    Component.onCompleted: {
        focusSearch();
        rail.sync();
    }

    // What can be done with an application: [{ text, icon, run }].
    function actionsFor(result: var): var {
        const entry = result.entry;
        const favorite = Launcher.isFavorite(entry.id);
        const address = "applications:" + entry.id + ".desktop";
        const pinned = Pins.pinned.includes(address);
        const actions = [
            {
                text: "Open",
                icon: "document-open-symbolic",
                run: () => Launcher.activate(result)
            }
        ];
        // What the application offers itself: a new window, a private one, ...
        // One that names no icon has the application's.
        for (const action of entry.actions)
            actions.push({
                text: action.name,
                icon: action.icon || entry.icon,
                run: () => {
                    action.execute();
                    LastWindow.expectWindow();
                    Launcher.hide();
                }
            });
        actions.push({
            text: favorite ? "Remove from Favorites" : "Add to Favorites",
            icon: favorite ? "non-starred-symbolic" : "starred-symbolic",
            run: () => Launcher.toggleFavorite(entry.id)
        });
        actions.push({
            text: pinned ? "Unpin from Dock" : "Pin to Dock",
            icon: pinned ? "window-unpin-symbolic" : "window-pin-symbolic",
            run: () => Pins.store(pinned ? Pins.pinned.filter(other => other !== address) : Pins.pinned.concat([address]))
        });
        return actions;
    }

    function step(by: int, autoRepeat: bool): void {
        if (menu.open) {
            menu.index = Math.max(0, Math.min(menu.actions.length - 1, menu.index + by));
            return;
        }
        if (keys === "rail" && !searching)
            rail.step(by, autoRepeat);
        else
            list.step(by, autoRepeat);
    }

    Item {
        id: body

        x: root.margin
        y: root.margin
        width: parent.width - root.margin * 2
        height: root.headHeight + root.rowHeight * root.rows

        // ---- the rail ----------------------------------------------------

        Item {
            id: railPane

            width: root.searching ? 0 : root.railWidth + 9
            height: parent.height
            opacity: root.searching ? 0 : 1
            visible: opacity > 0
            clip: true

            Behavior on width {
                Anim {}
            }

            Behavior on opacity {
                Anim {
                    kind: Anim.Fade
                }
            }

            PickList {
                id: rail

                // set by sync(), not by a move in the list
                property bool syncing: false

                // the icon of what is shown
                function sync(): void {
                    const at = Launcher.categories.findIndex(category => category.key === Launcher.category);
                    syncing = true;
                    jump = true;
                    currentIndex = Math.max(0, at);
                    jump = false;
                    syncing = false;
                }

                width: root.railWidth
                rowHeight: 30
                maxRows: Math.floor(body.height / rowHeight)
                // only how many there are: marking a favourite then leaves
                // the rail as it is
                model: Launcher.categories.length
                onCountChanged: sync()
                onCurrentIndexChanged: {
                    if (!syncing && Launcher.categories[currentIndex])
                        Launcher.category = Launcher.categories[currentIndex].key;
                }

                Connections {
                    target: Launcher

                    function onCategoryChanged() {
                        rail.sync();
                    }
                }

                delegate: Item {
                    id: entry

                    required property int index
                    readonly property var category: Launcher.categories[index] ?? ({})
                    readonly property bool chosen: rail.currentIndex === index

                    width: rail.width
                    height: rail.rowHeight

                    Icon {
                        anchors.centerIn: parent
                        source: entry.category.icon ?? ""
                        color: entry.chosen ? Theme.accent : (root.keys === "rail" || entryMouse.containsMouse ? Theme.fg : Theme.fgDim)

                        Behavior on color {
                            ColorAnim {}
                        }
                    }

                    MouseArea {
                        id: entryMouse

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        // under the pointer an icon only brightens: a click
                        // shows its list. (Shown on the way across, the list
                        // changed with every icon the pointer passed.)
                        hoverEnabled: true
                        onClicked: {
                            rail.currentIndex = entry.index;
                            root.keys = "list";
                        }
                    }
                }
            }
        }

        // ---- what is listed, by name, and the list -----------------------

        Item {
            id: head

            anchors {
                left: railPane.right
                right: parent.right
            }
            height: root.headHeight

            Label {
                id: headTitle

                x: 12
                y: 6
                font.pixelSize: 15
                font.bold: true
                text: root.searching ? "Results" : (root.category?.title ?? "")
            }

            Label {
                anchors {
                    left: headTitle.right
                    leftMargin: 9
                    baseline: headTitle.baseline
                }
                color: Theme.fgDim
                font.pixelSize: 12
                text: list.count > 0 ? list.count : ""
            }
        }

        PickList {
            id: list

            anchors {
                top: head.bottom
                left: railPane.right
                right: parent.right
            }
            rowHeight: root.rowHeight
            maxRows: root.rows
            model: root.shown
            // the rail has the keys: no row here is the chosen one
            highlighted: (root.keys === "list" || root.searching) && currentItem?.modelData.kind !== "none"

            delegate: Item {
                id: row

                required property var modelData
                required property int index
                readonly property bool app: modelData.kind === "app"

                width: list.width
                height: root.rowHeight

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 12
                    }
                    spacing: 12

                    Icon {
                        readonly property int size: row.modelData.symbolic ? 21 : 33

                        Layout.leftMargin: (33 - size) / 2
                        Layout.rightMargin: (33 - size) / 2
                        implicitWidth: size
                        implicitHeight: size
                        source: row.modelData.icon
                        fallback: "application-x-executable"
                        colorize: row.modelData.symbolic
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Label {
                            Layout.fillWidth: true
                            font.pixelSize: row.modelData.kind === "calc" ? 18 : 14
                            font.bold: row.modelData.kind === "calc"
                            text: row.modelData.title
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            color: Theme.fgDim
                            font.pixelSize: 12
                            text: row.modelData.subtitle
                        }
                    }
                }

                MouseArea {
                    id: rowMouse

                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // Real pointer movement selects the row under it, without
                    // scrolling. A still pointer selects nothing, so the wheel or
                    // the keyboard can move the list underneath it.
                    onPositionChanged: mouse => {
                        root.keys = "list";
                        list.hover(row.index, mapToItem(null, mouse.x, mouse.y));
                    }
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            Launcher.activate(row.modelData);
                        } else if (row.app) {
                            // the menu is for the row it is opened on
                            root.keys = "list";
                            list.currentIndex = row.index;
                            menu.show(root.actionsFor(row.modelData), mapToItem(root, mouse.x, mouse.y));
                        }
                    }
                }
            }
        }

        // nothing to list
        Label {
            anchors {
                left: railPane.right
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 24
            }
            visible: list.count === 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            color: Theme.fgDim
            text: {
                if (root.searching)
                    return `Nothing matches "${Launcher.query.trim()}"`;
                if (Launcher.category === "favorites")
                    return "No favorites yet. The star at the end of an application's row makes it one.";
                return "Nothing here";
            }
        }
    }

    // ---- the search, where the dock was ----------------------------------

    Rectangle {
        id: search

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: root.margin
        }
        height: 45
        radius: height / 2
        color: Theme.surface

        Icon {
            id: searchIcon

            anchors {
                left: parent.left
                leftMargin: 15
                verticalCenter: parent.verticalCenter
            }
            source: "search-symbolic"
            color: Theme.fgDim
        }

        Label {
            anchors {
                left: input.left
                right: input.right
                verticalCenter: parent.verticalCenter
            }
            visible: input.text === ""
            color: Theme.fgDim
            font.pixelSize: 14
            text: "Search apps  ·  > actions  ·  = calculate"
        }

        TextInput {
            id: input

            anchors {
                left: searchIcon.right
                leftMargin: Theme.padding
                right: parent.right
                rightMargin: 15
                verticalCenter: parent.verticalCenter
            }
            clip: true
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.accentFg
            font.pixelSize: 14
            focus: true
            onTextChanged: Launcher.query = text
            onAccepted: {
                if (menu.open)
                    menu.run(menu.index);
                else
                    Launcher.activate(root.shown[list.currentIndex]);
            }

            Keys.onUpPressed: event => root.step(-1, event.isAutoRepeat)
            Keys.onDownPressed: event => root.step(1, event.isAutoRepeat)
            Keys.onEscapePressed: {
                if (menu.open)
                    menu.open = false;
                else
                    Launcher.hide();
            }
            Keys.onPressed: event => {
                const control = event.modifiers & Qt.ControlModifier;
                const chosen = root.shown[list.currentIndex];
                // the Menu key, or Shift+F10: the menu of the chosen application
                if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                    if (menu.open)
                        menu.open = false;
                    else if (chosen?.kind === "app" && list.currentItem)
                        menu.show(root.actionsFor(chosen), list.currentItem.mapToItem(root, list.width - 240, root.rowHeight / 2));
                    event.accepted = true;
                    return;
                }
                // any other key but the arrows and Enter is for the list again
                if (menu.open && event.key !== Qt.Key_Shift && event.key !== Qt.Key_Control)
                    menu.open = false;
                // in an empty field there is no cursor to move
                const free = text === "";
                if (free && event.key === Qt.Key_Left)
                    root.keys = "rail";
                else if (free && event.key === Qt.Key_Right)
                    root.keys = "list";
                else if (!root.searching && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab))
                    root.keys = root.keys === "list" ? "rail" : "list";
                else if (control && (event.key === Qt.Key_N || event.key === Qt.Key_J))
                    root.step(1, event.isAutoRepeat);
                else if (control && (event.key === Qt.Key_P || event.key === Qt.Key_K))
                    root.step(-1, event.isAutoRepeat);
                else if (event.key === Qt.Key_PageDown)
                    root.step(root.rows, event.isAutoRepeat);
                else if (event.key === Qt.Key_PageUp)
                    root.step(-root.rows, event.isAutoRepeat);
                else if (control && event.key === Qt.Key_D && root.shown[list.currentIndex]?.kind === "app")
                    Launcher.toggleFavorite(root.shown[list.currentIndex].entry.id);
                else
                    return;
                event.accepted = true;
            }
        }
    }

    // ---- the menu of an application --------------------------------------

    // Drawn here, over the lists, and not a popup window as the dock's
    // menus are: the launcher holds the keyboard, and a window of its own
    // would have to take it away and give it back.
    Item {
        id: menu

        // [{ text, icon, run }]
        property var actions: []
        // the entry the keys have chosen
        property int index: 0
        property bool open: false
        // where it was asked for
        property point at: Qt.point(0, 0)

        function show(actions: var, at: point): void {
            menu.actions = actions;
            menu.at = at;
            index = 0;
            open = true;
        }

        function run(index: int): void {
            const action = actions[index];
            open = false;
            if (action)
                action.run();
        }

        anchors.fill: parent
        opacity: open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                kind: Anim.Fade
            }
        }

        // a click anywhere else closes it, and does nothing else
        MouseArea {
            anchors.fill: parent
            enabled: menu.open
            acceptedButtons: Qt.AllButtons
            onPressed: menu.open = false
        }

        Rectangle {
            // at the pointer, and within the panel
            x: Math.max(6, Math.min(root.width - width - 6, menu.at.x))
            y: Math.max(6, Math.min(root.height - height - 6, menu.at.y))
            width: Math.max(192, entries.implicitWidth) + Theme.spacing * 2
            height: entries.implicitHeight + Theme.spacing * 2
            radius: Theme.radius * 2
            color: Theme.bg
            border.width: 1.5
            border.color: Theme.surfaceHover

            // clicks between the entries stay here
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            ColumnLayout {
                id: entries

                x: Theme.spacing
                y: Theme.spacing
                width: parent.width - Theme.spacing * 2
                spacing: 0

                Repeater {
                    model: menu.actions

                    Rectangle {
                        id: action

                        required property var modelData
                        required property int index
                        readonly property bool chosen: menu.index === index

                        Layout.fillWidth: true
                        implicitWidth: actionRow.implicitWidth + 24
                        implicitHeight: 33
                        radius: Theme.radius
                        color: chosen ? Theme.surface : Theme.none

                        Behavior on color {
                            ColorAnim {
                                duration: Theme.followDuration
                            }
                        }

                        Row {
                            id: actionRow

                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 9

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: action.modelData.icon || "application-x-executable"
                                // an application's own actions bring icons in colour
                                colorize: String(action.modelData.icon).endsWith("-symbolic")
                                opacity: action.modelData.icon ? 1 : 0
                            }

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: action.modelData.text
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onPositionChanged: menu.index = action.index
                            onClicked: menu.run(action.index)
                        }
                    }
                }
            }
        }
    }
}
