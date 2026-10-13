import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs
import qs.widgets

// The launcher's content. The Dock grows into this when the launcher opens.
// All logic is in the Launcher singleton.
//
// A side bar on the left, each entry an icon and its name: the favourites,
// all applications, each category of them, the places, the session. Beside
// it the chosen one's list; below both the
// search field, where the dock was. Typing searches, as KRunner does, and
// the results take the rail's room too.
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
// activates, Escape closes (the menu first, if that is open). Among results,
// Tab and Shift+Tab walk through the chosen result's actions and on to the
// next result, as in KRunner, and Shift+Enter runs its first action.
Item {
    id: root

    readonly property int margin: 12
    // 48 while a heading stood over the list; the rows have its height now
    readonly property int rowHeight: 52
    // nine rows, not eight: the rail beside them has fourteen icons and two
    // gaps to stand in, and at eight rows its icons had 28 px each
    readonly property int rows: 9
    // an icon and the longest name ("All Applications"), within its border
    readonly property int railWidth: 172

    readonly property bool searching: Launcher.searching
    readonly property var source: searching ? Launcher.results : Launcher.listing
    // what the list shows: `source`, handed over by relist()
    property var shown: []
    // the marked row, if one is: none before the pointer or the arrow keys
    // have chosen one
    readonly property var current: list.marked ? (shown[list.currentIndex] ?? null) : null
    // What Enter is for: the marked row, and among results, with none
    // marked, the first. (In the menu, with none marked, nothing.)
    readonly property var target: current ?? (searching ? (shown[0] ?? null) : null)
    readonly property var currentActions: current?.actions ?? []
    // which of the chosen result's actions Enter runs; -1 is the result itself
    property int activeAction: -1
    // It belongs to the result, not to the row: when another result takes
    // the chosen row's place (new results came in), the action must not
    // carry over to it.
    readonly property string currentKey: current?.key ?? ""
    onCurrentKeyChanged: activeAction = -1
    // the selection was moved by hand since the query last changed; until
    // then it stays on the first result while results keep arriving
    property bool touched: false
    // by the keys, which counts on when the pointer has left the list again
    property bool keyTouched: false
    readonly property bool failed: Launcher.backendFailed && Launcher.runnerMode
    readonly property var category: Launcher.categories.find(category => category.key === Launcher.category) ?? Launcher.categories[0]
    // which list the arrow keys move in: "list" or "rail"
    property string keys: "list"

    // 570 until the side bar had names: the list keeps about the width it had
    implicitWidth: 660
    implicitHeight: margin + body.height + margin + search.height + margin

    function focusSearch() {
        input.forceActiveFocus();
    }

    // Another list: from its top. But results arrive in bursts, each a new
    // list: there a selection made by hand stays on its result, at the same
    // scroll position, if the result is still in it.
    function relist() {
        const key = searching && touched ? currentKey : "";
        // the keys' row is found again too: the pointer may have the
        // selection for now, and gives it back there
        const keyedKey = searching && keyTouched ? (shown[list.keyed]?.key ?? "") : "";
        const scroll = list.contentY;
        shown = source;
        const keyed = keyedKey === "" ? -1 : shown.findIndex(result => result.key === keyedKey);
        if (keyed < 0)
            keyTouched = false;
        let at = key === "" ? -1 : shown.findIndex(result => result.key === key);
        if (at < 0)
            at = keyed;
        if (at < 0) {
            touched = false;
            list.rewind();
            return;
        }
        list.jump = true;
        list.currentIndex = at;
        list.keyed = Math.max(0, keyed);
        list.contentY = Math.max(0, Math.min(scroll, (shown.length - list.maxRows) * list.rowHeight));
        list.jump = false;
    }

    onSourceChanged: relist()
    onSearchingChanged: {
        if (searching)
            keys = "list";
        listIn.restart();
    }
    Component.onCompleted: {
        relist();
        input.text = Launcher.query;
        focusSearch();
        rail.sync();
    }

    Connections {
        target: Launcher

        // set from elsewhere: over IPC, at a runner's request, or emptied
        // for the next opening
        function onQueryChanged() {
            if (input.text !== Launcher.query)
                input.text = Launcher.query;
            root.touched = false;
            root.keyTouched = false;
            list.rewind();
        }

        // reopened before the previous panel had gone
        function onOpenChanged() {
            if (Launcher.open)
                root.focusSearch();
        }
    }

    // Another list altogether (a category chosen, or the search begun or
    // given up) comes in: a short fade and a few pixels' rise, heading and
    // rows together. Put in place at once it was a cut. Not for results
    // that arrive while typing, which are the same list filling up.
    ParallelAnimation {
        id: listIn

        NumberAnimation {
            target: list
            property: "opacity"
            from: 0
            to: 1
            duration: 180
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: listShift
            property: "y"
            from: 6
            to: 0
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    Connections {
        target: Launcher

        function onCategoryChanged() {
            if (!root.searching)
                listIn.restart();
        }
    }

    // What Enter does to the chosen result, for the hint in the search field.
    readonly property string enterText: {
        if (!target)
            return "";
        if (activeAction >= 0)
            return currentActions[activeAction]?.text ?? "";
        if (target.kind === "action")
            return "Run";
        return target.answer ? "Copy" : "Open";
    }

    // The title with the typed words picked out, as styled text.
    function marked(result: var): string {
        const escape = text => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const title = result.title;
        const lower = title.toLowerCase();
        if (result.kind !== "match" || lower.length !== title.length)
            return escape(title);
        const spans = [];
        for (const word of Launcher.query.toLowerCase().split(/\s+/)) {
            const at = word ? lower.indexOf(word) : -1;
            if (at >= 0)
                spans.push([at, at + word.length]);
        }
        spans.sort((a, b) => a[0] - b[0]);
        let out = "", position = 0;
        for (const [from, to] of spans) {
            if (to <= position)
                continue;
            const start = Math.max(from, position);
            out += escape(title.slice(position, start)) + `<font color="${Theme.accent}">` + escape(title.slice(start, to)) + "</font>";
            position = to;
        }
        return out + escape(title.slice(position));
    }

    // What can be done with an application: [{ text, icon, run }].
    function actionsFor(entry: var): var {
        const favorite = Launcher.isFavorite(entry.id);
        const address = "applications:" + entry.id + ".desktop";
        const pinned = Pins.pinned.includes(address);
        const actions = [
            {
                text: "Open",
                icon: "document-open-symbolic",
                run: () => Launcher.launch(entry)
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
        if (keys === "rail" && !searching) {
            rail.step(by, autoRepeat);
        } else {
            touched = true;
            keyTouched = true;
            list.step(by, autoRepeat);
        }
    }

    // through the chosen result's actions, then on to the next result
    function tab(forward: bool, autoRepeat: bool): void {
        if (forward && activeAction < currentActions.length - 1)
            activeAction++;
        else if (!forward && activeAction >= 0)
            activeAction--;
        else
            step(forward ? 1 : -1, autoRepeat);
    }

    Item {
        id: body

        x: root.margin
        y: root.margin
        width: parent.width - root.margin * 2
        height: root.rowHeight * root.rows

        // The side bar and its room while something is typed, and the two
        // ways between. As a state with its transitions, where each step
        // has its time written down: as behaviours of the three values,
        // with pauses that depended on which way it went, the pauses were
        // those of the way before.
        states: State {
            name: "searching"
            when: root.searching

            PropertyChanges {
                railPane.width: 0
                rail.opacity: 0
                rail.x: -18
            }
        }
        transitions: [
            // the side bar goes, then the list takes its room
            Transition {
                to: "searching"

                NumberAnimation {
                    target: rail
                    property: "opacity"
                    duration: 150
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    target: rail
                    property: "x"
                    duration: 220
                    easing.type: Easing.OutCubic
                }

                SequentialAnimation {
                    PauseAnimation {
                        duration: 90
                    }

                    NumberAnimation {
                        target: railPane
                        property: "width"
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                }
            },
            // the list makes room, then the side bar comes
            Transition {
                from: "searching"

                NumberAnimation {
                    target: railPane
                    property: "width"
                    duration: 240
                    easing.type: Easing.OutCubic
                }

                SequentialAnimation {
                    PauseAnimation {
                        duration: 120
                    }

                    NumberAnimation {
                        target: rail
                        properties: "opacity,x"
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
            }
        ]

        // ---- the rail ----------------------------------------------------

        // ---- the side bar ------------------------------------------------

        // Three groups: the favourites and all applications on top, the
        // categories under them, and at the bottom, where the bar has the
        // session's button, what is not applications. As one undivided
        // column of fourteen icons without names it was a list to be read
        // through each time. (The names were first shown in a bubble beside
        // the icon under the pointer, then by the rail coming out over the
        // list when the pointer rested on it; there is room to have them
        // there always.)
        //
        // The pane is the room it has beside the list, and gives that up
        // while something is typed (the body's state "searching"). The side
        // bar is not squeezed by it: it fades and steps aside, and the list
        // takes the room when it has mostly gone; coming back, the list
        // makes room first. (The room was given and taken in the panels'
        // own movement, 500 ms and a little past the mark, with the side
        // bar cut off by its edge.)
        Item {
            id: railPane

            width: root.railWidth + 12
            height: parent.height

            Item {
                id: rail

                visible: opacity > 0

                readonly property int count: Launcher.categories.length
                readonly property int first: Launcher.categories.filter(category => category.part === "first").length
                readonly property int last: Launcher.categories.filter(category => category.part === "last").length
                // between the groups, with a line in it
                readonly property int gap: 14
                // between the border and the entries
                readonly property int pad: 6
                // as tall as there is room for
                readonly property int cell: Math.max(24, Math.min(32, Math.floor((height - pad * 2 - gap * 2) / Math.max(1, count))))

                property int currentIndex: 0
                // set by sync(), not by a move in the rail
                property bool syncing: false
                // The entry the pointer is on, once it has moved there: -1
                // for none. A pointer that happens to be here when the
                // launcher opens marks nothing.
                property int hovered: -1
                property real lastRepeat: 0

                // the last group stands at the bottom, whatever is above it
                function cellY(index: int): real {
                    if (index >= count - last)
                        return height - pad - (count - index) * cell;
                    return pad + index * cell + (index >= first ? gap : 0);
                }

                // the entry of what is shown
                function sync(): void {
                    const at = Launcher.categories.findIndex(category => category.key === Launcher.category);
                    syncing = true;
                    currentIndex = Math.max(0, at);
                    syncing = false;
                }

                // a held key steps no faster than in the list (see PickList)
                function step(by: int, autoRepeat: bool): void {
                    const now = Date.now();
                    if (autoRepeat && now - lastRepeat < 66)
                        return;
                    lastRepeat = now;
                    currentIndex = Math.max(0, Math.min(count - 1, currentIndex + by));
                }

                width: root.railWidth
                height: parent.height
                // only how many there are: marking a favourite then leaves
                // the rail as it is
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

                // A card with a rounded border, as an application's menu
                // has: it was what the rail lay on while it came out over
                // the list, and was liked better than the bare column. With
                // a little shadow under it, the frame's own in small, so
                // that it stands on the panel and is not only drawn on it.
                // On glass the card is glass too, and has its border alone:
                // the shadow lies under all of it and would show through.
                Rectangle {
                    anchors.fill: parent
                    radius: 15
                    color: Theme.card(Theme.bg)
                    border.width: 1.5
                    border.color: Theme.surfaceHover
                    layer.enabled: !Theme.glass
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        blurMax: 12
                        shadowVerticalOffset: 1.5
                        shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity * 0.7)
                    }
                }

                // Under the pointer: one grey bar that goes with it from
                // entry to entry, as the list's goes from row to row, in the
                // same time. (A bar of its own in every entry, fading in and
                // out where it was, came first: beside the list's it was a
                // different thing happening.) Not on the chosen entry, which
                // has its own.
                Rectangle {
                    id: pointedBar

                    // where it is, or was last
                    property int index: 0

                    x: rail.pad
                    y: rail.cellY(index) + 1
                    width: rail.width - rail.pad * 2
                    height: rail.cell - 2
                    radius: 10
                    color: Theme.surface
                    opacity: rail.hovered >= 0 && rail.hovered !== rail.currentIndex ? 1 : 0

                    // it appears where the pointer comes in, and only then moves
                    Behavior on y {
                        enabled: pointedBar.opacity > 0

                        NumberAnimation {
                            duration: Theme.followDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 60
                        }
                    }

                    Connections {
                        target: rail

                        function onHoveredChanged() {
                            if (rail.hovered >= 0)
                                pointedBar.index = rail.hovered;
                        }
                    }
                }

                // The chosen one: in the accent's colour, not the list's
                // grey. Two grey bars side by side read as two selections.
                Rectangle {
                    x: rail.pad
                    y: rail.cellY(rail.currentIndex) + 1
                    width: rail.width - rail.pad * 2
                    height: rail.cell - 2
                    radius: 10
                    color: Qt.alpha(Theme.accent, root.keys === "rail" ? 0.28 : 0.16)

                    Behavior on y {
                        NumberAnimation {
                            duration: Theme.fadeDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.fadeCurve
                        }
                    }

                    Behavior on color {
                        ColorAnim {}
                    }
                }

                Repeater {
                    model: [rail.pad + rail.first * rail.cell + rail.gap / 2, rail.height - rail.pad - rail.last * rail.cell - rail.gap / 2]

                    Rectangle {
                        required property real modelData

                        x: rail.pad + 12
                        y: modelData - height / 2
                        width: rail.width - (rail.pad + 12) * 2
                        height: 1.5
                        color: Theme.surface
                    }
                }

                Repeater {
                    model: rail.count

                    Item {
                        id: entry

                        required property int index
                        readonly property var category: Launcher.categories[index] ?? ({})
                        readonly property bool chosen: rail.currentIndex === index
                        readonly property bool pointed: rail.hovered === index
                        // brighter under the pointer, and all of them while the keys are here
                        readonly property color tone: root.keys === "rail" || pointed ? Theme.fg : Theme.fgDim

                        y: rail.cellY(index)
                        width: rail.width
                        height: rail.cell

                        Icon {
                            id: entryIcon

                            x: rail.pad + 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 21
                            height: 21
                            source: entry.category.icon ?? ""
                            color: entry.chosen ? Theme.accent : entry.tone

                            Behavior on color {
                                HoverAnim {}
                            }
                        }

                        Label {
                            anchors {
                                left: entryIcon.right
                                leftMargin: 12
                                right: parent.right
                                rightMargin: rail.pad + 9
                                verticalCenter: parent.verticalCenter
                            }
                            font.pixelSize: 13
                            color: entry.chosen ? Theme.fg : entry.tone
                            text: entry.category.title ?? ""

                            Behavior on color {
                                HoverAnim {}
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            // Under the pointer an entry is only marked: a
                            // click shows its list. (Shown on the way
                            // across, the list changed with every entry the
                            // pointer passed.)
                            hoverEnabled: true
                            onPositionChanged: rail.hovered = entry.index
                            onExited: {
                                if (rail.hovered === entry.index)
                                    rail.hovered = -1;
                            }
                            onClicked: {
                                rail.currentIndex = entry.index;
                                root.keys = "list";
                            }
                        }
                    }
                }
            }
        }

        // ---- the list ----------------------------------------------------

        // No heading over it: the side bar says which list this is, and for
        // results there is nothing to say. (There was one, the name and how
        // many, from when the rail was icons alone.)
        PickList {
            id: list

            anchors {
                top: parent.top
                left: railPane.right
                right: parent.right
            }
            rowHeight: root.rowHeight
            maxRows: root.rows
            model: root.shown
            // the rail has the keys: no row here is the chosen one
            highlighted: root.keys === "list" || root.searching
            // and none is before the pointer or the arrow keys choose one
            lazy: true
            // the pointer's selection is over
            onPointerLeft: root.touched = root.keyTouched
            transform: Translate {
                id: listShift
            }

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property bool selected: ListView.isCurrentItem && list.highlighted && list.marked
                // the first row of each category of results names it
                readonly property string category: modelData.category ?? ""
                readonly property bool heading: category !== "" && category !== (root.shown[index - 1]?.category ?? "")
                // a result's own actions, as buttons while it is the chosen one
                readonly property var actions: modelData.actions ?? []
                readonly property bool showsActions: selected && actions.length > 0

                width: list.width
                height: root.rowHeight

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // Real pointer movement selects the row under it, without
                    // scrolling. A still pointer selects nothing, so the wheel or
                    // the keyboard can move the list underneath it.
                    onPositionChanged: mouse => {
                        root.keys = "list";
                        const before = list.currentIndex;
                        list.hover(row.index, mapToItem(null, mouse.x, mouse.y));
                        if (list.currentIndex !== before)
                            root.touched = true;
                    }
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            Launcher.submit(row.modelData, row.index, -1);
                            return;
                        }
                        const entry = Launcher.entryOf(row.modelData);
                        if (entry) {
                            // the menu is for the row it is opened on, and
                            // that row stays chosen with the pointer on the menu
                            root.keys = "list";
                            root.touched = true;
                            root.keyTouched = true;
                            list.choose(row.index);
                            menu.show(root.actionsFor(entry), mapToItem(root, mouse.x, mouse.y));
                        }
                    }
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 12 + (trailing.width > 0 ? trailing.width + 12 : 0)
                    }
                    spacing: 12

                    // symbolic icons are drawn smaller, in the text colour
                    Item {
                        implicitWidth: 33
                        implicitHeight: 33

                        Icon {
                            id: icon

                            anchors.centerIn: parent
                            width: row.modelData.symbolic ? 21 : 33
                            height: width
                            visible: valid
                            source: row.modelData.icon
                            // no stand-in of Kirigami's own: `valid` should say
                            // whether the row's icon exists
                            fallback: ""
                            colorize: row.modelData.symbolic
                        }

                        // for a row without a usable icon (a runner may give an
                        // empty one: browser tabs and history)
                        Icon {
                            readonly property bool symbolic: String(source).endsWith("-symbolic")

                            anchors.centerIn: parent
                            width: symbolic ? 21 : 33
                            height: width
                            visible: !icon.valid
                            source: row.modelData.fallbackIcon ?? "application-x-executable"
                            colorize: symbolic
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Label {
                            Layout.fillWidth: true
                            font.pixelSize: 14
                            textFormat: Text.StyledText
                            text: root.marked(row.modelData)
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            color: Theme.fgDim
                            font.pixelSize: 12
                            textFormat: Text.PlainText
                            text: row.modelData.subtitle
                        }
                    }
                }

                // at the row's end: its actions while chosen, else its category
                Item {
                    id: trailing

                    anchors {
                        right: parent.right
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    width: row.showsActions ? actions.implicitWidth : (category.visible ? category.implicitWidth : 0)
                    height: row.height

                    Label {
                        id: category

                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        visible: row.heading && !row.showsActions
                        color: Theme.fgDim
                        font.pixelSize: 11
                        text: row.category
                    }

                    Row {
                        id: actions

                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: Theme.spacing
                        visible: row.showsActions

                        Repeater {
                            model: row.showsActions ? row.actions : []

                            Rectangle {
                                id: button

                                required property var modelData
                                required property int index

                                readonly property bool active: root.activeAction === index

                                width: 30
                                height: 30
                                radius: 9
                                color: active ? Theme.accent : (buttonMouse.containsMouse ? Theme.surfaceActive : Theme.surfaceHover)

                                Behavior on color {
                                    HoverAnim {}
                                }

                                Icon {
                                    anchors.centerIn: parent
                                    source: button.modelData.icon
                                    fallback: "system-run-symbolic"
                                    color: button.active ? Theme.accentFg : Theme.fg
                                }

                                MouseArea {
                                    id: buttonMouse

                                    cursorShape: Qt.PointingHandCursor
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    // the hint in the search field then says what the button does
                                    onEntered: root.activeAction = button.index
                                    onClicked: Launcher.submit(row.modelData, row.index, button.index)
                                }
                            }
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
            // while runners are still answering there is nothing to say yet
            visible: list.count === 0 && (!root.searching || root.failed || !Launcher.querying)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            color: root.failed ? Theme.error : Theme.fgDim
            text: {
                if (root.failed)
                    return "KRunner's search (org.kde.milou) is not loadable; see `qs log`";
                if (root.searching)
                    return `Nothing found for "${Launcher.query.trim()}"`;
                if (Launcher.category === "favorites")
                    return "No favorites yet. An application's menu, on a right click, makes it one.";
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
        color: Theme.card(Theme.surface)
        border.width: Theme.fieldBorder
        border.color: Theme.surfaceHover

        Icon {
            id: searchIcon

            anchors {
                left: parent.left
                leftMargin: 15
                verticalCenter: parent.verticalCenter
            }
            source: "search-symbolic"
            // lit while runners are still answering
            color: Launcher.querying ? Theme.accent : Theme.fgDim

            Behavior on color {
                ColorAnim {}
            }
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
            text: "Search apps, windows, settings, the web  ·  > actions"
        }

        // what the keys do to the chosen result
        RowLayout {
            id: hints

            anchors {
                right: parent.right
                rightMargin: 15
                verticalCenter: parent.verticalCenter
            }
            spacing: 15
            visible: root.searching && list.count > 0

            KeyHint {
                key: "⇧↵"
                keyColor: Theme.surfaceHover
                text: root.activeAction < 0 ? (root.currentActions[0]?.text ?? "") : ""
            }

            KeyHint {
                key: "↵"
                keyColor: Theme.surfaceHover
                text: root.enterText
            }
        }

        TextInput {
            id: input

            anchors {
                left: searchIcon.right
                leftMargin: Theme.padding
                right: hints.visible ? hints.left : parent.right
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
                // the chosen row's application, if it is one
                const entry = Launcher.entryOf(root.current);
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    // Shift+Enter is the first action, where there is one
                    const first = (event.modifiers & Qt.ShiftModifier) && root.currentActions.length > 0;
                    if (event.isAutoRepeat) {
                        // one press, one start
                    } else if (menu.open) {
                        menu.run(menu.index);
                    } else {
                        Launcher.submit(root.target, root.current ? list.currentIndex : 0, first ? 0 : root.activeAction);
                    }
                    event.accepted = true;
                    return;
                }
                // the Menu key, or Shift+F10: the menu of the chosen application
                if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                    if (menu.open)
                        menu.open = false;
                    else if (entry && list.currentItem) {
                        // the row may be the pointer's: it stays chosen
                        root.keyTouched = root.touched;
                        list.choose(list.currentIndex);
                        menu.show(root.actionsFor(entry), list.currentItem.mapToItem(root, list.width - 240, root.rowHeight / 2));
                    }
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
                else if (event.key === Qt.Key_Tab)
                    root.tab(true, event.isAutoRepeat);
                else if (event.key === Qt.Key_Backtab)
                    root.tab(false, event.isAutoRepeat);
                else if (control && (event.key === Qt.Key_N || event.key === Qt.Key_J))
                    root.step(1, event.isAutoRepeat);
                else if (control && (event.key === Qt.Key_P || event.key === Qt.Key_K))
                    root.step(-1, event.isAutoRepeat);
                else if (event.key === Qt.Key_PageDown)
                    root.step(root.rows, event.isAutoRepeat);
                else if (event.key === Qt.Key_PageUp)
                    root.step(-root.rows, event.isAutoRepeat);
                else if (control && event.key === Qt.Key_D && entry)
                    Launcher.toggleFavorite(entry.id);
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
                            HoverAnim {}
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
