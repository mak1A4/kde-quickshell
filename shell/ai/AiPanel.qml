import Quickshell
import QtQuick
import QtQuick.Layouts
import Qt.labs.qmlmodels
import qs
import qs.widgets

// The AI panel, in two pages that take turns (the panel changes its size
// with them). All state is in the Ai singleton; this only lays it out.
//
// Home: a composer for a new thread, and under it one list. The list is
// every thread, the ones that wait for an answer first, then the running
// ones, then what has finished unseen. Each of the composer's selectors
// (project, model, effort, access) puts its choices into the same list for
// as long as one is being chosen, so there is one list and one way to move
// in it.
//   Keys: Enter sends, Shift+Enter makes a new line. Down goes into the
//   list, and then Enter opens the marked thread; typing goes back to
//   writing. Tab goes through the selectors. Escape goes back a step, then
//   closes.
//
// Thread: the conversation and a field for a follow-up. What the agent did
// between two messages is one row, to be unfolded. The list stays at its end
// while the agent writes, unless the user has scrolled away from it.
//   Keys: Enter sends, PageUp/PageDown scroll, Escape goes back to home.
Item {
    id: root

    readonly property bool inThread: Ai.page === "thread"
    readonly property int margin: 12
    readonly property int homeWidth: 720
    readonly property int threadWidth: 900
    readonly property int threadHeight: 690

    implicitWidth: inThread ? threadWidth : homeWidth
    implicitHeight: inThread ? threadHeight : home.implicitHeight + margin * 2

    function focusComposer() {
        (inThread ? followInput : homeInput).forceActiveFocus();
    }

    onInThreadChanged: focusComposer()
    Component.onCompleted: {
        show();
        focusComposer();
    }

    Connections {
        target: Ai

        function onOpenChanged() {
            if (!Ai.open)
                return;
            root.pick("threads");
            root.focusComposer();
        }
    }

    // how long ago, as short as the notifications say it
    function ago(iso) {
        const seconds = (Date.now() - Date.parse(iso)) / 1000;
        if (isNaN(seconds))
            return "";
        if (seconds < 60)
            return "now";
        if (seconds < 3600)
            return Math.floor(seconds / 60) + "m";
        if (seconds < 86400)
            return Math.floor(seconds / 3600) + "h";
        return Math.floor(seconds / 86400) + "d";
    }

    function providerName(provider) {
        const id = String(provider ?? "");
        return id.includes("claude") ? "Claude" : id.includes("codex") ? "Codex" : id.charAt(0).toUpperCase() + id.slice(1);
    }

    function copy(text) {
        if (text !== "")
            Quickshell.execDetached(["wl-copy", "--", text]);
    }

    // ---- what the list on the home page shows ---------------------------------

    // "threads", or the selector that is being chosen from
    property string listing: "threads"
    readonly property var selectors: ["project", "model", "effort", "access"]

    // A row is { key, title, note, state, label }: `state` is a thread's
    // (Ai.kindOf), or "chosen" for the choice in use.
    readonly property var entries: {
        const chosen = yes => yes ? "chosen" : "";
        switch (listing) {
        case "project":
            return Ai.projects.map(project => ({
                        key: project.id,
                        title: project.title,
                        note: [Ai.environmentLabel(project.environment), String(project.workspaceRoot ?? "").replace(Ai.home, "~")].filter(part => part).join(" · "),
                        state: chosen(project.id === Ai.projectId),
                        label: ""
                    }));
        case "model":
            return Ai.favorites.map((favorite, index) => ({
                        key: String(index),
                        title: Ai.modelName(favorite.model),
                        note: providerName(favorite.provider),
                        state: chosen(index === Ai.modelIndex),
                        label: ""
                    }));
        case "effort":
            return Ai.effortChoices.map(choice => ({
                        key: choice.id,
                        title: choice.label,
                        note: "",
                        state: chosen(choice.id === Ai.effort),
                        label: ""
                    }));
        case "access":
            return Ai.runtimeModes.map(mode => ({
                        key: mode.id,
                        title: mode.label,
                        note: mode.note,
                        state: chosen(mode.id === Ai.runtimeMode),
                        label: ""
                    }));
        }
        const labels = {
            waiting: "Needs you",
            running: "Running",
            background: "In the background",
            failed: "Failed",
            done: "Finished"
        };
        return Ai.allThreads.map(thread => {
            const state = Ai.kindOf(thread);
            return {
                key: thread.id,
                title: thread.title || "Untitled",
                note: [Ai.environmentLabel(thread.environment), Ai.projectTitle(thread.projectId), ago(Ai.when(thread))].filter(part => part).join(" · "),
                state: state,
                label: labels[state] ?? ""
            };
        });
    }
    // what the list has, handed over by show()
    property var shown: []
    property string shownAs: ""

    // The rows are listed anew whenever a thread changes, which is often
    // while one runs. The marked row stays marked and the list stays where
    // it was scrolled to.
    function show() {
        const text = JSON.stringify(entries);
        if (text === shownAs)
            return;
        shownAs = text;
        const key = list.marked ? (shown[list.currentIndex]?.key ?? "") : "";
        const scroll = list.contentY;
        shown = entries;
        const at = key === "" ? -1 : shown.findIndex(entry => entry.key === key);
        list.jump = true;
        if (at >= 0)
            list.currentIndex = at;
        else if (listing === "threads")
            list.rewind();
        else
            list.choose(Math.max(0, shown.findIndex(entry => entry.state === "chosen")));
        list.contentY = Math.max(0, Math.min(scroll, list.scrollEnd));
        list.jump = false;
    }

    onEntriesChanged: show()

    // Puts a selector's choices into the list, the one in use marked, or
    // the threads back.
    function pick(kind) {
        if (listing === kind)
            return;
        list.rewind();
        listing = kind;
        if (kind === "threads")
            return;
        list.jump = true;
        list.choose(Math.max(0, shown.findIndex(entry => entry.state === "chosen")));
        list.contentY = Math.max(0, Math.min(list.scrollEnd, list.currentIndex * list.rowHeight));
        list.jump = false;
    }

    function activate(index) {
        const entry = shown[index];
        if (!entry)
            return;
        switch (listing) {
        case "project":
            Ai.projectId = entry.key;
            break;
        case "model":
            Ai.modelIndex = Number(entry.key);
            break;
        case "effort":
            Ai.effort = entry.key;
            break;
        case "access":
            Ai.runtimeMode = entry.key;
            break;
        default:
            Ai.openThread(entry.key);
            return;
        }
        pick("threads");
    }

    function submit() {
        if (homeInput.text.trim() === "" || !Ai.canStart || !Ai.projectId)
            return;
        Ai.send(homeInput.text);
        homeInput.text = "";
    }

    // ---- parts -----------------------------------------------------------------

    // a dot that breathes while something is going on
    component Pulse: Rectangle {
        id: pulse

        property bool beating: true

        implicitWidth: 9
        implicitHeight: 9
        radius: 4.5
        color: Theme.accent

        SequentialAnimation on opacity {
            running: pulse.beating && pulse.visible && Ai.open
            loops: Animation.Infinite
            alwaysRunToEnd: true

            NumberAnimation {
                to: 0.25
                duration: 700
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                to: 1
                duration: 700
                easing.type: Easing.InOutSine
            }
        }
    }

    // what a thread is up to, or that a choice is the one in use
    component StateDot: Pulse {
        property string kind

        beating: kind === "running" || kind === "background"
        visible: color.a > 0
        color: {
            switch (kind) {
            case "waiting":
                return Theme.warning;
            case "failed":
                return Theme.error;
            case "done":
                return Theme.systemHue;
            case "running":
            case "background":
            case "chosen":
                return Theme.accent;
            }
            return Theme.none;
        }
    }

    // one of the composer's selectors: what is chosen, and a click or Tab
    // away from choosing again
    component Chip: Rectangle {
        id: chip

        property string kind
        property alias text: chipLabel.text
        readonly property bool active: root.listing === kind

        implicitWidth: chipLabel.implicitWidth + 21
        implicitHeight: 27
        radius: height / 2
        color: active ? Theme.accent : (chipMouse.containsMouse ? Theme.surfaceActive : Theme.surfaceHover)

        Behavior on color {
            HoverAnim {}
        }

        Label {
            id: chipLabel

            anchors.centerIn: parent
            width: Math.min(implicitWidth, 180)
            color: chip.active ? Theme.accentFg : Theme.fg
            font.pixelSize: 12
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: {
                root.pick(chip.active ? "threads" : chip.kind);
                homeInput.forceActiveFocus();
            }
        }
    }

    // the round button a composer sends with
    component SendButton: Rectangle {
        id: sendButton

        property bool armed: false

        signal clicked

        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: armed ? Theme.accent : Theme.surfaceHover

        Behavior on color {
            HoverAnim {}
        }

        Icon {
            anchors.centerIn: parent
            source: "go-up-symbolic"
            color: sendButton.armed ? Theme.accentFg : Theme.fgDim
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sendButton.clicked()
        }
    }

    // Text of the conversation: it can be selected and copied, and its links
    // open. Copying goes through wl-copy: this process's own clipboard does
    // not reach the session's (see Launcher.qml). Anything typed while one of
    // these has the keys is meant for the follow-up field.
    component Prose: TextEdit {
        id: prose

        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.accentFg
        font.pixelSize: Theme.fontSize
        onLinkActivated: link => Qt.openUrlExternally(link)

        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                root.copy(selectedText);
                event.accepted = true;
                return;
            }
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                return;
            // Escape only gives the keys back; it does not close anything
            const typed = event.text !== "" && event.key !== Qt.Key_Escape && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter;
            if (!typed && event.key !== Qt.Key_Escape)
                return;
            followInput.forceActiveFocus();
            if (typed)
                followInput.insert(followInput.cursorPosition, event.text);
            event.accepted = true;
        }

        HoverHandler {
            cursorShape: prose.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
        }
    }

    // An answer as the blocks it is made of: [{ code, text }]. Qt draws
    // Markdown without any room between paragraphs, and code without
    // anything behind it; so each paragraph (list, table, heading) is drawn
    // by itself, with room between, and each fenced block as code on a card.
    // A fence that is not closed is one still being written.
    function blocks(text) {
        const out = [];
        const listed = block => /^\s*([-*+]|\d+[.)])\s/.test(block);
        let lines = [];
        let fence = "";
        const close = () => {
            if (lines.length === 0)
                return;
            const block = lines.join("\n");
            const before = out[out.length - 1];
            lines = [];
            // a list whose items are a blank line apart is one list, and an
            // indented paragraph under one belongs to it
            if (before && !before.code && listed(before.text) && (listed(block) || /^\s{2,}/.test(block)))
                before.text += "\n\n" + block;
            else
                out.push({
                    code: false,
                    text: block
                });
        };
        for (const line of text.split("\n")) {
            const mark = /^\s*(`{3,}|~{3,})(.*)$/.exec(line);
            if (fence !== "") {
                if (mark && mark[1].startsWith(fence) && mark[2].trim() === "")
                    fence = "";
                else
                    out[out.length - 1].text += (out[out.length - 1].text === "" ? "" : "\n") + line;
            } else if (mark) {
                close();
                fence = mark[1];
                out.push({
                    code: true,
                    text: ""
                });
            } else if (line.trim() === "")
                close();
            else
                lines.push(line);
        }
        close();
        return out;
    }

    Component {
        id: proseBlock

        Prose {
            width: parent?.width ?? 0
            textFormat: TextEdit.MarkdownText
            text: parent?.part.text ?? ""
        }
    }

    Component {
        id: codeBlock

        Rectangle {
            width: parent?.width ?? 0
            implicitHeight: code.contentHeight + 18
            radius: 9
            color: Theme.card(Theme.surface)

            HoverHandler {
                id: codeHover
            }

            Prose {
                id: code

                x: 12
                y: 9
                width: parent.width - 24
                wrapMode: TextEdit.WrapAnywhere
                textFormat: TextEdit.PlainText
                font.family: "monospace"
                font.pixelSize: 12
                text: parent.parent?.part.text ?? ""
            }

            IconButton {
                anchors {
                    right: parent.right
                    top: parent.top
                    margins: 3
                }
                opacity: codeHover.hovered ? 1 : 0
                color: Theme.surfaceHover
                source: "edit-copy-symbolic"
                iconColor: Theme.fgDim
                onClicked: root.copy(code.text)

                Behavior on opacity {
                    Anim {
                        kind: Anim.Hover
                    }
                }
            }
        }
    }

    // ---- home ----------------------------------------------------------------

    Column {
        id: home

        x: root.margin
        y: root.margin
        width: root.homeWidth - root.margin * 2
        spacing: root.margin
        opacity: root.inThread ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            SwapFade {
                incoming: !root.inThread
            }
        }

        // the composer
        Rectangle {
            width: parent.width
            height: composer.implicitHeight + 24
            radius: 15
            color: Theme.card(Theme.surface)
            border.width: Theme.fieldBorder
            border.color: Theme.surfaceHover

            ColumnLayout {
                id: composer

                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 9

                Item {
                    Layout.fillWidth: true
                    Layout.leftMargin: 3
                    Layout.rightMargin: 3
                    implicitHeight: Math.max(42, Math.min(150, homeInput.contentHeight))

                    Label {
                        width: parent.width
                        visible: homeInput.text === ""
                        color: Theme.fgDim
                        font.pixelSize: 14
                        text: Ai.project ? `Ask for something in ${Ai.project.title}` : "Ask for something"
                    }

                    TextEdit {
                        id: homeInput

                        // on the text's last line, from where Down leaves it
                        readonly property bool atEnd: cursorRectangle.y + cursorRectangle.height >= contentHeight - 1

                        anchors.fill: parent
                        clip: true
                        color: Theme.fg
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentFg
                        font.pixelSize: 14
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        focus: true

                        // written on: the keys are for the text again
                        onTextChanged: {
                            if (root.listing === "threads" && list.keysOn)
                                list.rewind();
                        }

                        Keys.onEscapePressed: {
                            if (root.listing !== "threads")
                                root.pick("threads");
                            else if (list.keysOn)
                                list.rewind();
                            else
                                Ai.hide();
                        }
                        Keys.onPressed: event => {
                            const control = event.modifiers & Qt.ControlModifier;
                            const choosing = root.listing !== "threads";
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    return;
                                if (!event.isAutoRepeat) {
                                    if (choosing || list.keysOn)
                                        root.activate(list.currentIndex);
                                    else
                                        root.submit();
                                }
                            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                const all = ["threads"].concat(root.selectors);
                                const by = event.key === Qt.Key_Tab ? 1 : all.length - 1;
                                root.pick(all[(all.indexOf(root.listing) + by) % all.length]);
                            } else if (event.key === Qt.Key_Down || (control && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
                                if (!choosing && !list.keysOn && !atEnd)
                                    return;
                                list.step(1, event.isAutoRepeat);
                            } else if (event.key === Qt.Key_Up || (control && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
                                if (!choosing && !list.keysOn)
                                    return;
                                // from the first thread back to the text
                                if (!choosing && list.currentIndex === 0)
                                    list.rewind();
                                else
                                    list.step(-1, event.isAutoRepeat);
                            } else if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && (choosing || list.keysOn))
                                list.step(event.key === Qt.Key_PageDown ? list.maxRows : -list.maxRows, event.isAutoRepeat);
                            else
                                return;
                            event.accepted = true;
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing

                    Chip {
                        kind: "project"
                        text: Ai.project?.title ?? "No project"
                    }

                    Chip {
                        kind: "model"
                        text: Ai.modelName(Ai.modelSelection.model) || "Model"
                    }

                    Chip {
                        kind: "effort"
                        visible: (Ai.modelSelection.options ?? []).length > 0
                        text: Ai.effortLabel
                    }

                    Chip {
                        kind: "access"
                        text: Ai.runtimeLabel(Ai.runtimeMode)
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    SendButton {
                        armed: homeInput.text.trim() !== "" && Ai.canStart && Ai.projectId !== ""
                        onClicked: {
                            root.submit();
                            homeInput.forceActiveFocus();
                        }
                    }
                }
            }
        }

        // not connected: why, and what to do about it
        RowLayout {
            width: parent.width
            height: 39
            visible: !Ai.ready || Ai.status === "error"
            spacing: Theme.spacing

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.padding
                color: Ai.status === "error" ? Theme.error : Theme.fgDim
                text: Ai.statusText || "Not connected to T3 Code."
            }

            Button {
                visible: Ai.status === "offline"
                text: "Start the server"
                onClicked: Ai.startServer()
            }

            Button {
                visible: Ai.status === "error" || Ai.status === "idle"
                text: Ai.ready ? "Dismiss" : "Try again"
                onClicked: {
                    if (Ai.ready)
                        Ai.setStatus("ready", "");
                    else
                        Ai.checkSession(false);
                }
            }
        }

        PickList {
            id: list

            width: parent.width
            visible: count > 0
            rowHeight: 39
            maxRows: 9
            lazy: true
            model: root.shown

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
                    onPositionChanged: mouse => list.hover(row.index, mapToItem(null, mouse.x, mouse.y))
                    onClicked: {
                        root.activate(row.index);
                        root.focusComposer();
                    }
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 12
                    }
                    spacing: 12

                    Item {
                        implicitWidth: 9
                        implicitHeight: 9

                        StateDot {
                            kind: row.modelData.state
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: row.modelData.title
                    }

                    Label {
                        Layout.maximumWidth: 300
                        color: Theme.fgDim
                        font.pixelSize: 11
                        textFormat: Text.PlainText
                        text: row.modelData.note
                    }

                    Label {
                        visible: text !== ""
                        color: row.modelData.state === "waiting" ? Theme.warning : (row.modelData.state === "failed" ? Theme.error : Theme.fgDim)
                        font.pixelSize: 11
                        text: row.modelData.label
                    }
                }
            }
        }

        // nothing to list
        Label {
            width: parent.width
            height: list.rowHeight
            visible: Ai.ready && list.count === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Theme.fgDim
            text: root.listing === "threads" ? "No threads yet." : (root.listing === "model" ? "No favourite models in T3 Code." : "Nothing to choose from.")
        }

        // what the list is, and what the keys do
        Item {
            width: parent.width
            height: 18

            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.padding
                    verticalCenter: parent.verticalCenter
                }
                color: Theme.fgDim
                font.pixelSize: 11
                text: {
                    switch (root.listing) {
                    case "project":
                        return "Project";
                    case "model":
                        return "Model, from your favourites in T3 Code";
                    case "effort":
                        return "Effort";
                    case "access":
                        return "Access, for a new thread";
                    }
                    // and of another machine's server, that it is not there
                    const away = Ai.links.filter(link => !link.local && !link.ready).map(link => `${link.label} not connected`);
                    const parts = [Ai.waitingCount ? `${Ai.waitingCount} waiting` : "", Ai.runningCount ? `${Ai.runningCount} running` : ""].concat(away).filter(part => part);
                    return ["T3 Code"].concat(parts).join(" · ");
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
                    key: "↵"
                    text: root.listing !== "threads" ? "Choose" : (list.keysOn ? "Open" : "Send")
                }

                KeyHint {
                    key: "↓"
                    text: root.listing === "threads" && !list.keysOn && list.count > 0 ? "Threads" : ""
                }

                KeyHint {
                    key: "tab"
                    text: root.listing === "threads" ? "Options" : "Next"
                }

                KeyHint {
                    key: "esc"
                    text: root.listing !== "threads" || list.keysOn ? "Back" : "Close"
                }
            }
        }
    }

    // ---- one thread ------------------------------------------------------------

    // rows of the agent's work that are unfolded, by their key
    property var unfolded: ({})

    function unfold(key) {
        const next = Object.assign({}, unfolded);
        if (next[key])
            delete next[key];
        else
            next[key] = true;
        unfolded = next;
    }

    Item {
        id: threadPage

        x: root.margin
        y: root.margin
        width: root.threadWidth - root.margin * 2
        height: root.threadHeight - root.margin * 2
        opacity: root.inThread ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            SwapFade {
                incoming: root.inThread
            }
        }

        RowLayout {
            id: header

            width: parent.width
            height: 39
            spacing: Theme.padding

            IconButton {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                source: "go-previous-symbolic"
                onClicked: Ai.page = "home"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    Layout.fillWidth: true
                    font.pixelSize: 14
                    textFormat: Text.PlainText
                    text: Ai.thread?.title || Ai.starting.split("\n")[0] || "Thread"
                }

                Label {
                    Layout.fillWidth: true
                    color: Theme.fgDim
                    font.pixelSize: 11
                    textFormat: Text.PlainText
                    text: {
                        const thread = Ai.thread;
                        if (!thread)
                            return [Ai.project?.title ?? "", Ai.modelName(Ai.modelSelection.model)].filter(part => part).join(" · ");
                        return [Ai.environmentLabel(thread.environment), Ai.projectTitle(thread.projectId), thread.branch ?? "", Ai.modelName(thread.modelSelection?.model), Ai.runtimeLabel(thread.runtimeMode)].filter(part => part).join(" · ");
                    }
                }
            }

            // the server has gone, or said no to something
            Label {
                visible: text !== ""
                color: Theme.error
                font.pixelSize: 11
                text: Ai.status === "error" ? Ai.statusText : (Ai.canSend ? "" : Ai.threadLink.statusText)
            }

            Button {
                visible: Ai.busy && !Ai.sending
                icon: "media-playback-stop-symbolic"
                text: "Stop"
                onClicked: Ai.interrupt()
            }
        }

        ListView {
            id: messages

            // at its end, and staying there as rows come and grow
            property bool follow: true
            readonly property real startY: originY
            readonly property real endY: Math.max(originY, originY + contentHeight - height)

            function toEnd() {
                if (follow)
                    positionViewAtEnd();
            }

            function scrollBy(distance) {
                contentY = Math.max(startY, Math.min(endY, contentY + distance));
                follow = contentY >= endY - 3;
            }

            anchors {
                top: header.bottom
                topMargin: Theme.spacing
                bottom: followCard.top
                bottomMargin: root.margin
            }
            width: parent.width
            clip: true
            spacing: 15
            // the wheel and the keys scroll; a drag selects text
            interactive: false
            cacheBuffer: 3000
            model: Ai.rows
            onContentHeightChanged: Qt.callLater(toEnd)
            onHeightChanged: Qt.callLater(toEnd)

            Connections {
                target: Ai

                function onShowEnd() {
                    messages.follow = true;
                    Qt.callLater(messages.toEnd);
                }
            }

            WheelHandler {
                onWheel: event => messages.scrollBy(event.pixelDelta.y !== 0 ? -event.pixelDelta.y : -event.angleDelta.y * 0.75)
            }

            delegate: DelegateChooser {
                role: "kind"

                DelegateChoice {
                    roleValue: "user"

                    Item {
                        id: mine

                        required property string text

                        width: messages.width
                        implicitHeight: bubble.height

                        // how wide the text is unwrapped
                        Label {
                            id: measure

                            visible: false
                            textFormat: Text.PlainText
                            elide: Text.ElideNone
                            text: mine.text
                        }

                        Rectangle {
                            id: bubble

                            anchors.right: parent.right
                            anchors.rightMargin: 15
                            width: Math.min((parent.width - 15) * 0.78, Math.ceil(measure.implicitWidth) + 25)
                            height: mineText.contentHeight + 18
                            radius: 12
                            color: Theme.card(Theme.surface)

                            Prose {
                                id: mineText

                                x: 12
                                y: 9
                                width: parent.width - 24
                                textFormat: TextEdit.PlainText
                                text: mine.text
                            }
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "assistant"

                    Item {
                        id: answer

                        required property string text
                        readonly property var parts: root.blocks(text)

                        width: messages.width
                        implicitHeight: answerColumn.implicitHeight

                        HoverHandler {
                            id: answerHover
                        }

                        Column {
                            id: answerColumn

                            x: 6
                            width: parent.width - 51
                            spacing: 9

                            // by number, so that a block being written is
                            // the same item from word to word
                            Repeater {
                                model: answer.parts.length

                                Loader {
                                    required property int index
                                    readonly property var part: answer.parts[index] ?? ({
                                            code: false,
                                            text: ""
                                        })

                                    width: answerColumn.width
                                    sourceComponent: part.code ? codeBlock : proseBlock
                                }
                            }
                        }

                        IconButton {
                            anchors.right: parent.right
                            anchors.rightMargin: 15
                            opacity: answerHover.hovered ? 1 : 0
                            source: "edit-copy-symbolic"
                            iconColor: Theme.fgDim
                            onClicked: root.copy(answer.text)

                            Behavior on opacity {
                                Anim {
                                    kind: Anim.Hover
                                }
                            }
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "work"

                    Item {
                        id: work

                        required property string key
                        required property string text
                        required property string last
                        required property string steps
                        required property bool live
                        required property int index
                        readonly property bool open: root.unfolded[key] === true
                        // the agent is at it now
                        readonly property bool going: live && Ai.busy && index === messages.count - 1

                        width: messages.width
                        implicitHeight: workColumn.implicitHeight

                        Column {
                            id: workColumn

                            x: 6
                            width: parent.width - 21
                            spacing: Theme.spacing

                            Item {
                                width: parent.width
                                height: 21

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.spacing

                                    Icon {
                                        implicitWidth: 15
                                        implicitHeight: 15
                                        source: "go-next-symbolic"
                                        color: Theme.fgDim
                                        rotation: work.open ? 90 : 0

                                        Behavior on rotation {
                                            Anim {
                                                kind: Anim.Fade
                                            }
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        color: Theme.fgDim
                                        font.pixelSize: 12
                                        textFormat: Text.PlainText
                                        text: work.going && !work.open ? work.last : work.text
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.unfold(work.key)
                                }
                            }

                            Column {
                                x: 21
                                width: parent.width - 21
                                spacing: 3
                                visible: work.open

                                Repeater {
                                    model: work.open ? JSON.parse(work.steps) : []

                                    Label {
                                        required property var modelData

                                        width: parent.width
                                        wrapMode: Text.Wrap
                                        elide: Text.ElideNone
                                        maximumLineCount: modelData.kind === "thought" ? 6 : 12
                                        color: modelData.kind === "thought" || modelData.kind === "note" ? Theme.fgDim : Theme.fg
                                        font.pixelSize: 12
                                        font.family: modelData.kind === "command" ? "monospace" : Qt.application.font.family
                                        font.italic: modelData.kind === "thought"
                                        textFormat: Text.PlainText
                                        text: ({
                                                command: "$ ",
                                                edit: "Edited ",
                                                search: "Searched ",
                                                agent: "Subagent: "
                                            }[modelData.kind] ?? "") + modelData.text
                                    }
                                }
                            }
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "approval"

                    Item {
                        id: approval

                        required property string text
                        required property string requestId
                        required property bool pending

                        width: messages.width
                        implicitHeight: approvalCard.height

                        Rectangle {
                            id: approvalCard

                            width: parent.width - 15
                            height: approvalColumn.implicitHeight + 24
                            radius: 12
                            color: Theme.card(Theme.surface)

                            Column {
                                id: approvalColumn

                                x: 12
                                y: 12
                                width: parent.width - 24
                                spacing: Theme.padding

                                Label {
                                    color: approval.pending ? Theme.warning : Theme.fgDim
                                    font.pixelSize: 11
                                    text: approval.pending ? "The agent asks before going on" : "Asked, and answered"
                                }

                                Prose {
                                    width: parent.width
                                    textFormat: TextEdit.PlainText
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    text: approval.text
                                }

                                Row {
                                    visible: approval.pending
                                    spacing: Theme.spacing

                                    Button {
                                        raised: true
                                        text: "Approve"
                                        onClicked: Ai.respond(approval.requestId, "accept")
                                    }

                                    Button {
                                        raised: true
                                        text: "Approve for this session"
                                        onClicked: Ai.respond(approval.requestId, "acceptForSession")
                                    }

                                    Button {
                                        raised: true
                                        text: "Decline"
                                        onClicked: Ai.respond(approval.requestId, "decline")
                                    }
                                }
                            }
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "question"

                    Item {
                        id: question

                        required property string steps
                        required property string requestId
                        required property bool pending
                        readonly property var asked: JSON.parse(steps || "[]")
                        // what is chosen or written so far, by the question's id
                        property var answers: ({})
                        readonly property bool complete: asked.length > 0 && asked.every(one => (answers[one.id] ?? "").trim() !== "")

                        function give(id, text) {
                            const next = Object.assign({}, answers);
                            next[id] = text;
                            answers = next;
                        }

                        // an option is taken, or with several allowed, taken
                        // or put back; what the answer is then
                        function choose(one, label) {
                            if (!one.multi)
                                return label;
                            const have = (answers[one.id] ?? "").split(", ").filter(part => part);
                            const at = have.indexOf(label);
                            if (at < 0)
                                have.push(label);
                            else
                                have.splice(at, 1);
                            return have.join(", ");
                        }

                        function send() {
                            if (pending && complete)
                                Ai.answer(requestId, answers);
                        }

                        width: messages.width
                        implicitHeight: questionCard.height

                        Rectangle {
                            id: questionCard

                            width: parent.width - 15
                            height: questionColumn.implicitHeight + 24
                            radius: 12
                            color: Theme.card(Theme.surface)

                            Column {
                                id: questionColumn

                                x: 12
                                y: 12
                                width: parent.width - 24
                                spacing: 12

                                Label {
                                    color: question.pending ? Theme.warning : Theme.fgDim
                                    font.pixelSize: 11
                                    text: question.pending ? (question.asked.length === 1 ? "The agent has a question" : "The agent has questions") : "Asked, and answered"
                                }

                                Repeater {
                                    model: question.asked

                                    Column {
                                        id: one

                                        required property var modelData
                                        readonly property string answer: question.answers[modelData.id] ?? ""

                                        width: questionColumn.width
                                        spacing: Theme.spacing

                                        Prose {
                                            width: parent.width
                                            textFormat: TextEdit.PlainText
                                            text: one.modelData.question
                                        }

                                        Prose {
                                            width: parent.width
                                            visible: !question.pending && text !== ""
                                            textFormat: TextEdit.PlainText
                                            color: Theme.fgDim
                                            text: one.modelData.answer
                                        }

                                        Repeater {
                                            model: question.pending ? one.modelData.options : []

                                            Rectangle {
                                                id: option

                                                required property var modelData
                                                readonly property bool taken: one.answer.split(", ").includes(modelData.label)

                                                width: one.width
                                                height: optionColumn.implicitHeight + 12
                                                radius: 9
                                                color: taken ? Theme.surfaceActive : (optionMouse.containsMouse ? Theme.surfaceHover : Theme.none)

                                                Behavior on color {
                                                    HoverAnim {}
                                                }

                                                Column {
                                                    id: optionColumn

                                                    x: 9
                                                    y: 6
                                                    width: parent.width - 18

                                                    Label {
                                                        width: parent.width
                                                        textFormat: Text.PlainText
                                                        text: option.modelData.label
                                                    }

                                                    Label {
                                                        width: parent.width
                                                        visible: text !== ""
                                                        wrapMode: Text.Wrap
                                                        elide: Text.ElideNone
                                                        color: Theme.fgDim
                                                        font.pixelSize: 11
                                                        textFormat: Text.PlainText
                                                        text: option.modelData.description
                                                    }
                                                }

                                                MouseArea {
                                                    id: optionMouse

                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    hoverEnabled: true
                                                    onClicked: {
                                                        own.text = question.choose(one.modelData, option.modelData.label);
                                                        question.give(one.modelData.id, own.text);
                                                    }
                                                }
                                            }
                                        }

                                        // the answer, to be written or changed
                                        Rectangle {
                                            width: parent.width
                                            height: 33
                                            visible: question.pending
                                            radius: 9
                                            color: Theme.surfaceHover

                                            Label {
                                                anchors {
                                                    left: own.left
                                                    right: own.right
                                                    verticalCenter: parent.verticalCenter
                                                }
                                                visible: own.text === ""
                                                color: Theme.fgDim
                                                text: one.modelData.options.length > 0 ? "Or in your own words" : "Your answer"
                                            }

                                            TextInput {
                                                id: own

                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    leftMargin: 9
                                                    rightMargin: 9
                                                    verticalCenter: parent.verticalCenter
                                                }
                                                clip: true
                                                color: Theme.fg
                                                selectionColor: Theme.accent
                                                selectedTextColor: Theme.accentFg
                                                font.pixelSize: Theme.fontSize
                                                onTextEdited: question.give(one.modelData.id, text)
                                                onAccepted: question.send()
                                                Keys.onEscapePressed: followInput.forceActiveFocus()
                                            }
                                        }
                                    }
                                }

                                Button {
                                    visible: question.pending
                                    raised: true
                                    opacity: question.complete ? 1 : 0.5
                                    text: question.asked.length === 1 ? "Send the answer" : "Send the answers"
                                    onClicked: question.send()
                                }
                            }
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "notice"

                    Item {
                        id: notice

                        required property string text

                        width: messages.width
                        implicitHeight: noticeText.contentHeight

                        Prose {
                            id: noticeText

                            x: 6
                            width: parent.width - 21
                            textFormat: TextEdit.PlainText
                            color: Theme.fgDim
                            font.pixelSize: 12
                            text: notice.text
                        }
                    }
                }

                DelegateChoice {
                    roleValue: "error"

                    Item {
                        id: failure

                        required property string text

                        width: messages.width
                        implicitHeight: failureText.contentHeight

                        Prose {
                            id: failureText

                            x: 6
                            width: parent.width - 21
                            textFormat: TextEdit.PlainText
                            color: Theme.error
                            text: failure.text
                        }
                    }
                }
            }

            // the agent is at work, or the message is on its way
            footer: Item {
                width: messages.width
                height: Ai.busy ? 36 : 0
                visible: Ai.busy

                RowLayout {
                    x: 9
                    y: 15
                    height: 21
                    spacing: Theme.padding

                    Pulse {}

                    Label {
                        color: Theme.fgDim
                        font.pixelSize: 12
                        text: Ai.sending ? "Sending" : (Ai.kindOf(Ai.thread) === "waiting" ? "Waiting for you" : "Working")
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: messages.count === 0 && !Ai.busy
                color: Theme.fgDim
                text: Ai.projection ? "Nothing in this thread yet." : "Loading the thread"
            }

            // where the list is, while there is more than fits
            Rectangle {
                anchors.right: parent.right
                visible: messages.visibleArea.heightRatio < 1
                y: messages.visibleArea.yPosition * messages.height
                width: 3
                height: Math.max(30, messages.visibleArea.heightRatio * messages.height)
                radius: 1.5
                color: Theme.surfaceHover
            }
        }

        // the follow-up
        Rectangle {
            id: followCard

            anchors.bottom: hints.top
            anchors.bottomMargin: root.margin
            width: parent.width
            height: Math.max(54, Math.min(174, followInput.contentHeight + 24))
            radius: 15
            color: Theme.card(Theme.surface)
            border.width: Theme.fieldBorder
            border.color: Theme.surfaceHover

            Label {
                anchors {
                    left: followInput.left
                    right: followInput.right
                    top: followInput.top
                }
                visible: followInput.text === ""
                color: Theme.fgDim
                font.pixelSize: 14
                text: Ai.liveRun !== null ? "Write a follow-up for when this run has ended" : "Write a follow-up"
            }

            TextEdit {
                id: followInput

                anchors {
                    fill: parent
                    leftMargin: 15
                    rightMargin: 54
                    topMargin: 12
                    bottomMargin: 12
                }
                clip: true
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentFg
                font.pixelSize: 14
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText

                function submit() {
                    if (text.trim() === "" || !Ai.canSend)
                        return;
                    Ai.send(text);
                    text = "";
                }

                Keys.onEscapePressed: Ai.page = "home"
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (event.modifiers & Qt.ShiftModifier)
                            return;
                        if (!event.isAutoRepeat)
                            submit();
                    } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)
                        messages.scrollBy((event.key === Qt.Key_PageUp ? -0.8 : 0.8) * messages.height);
                    else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Home || event.key === Qt.Key_End))
                        messages.scrollBy(event.key === Qt.Key_Home ? -messages.contentHeight : messages.contentHeight);
                    else
                        return;
                    event.accepted = true;
                }
            }

            SendButton {
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    margins: 12
                }
                armed: followInput.text.trim() !== "" && Ai.canSend
                onClicked: {
                    followInput.submit();
                    followInput.forceActiveFocus();
                }
            }
        }

        Item {
            id: hints

            anchors.bottom: parent.bottom
            width: parent.width
            height: 18

            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.padding
                    verticalCenter: parent.verticalCenter
                }
                visible: !messages.follow
                color: Theme.fgDim
                font.pixelSize: 11
                text: Ai.busy ? "Scrolled back, the agent goes on below" : ""
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
                    text: Ai.liveRun !== null ? "Queue" : "Send"
                }

                KeyHint {
                    key: "⇧↵"
                    text: "New line"
                }

                KeyHint {
                    key: "pgup"
                    text: "Scroll"
                }

                KeyHint {
                    key: "esc"
                    text: "Threads"
                }
            }
        }
    }
}
