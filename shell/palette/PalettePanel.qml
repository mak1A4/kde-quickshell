import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// The command palette's content: a search field with the results below it,
// hanging from the top frame edge. All logic is in the CommandPalette singleton.
//
// Keys: Up/Down or Ctrl+P/N/K/J move, PageUp/PageDown jump, Enter runs the
// selected result, Shift+Enter its first action, Escape closes. Tab and
// Shift+Tab walk through the selected result's actions and on to the next
// result, as in KRunner. In the clipboard history, Backspace in the empty
// field goes back to searching.
Item {
    id: root

    readonly property var results: CommandPalette.results
    // what the list shows: `results`, handed over by show()
    property var shown: []
    readonly property var current: shown[list.currentIndex] ?? null
    readonly property var currentActions: current?.actions ?? []
    // which of the selected result's actions Enter runs; -1 is the result itself
    property int activeAction: -1
    // It belongs to the result, not to the row: when another result takes
    // the selected row's place (new results came in), the action must not
    // carry over to it.
    readonly property string currentKey: current?.key ?? ""
    onCurrentKeyChanged: activeAction = -1
    // the selection was moved by hand since the query last changed; until
    // then it stays on the first result while results keep arriving
    property bool touched: false
    readonly property int margin: 12
    readonly property bool failed: CommandPalette.backendFailed && CommandPalette.runnerMode && CommandPalette.query.trim() !== ""

    implicitWidth: 660
    implicitHeight: column.implicitHeight + margin * 2

    function focusSearch() {
        input.forceActiveFocus();
    }

    // Results arrive in bursts, each a new list. A selection made by hand
    // stays on its result, at the same scroll position, if the result is
    // still there; otherwise the first result is selected.
    function show() {
        const key = touched ? currentKey : "";
        const scroll = list.contentY;
        shown = results;
        const at = key === "" ? -1 : shown.findIndex(result => result.key === key);
        if (at < 0) {
            touched = false;
            list.rewind();
            return;
        }
        list.jump = true;
        list.currentIndex = at;
        list.contentY = Math.max(0, Math.min(scroll, (shown.length - list.maxRows) * list.rowHeight));
        list.jump = false;
    }

    onResultsChanged: show()

    function step(by, autoRepeat) {
        touched = true;
        list.step(by, autoRepeat);
    }

    function tab(forward, autoRepeat) {
        if (forward && activeAction < currentActions.length - 1)
            activeAction++;
        else if (!forward && activeAction >= 0)
            activeAction--;
        else
            step(forward ? 1 : -1, autoRepeat);
    }

    // What Enter does to the selected result, for the footer.
    readonly property string enterText: {
        if (!current)
            return "";
        if (activeAction >= 0)
            return currentActions[activeAction]?.text ?? "";
        if (current.kind === "action")
            return "Run";
        if (current.kind === "clip")
            return "Copy";
        return current.answer ? "Copy" : "Open";
    }

    // The title with the typed words picked out, as styled text.
    function marked(result) {
        const escape = text => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const title = result.title;
        const lower = title.toLowerCase();
        if ((result.kind !== "match" && result.kind !== "clip") || result.image || lower.length !== title.length)
            return escape(title);
        const spans = [];
        for (const word of CommandPalette.query.toLowerCase().split(/\s+/)) {
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

    Component.onCompleted: {
        show();
        input.text = CommandPalette.query;
        focusSearch();
    }

    Connections {
        target: CommandPalette

        // set from elsewhere: over IPC, or at a runner's request
        function onQueryChanged() {
            if (input.text !== CommandPalette.query)
                input.text = CommandPalette.query;
            root.touched = false;
            list.rewind();
        }

        // reopened before the previous panel had faded away
        function onOpenChanged() {
            if (CommandPalette.open)
                root.focusSearch();
        }
    }

    Column {
        id: column

        x: root.margin
        y: root.margin
        width: root.implicitWidth - root.margin * 2
        spacing: root.margin

        Rectangle {
            id: search

            width: parent.width
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
                source: CommandPalette.clipboardMode ? "edit-paste-symbolic" : "search-symbolic"
                // lit while runners are still answering
                color: CommandPalette.querying ? Theme.accent : Theme.fgDim

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
                text: CommandPalette.clipboardMode ? "Search the clipboard history" : "Search apps, windows, settings, the web  ·  > shell actions"
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
                onTextChanged: CommandPalette.query = text

                Keys.onUpPressed: event => root.step(-1, event.isAutoRepeat)
                Keys.onDownPressed: event => root.step(1, event.isAutoRepeat)
                Keys.onEscapePressed: CommandPalette.hide()
                Keys.onPressed: event => {
                    const control = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Backspace && input.text === "" && CommandPalette.clipboardMode) {
                        CommandPalette.mode = "";
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        // Shift+Enter is the first action, where there is one
                        const first = (event.modifiers & Qt.ShiftModifier) && root.currentActions.length > 0;
                        if (!event.isAutoRepeat)
                            CommandPalette.submit(list.currentIndex, first ? 0 : root.activeAction);
                    } else if (event.key === Qt.Key_Tab)
                        root.tab(true, event.isAutoRepeat);
                    else if (event.key === Qt.Key_Backtab)
                        root.tab(false, event.isAutoRepeat);
                    else if (control && (event.key === Qt.Key_N || event.key === Qt.Key_J))
                        root.step(1, event.isAutoRepeat);
                    else if (control && (event.key === Qt.Key_P || event.key === Qt.Key_K))
                        root.step(-1, event.isAutoRepeat);
                    else if (event.key === Qt.Key_PageDown)
                        root.step(list.maxRows, event.isAutoRepeat);
                    else if (event.key === Qt.Key_PageUp)
                        root.step(-list.maxRows, event.isAutoRepeat);
                    else
                        return;
                    event.accepted = true;
                }
            }
        }

        PickList {
            id: list

            width: parent.width
            visible: count > 0
            model: root.shown

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property bool selected: ListView.isCurrentItem
                // the first row of each category names it
                readonly property bool heading: modelData.category !== "" && modelData.category !== (root.shown[index - 1]?.category ?? "")
                readonly property bool showsActions: selected && modelData.actions.length > 0

                width: list.width
                height: list.rowHeight

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    hoverEnabled: true
                    // real pointer movement selects the row under it, see PickList
                    onPositionChanged: mouse => {
                        const before = list.currentIndex;
                        list.hover(row.index, mapToItem(null, mouse.x, mouse.y));
                        if (list.currentIndex !== before)
                            root.touched = true;
                    }
                    onClicked: CommandPalette.submit(row.index, -1)
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: Theme.padding
                        rightMargin: Theme.padding + (trailing.width > 0 ? trailing.width + 12 : 0)
                    }
                    spacing: 12

                    // symbolic icons are drawn smaller, in the text colour; a
                    // clipboard image is shown itself, wider than an icon
                    Item {
                        implicitWidth: thumbnail.visible ? 72 : 36
                        implicitHeight: thumbnail.visible ? 42 : 36

                        Image {
                            id: thumbnail

                            anchors.fill: parent
                            visible: (row.modelData.image ?? "") !== ""
                            source: visible ? "file://" + row.modelData.image : ""
                            // decoded at twice the size shown, not at full size
                            sourceSize.height: 84
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            clip: true
                        }

                        Icon {
                            id: icon

                            anchors.centerIn: parent
                            width: row.modelData.symbolic ? 24 : 36
                            height: width
                            visible: valid && !thumbnail.visible
                            source: row.modelData.icon
                            // no stand-in of Kirigami's own: `valid` should say
                            // whether the result's icon exists
                            fallback: ""
                            colorize: row.modelData.symbolic
                        }

                        // for a result without a usable icon
                        Icon {
                            readonly property bool symbolic: String(source).endsWith("-symbolic")

                            anchors.centerIn: parent
                            width: symbolic ? 24 : 36
                            height: width
                            visible: !icon.valid && !thumbnail.visible
                            source: row.modelData.fallbackIcon ?? "search-symbolic"
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

                // at the row's end: its actions while selected, else its category
                Item {
                    id: trailing

                    anchors {
                        right: parent.right
                        rightMargin: Theme.padding
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
                        text: row.modelData.category
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
                            model: row.showsActions ? row.modelData.actions : []

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
                                    ColorAnim {}
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
                                    // the footer then says what the button does
                                    onEntered: root.activeAction = button.index
                                    onClicked: CommandPalette.submit(row.index, button.index)
                                }
                            }
                        }
                    }
                }
            }
        }

        // nothing matched, or KRunner's search is not available
        Label {
            width: parent.width
            height: list.rowHeight
            visible: list.count === 0 && CommandPalette.query.trim() !== "" && (root.failed || !CommandPalette.querying)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: root.failed ? Theme.error : Theme.fgDim
            text: root.failed ? "KRunner's search (org.kde.milou) is not loadable; see `qs log`" : `Nothing found for "${CommandPalette.query.trim()}"`
        }

        // what the list is, and what the keys do to the selected result
        Item {
            width: parent.width
            height: 18
            visible: list.count > 0

            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.padding
                    verticalCenter: parent.verticalCenter
                }
                color: Theme.fgDim
                font.pixelSize: 11
                text: {
                    if (CommandPalette.shellMode)
                        return "Shell actions";
                    if (CommandPalette.clipboardMode)
                        return CommandPalette.query.trim() === "" ? "Clipboard history" : (list.count === 1 ? "1 entry" : `${list.count} entries`);
                    if (CommandPalette.querying)
                        return "Searching…";
                    return list.count === 1 ? "1 result" : `${list.count} results`;
                }
            }

            RowLayout {
                anchors {
                    right: parent.right
                    rightMargin: Theme.padding
                    verticalCenter: parent.verticalCenter
                }
                spacing: 15

                KeyHint {
                    key: "⇧↵"
                    text: root.activeAction < 0 ? (root.currentActions[0]?.text ?? "") : ""
                }

                KeyHint {
                    key: "↵"
                    text: root.enterText
                }

                KeyHint {
                    key: "esc"
                    text: "Close"
                }
            }
        }
    }
}
