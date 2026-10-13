import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// The clipboard history's content: a search field with the entries below it,
// hanging from the top frame edge. All logic is in the CommandPalette
// singleton. (It was the command palette's panel, with KRunner's results in
// the same list; those are the launcher's now.)
//
// Keys: Up/Down or Ctrl+P/N/K/J move, PageUp/PageDown jump, Enter copies the
// selected entry, Escape closes.
Item {
    id: root

    readonly property var results: CommandPalette.results
    // what the list shows: `results`, handed over by show()
    property var shown: []
    readonly property string currentKey: shown[list.currentIndex]?.key ?? ""
    // the selection was moved by hand since the query last changed; until
    // then it stays on the first result while results keep arriving
    property bool touched: false
    // by the keys, which counts on when the pointer has left the list again
    property bool keyTouched: false
    readonly property int margin: 12

    implicitWidth: 660
    implicitHeight: column.implicitHeight + margin * 2

    function focusSearch() {
        input.forceActiveFocus();
    }

    // The entries are listed anew for every key. A selection made by hand
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
        keyTouched = true;
        list.step(by, autoRepeat);
    }

    // The title with the typed words picked out, as styled text.
    function marked(result) {
        const escape = text => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const title = result.title;
        const lower = title.toLowerCase();
        if (result.image || lower.length !== title.length)
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

        // set from elsewhere: over IPC
        function onQueryChanged() {
            if (input.text !== CommandPalette.query)
                input.text = CommandPalette.query;
            root.touched = false;
            root.keyTouched = false;
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
                source: "edit-paste-symbolic"
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
                text: "Search the clipboard history"
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
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (!event.isAutoRepeat)
                            CommandPalette.submit(list.currentIndex);
                    } else if (control && (event.key === Qt.Key_N || event.key === Qt.Key_J))
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
            // the pointer's selection is over (see PickList)
            onPointerLeft: root.touched = root.keyTouched

            delegate: Item {
                id: row

                required property var modelData
                required property int index

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
                    onClicked: CommandPalette.submit(row.index)
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: Theme.padding
                        rightMargin: Theme.padding
                    }
                    spacing: 12

                    // an image is shown itself, wider than an icon
                    Item {
                        implicitWidth: thumbnail.visible ? 72 : 36
                        implicitHeight: thumbnail.visible ? 42 : 36

                        Image {
                            id: thumbnail

                            anchors.fill: parent
                            visible: row.modelData.image !== ""
                            source: visible ? "file://" + row.modelData.image : ""
                            // decoded at twice the size shown, not at full size
                            sourceSize.height: 84
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            clip: true
                        }

                        Icon {
                            anchors.centerIn: parent
                            width: 24
                            height: width
                            visible: !thumbnail.visible
                            source: row.modelData.icon
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
            }
        }

        // nothing matched
        Label {
            width: parent.width
            height: list.rowHeight
            visible: list.count === 0 && CommandPalette.query.trim() !== ""
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Theme.fgDim
            text: `Nothing found for "${CommandPalette.query.trim()}"`
        }

        // what the list is, and what the keys do to the selected entry
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
                text: CommandPalette.query.trim() === "" ? "Clipboard history" : (list.count === 1 ? "1 entry" : `${list.count} entries`)
            }

            RowLayout {
                anchors {
                    right: parent.right
                    rightMargin: Theme.padding
                    verticalCenter: parent.verticalCenter
                }
                spacing: 15

                KeyHint {
                    key: "↵"
                    text: "Copy"
                }

                KeyHint {
                    key: "esc"
                    text: "Close"
                }
            }
        }
    }
}
