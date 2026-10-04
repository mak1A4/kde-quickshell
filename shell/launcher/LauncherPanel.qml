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

    function focusSearch() {
        input.forceActiveFocus();
    }

    // new results: back to the first one
    onResultsChanged: list.rewind()
    Component.onCompleted: focusSearch()

    PickList {
        id: list

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: root.margin
        }
        rowHeight: root.rowHeight
        maxRows: root.maxRows
        model: root.results
        highlighted: currentItem?.modelData.kind !== "none"

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
                // the keyboard can move the list underneath it.
                onPositionChanged: mouse => list.hover(row.index, mapToItem(null, mouse.x, mouse.y))
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

            Keys.onUpPressed: event => list.step(-1, event.isAutoRepeat)
            Keys.onDownPressed: event => list.step(1, event.isAutoRepeat)
            Keys.onEscapePressed: Launcher.hide()
            Keys.onPressed: event => {
                const control = event.modifiers & Qt.ControlModifier;
                if (event.key === Qt.Key_Tab || (control && (event.key === Qt.Key_N || event.key === Qt.Key_J)))
                    list.step(1, event.isAutoRepeat);
                else if (event.key === Qt.Key_Backtab || (control && (event.key === Qt.Key_P || event.key === Qt.Key_K)))
                    list.step(-1, event.isAutoRepeat);
                else if (event.key === Qt.Key_PageDown)
                    list.step(root.maxRows, event.isAutoRepeat);
                else if (event.key === Qt.Key_PageUp)
                    list.step(-root.maxRows, event.isAutoRepeat);
                else
                    return;
                event.accepted = true;
            }
        }
    }
}
