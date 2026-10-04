import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// The launcher's content: a short result list above a search field, after
// Caelestia's. The Dock grows into this when the launcher opens. All logic is
// in the Launcher singleton.
//
// Keys: Up/Down or Ctrl+P/N/K/J and Tab/Shift+Tab move, PageUp/PageDown jump,
// Enter activates, Escape closes.
Item {
    id: root

    readonly property var results: Launcher.results
    readonly property int rowHeight: 54
    readonly property int maxRows: 7
    readonly property int margin: 12

    implicitWidth: 540
    implicitHeight: list.height + (list.height > 0 ? margin : 0) + empty.height + search.height + margin * 2

    // ---- selection movement ------------------------------------------------
    //
    // One thing is animated: `highlightY`, the highlight's position in the
    // list. For keyboard moves the scroll position is not animated separately
    // but follows the highlight frame by frame (`follow`), so the two cannot
    // drift apart. (Animating both, the highlight fell behind on a held key and
    // was dragged upward by the scrolling list.)
    //
    // A single press eases with the shell's curve. A held key glides at
    // constant speed, one row per step, each step lasting as long as the gap
    // between steps, which reads as continuous motion instead of hops.

    // true while a key is held down and repeating
    property bool repeating: false
    // A held key steps at most this often (ms), whatever the keyboard's own
    // repeat rate: at the system rate the list ran past too fast to follow.
    readonly property int repeatInterval: 66
    property real lastRepeat: 0
    // measured time between the steps of a held key
    property int stepDuration: 80
    // the scroll position follows the highlight (keyboard), or not (pointer)
    property bool following: false
    // set to move the highlight without animation
    property bool jump: false

    property real highlightY: list.currentIndex * rowHeight

    Behavior on highlightY {
        enabled: !root.jump

        NumberAnimation {
            duration: root.repeating ? root.stepDuration : Theme.fadeDuration
            easing.type: root.repeating ? Easing.Linear : Easing.BezierSpline
            easing.bezierCurve: Theme.fadeCurve
        }
    }

    onHighlightYChanged: {
        if (!following)
            return;
        if (highlightY < list.contentY)
            list.contentY = highlightY;
        else if (highlightY + rowHeight > list.contentY + list.height)
            list.contentY = highlightY + rowHeight - list.height;
    }

    // Keyboard selection: moves the selection; the list scrolls to keep it in view.
    function move(by, autoRepeat) {
        if (list.count === 0)
            return;
        repeating = autoRepeat ?? false;
        if (repeating) {
            const now = Date.now();
            const since = now - lastRepeat;
            if (since < repeatInterval)
                return;
            lastRepeat = now;
            // the first repeat comes after the long initial delay; ignore that gap
            if (since < 250)
                stepDuration = since;
        }
        following = true;
        list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + by));
    }

    // Where the pointer was last seen, in window coordinates (x < 0: not yet).
    property point pointerAt: Qt.point(-1, -1)

    // Pointer selection, called for every hover report of a row. It acts only
    // when the pointer has really moved on screen. Rows sliding under a resting
    // pointer are reported as movement too (the pointer's position within the
    // row changes), and with the list gliding that happens every frame; acting
    // on those re-selects the row under the pointer and fights the keyboard.
    // Pointer selection never scrolls, see the list below.
    function hover(index, at) {
        const first = pointerAt.x < 0;
        const moved = Math.abs(at.x - pointerAt.x) >= 1 || Math.abs(at.y - pointerAt.y) >= 1;
        pointerAt = at;
        // the first report only says where the pointer rests: the launcher
        // usually opens right under it, and that must not select anything
        if (first || !moved)
            return;
        repeating = false;
        following = false;
        list.currentIndex = index;
    }

    function focusSearch() {
        input.forceActiveFocus();
    }

    // new results: back to the first one, at the top, without gliding there
    onResultsChanged: {
        jump = true;
        list.currentIndex = 0;
        list.contentY = 0;
        jump = false;
    }
    Component.onCompleted: focusSearch()

    ListView {
        id: list

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: root.margin
        }
        height: Math.min(count, root.maxRows) * root.rowHeight
        clip: true
        model: root.results
        boundsBehavior: Flickable.StopAtBounds
        // Only the wheel and the keyboard scroll. The list must not follow the
        // selection by itself (hovering a half-visible row would scroll it,
        // putting another row under the pointer, and so on), and dragging with
        // the mouse must not flick it.
        highlightRangeMode: ListView.NoHighlightRange
        acceptedButtons: Qt.NoButton
        // the wheel settles on whole rows
        snapMode: ListView.SnapToItem
        // the highlight is our own rectangle, so it can use the shell's curve
        highlightFollowsCurrentItem: false

        highlight: Rectangle {
            y: root.highlightY
            width: list.width
            height: root.rowHeight
            radius: 12
            color: Theme.surface
            visible: list.currentItem !== null && (list.currentItem.modelData.kind !== "none")
        }

        delegate: Item {
            id: row

            required property var modelData
            required property int index

            width: list.width
            height: root.rowHeight

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Theme.padding
                    rightMargin: Theme.padding
                }
                spacing: 12

                Icon {
                    implicitWidth: 36
                    implicitHeight: 36
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
                anchors.fill: parent
                hoverEnabled: true
                // Real pointer movement selects the row under it, without
                // scrolling. A still pointer selects nothing, so the wheel or
                // the keyboard can move the list underneath it (see hover()).
                onPositionChanged: mouse => root.hover(row.index, mapToItem(null, mouse.x, mouse.y))
                onClicked: Launcher.activate(row.modelData)
            }
        }
    }

    // nothing matched
    Item {
        id: empty

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: root.margin
        }
        height: visible ? root.rowHeight : 0
        visible: list.count === 0

        Label {
            anchors.centerIn: parent
            color: Theme.fgDim
            text: Launcher.apps.length === 0 ? "No applications found" : `Nothing matches "${Launcher.query.trim()}"`
        }
    }

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
            onAccepted: Launcher.activate(root.results[list.currentIndex])

            Keys.onUpPressed: event => root.move(-1, event.isAutoRepeat)
            Keys.onDownPressed: event => root.move(1, event.isAutoRepeat)
            Keys.onEscapePressed: Launcher.hide()
            Keys.onPressed: event => {
                const control = event.modifiers & Qt.ControlModifier;
                if (event.key === Qt.Key_Tab || (control && (event.key === Qt.Key_N || event.key === Qt.Key_J)))
                    root.move(1, event.isAutoRepeat);
                else if (event.key === Qt.Key_Backtab || (control && (event.key === Qt.Key_P || event.key === Qt.Key_K)))
                    root.move(-1, event.isAutoRepeat);
                else if (event.key === Qt.Key_PageDown)
                    root.move(root.maxRows, event.isAutoRepeat);
                else if (event.key === Qt.Key_PageUp)
                    root.move(-root.maxRows, event.isAutoRepeat);
                else
                    return;
                event.accepted = true;
            }
        }
    }
}
