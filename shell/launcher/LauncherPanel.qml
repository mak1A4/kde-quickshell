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

    function move(by) {
        if (list.count === 0)
            return;
        list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + by));
    }

    function focusSearch() {
        input.forceActiveFocus();
    }

    onResultsChanged: list.currentIndex = 0
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
        // the highlight is our own rectangle, so it can use the shell's curve
        highlightFollowsCurrentItem: false
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        highlightMoveDuration: Theme.fadeDuration

        highlight: Rectangle {
            y: list.currentItem?.y ?? 0
            width: list.width
            height: root.rowHeight
            radius: 12
            color: Theme.surface
            visible: list.currentItem !== null && (list.currentItem.modelData.kind !== "none")

            Behavior on y {
                Anim {
                    kind: Anim.Fade
                }
            }
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
                // only real pointer movement selects, not the list scrolling under a still pointer
                onPositionChanged: list.currentIndex = row.index
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

            Keys.onUpPressed: root.move(-1)
            Keys.onDownPressed: root.move(1)
            Keys.onEscapePressed: Launcher.hide()
            Keys.onPressed: event => {
                const control = event.modifiers & Qt.ControlModifier;
                if (event.key === Qt.Key_Tab || (control && (event.key === Qt.Key_N || event.key === Qt.Key_J)))
                    root.move(1);
                else if (event.key === Qt.Key_Backtab || (control && (event.key === Qt.Key_P || event.key === Qt.Key_K)))
                    root.move(-1);
                else if (event.key === Qt.Key_PageDown)
                    root.move(root.maxRows);
                else if (event.key === Qt.Key_PageUp)
                    root.move(-root.maxRows);
                else
                    return;
                event.accepted = true;
            }
        }
    }
}
