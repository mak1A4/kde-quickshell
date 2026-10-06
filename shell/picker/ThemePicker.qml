import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs
import qs.widgets

// The theme switcher: the looks (Looks.qml: a theme with one of its
// backgrounds) as a row of pictures, the one in the middle large, after
// Caelestia's wallpaper list. It is shown where the command palette is, as
// one of its modes (CommandPalette.mode "themes").
//
// Moving through the row shows the shell in each theme's colours at once,
// and only the shell: nothing is chosen. Enter, or a click on the look in
// the middle, chooses the theme and its background for everything; Escape
// puts the shell's colours back.
//
// Keys: Left/Right (or Tab, h/l) move, Home/End jump, Enter chooses, Escape
// closes.
Item {
    id: root

    readonly property int margin: 12
    readonly property int cardWidth: 264
    readonly property int cardHeight: Math.round(cardWidth / 16 * 9)
    // each look has this much of the row; the ones beside the middle are
    // drawn smaller in it
    readonly property int slot: 252
    readonly property int shownSlots: 5
    readonly property var looks: Looks.list
    readonly property var current: looks[row.currentIndex] ?? null
    readonly property var currentColors: Theme.resolved(current?.colors ?? {})

    implicitWidth: slot * shownSlots + margin * 2
    implicitHeight: column.implicitHeight + margin * 2

    function choose() {
        if (!current)
            return;
        Themes.choose(current.theme, current.file);
        CommandPalette.hide();
    }

    // the look that is in use, in the middle, without gliding there
    function rewind() {
        const at = Looks.indexOf(Themes.chosen, Themes.background.replace(/^.*\//, ""));
        row.highlightMoveDuration = 0;
        row.currentIndex = Math.max(0, at);
        row.highlightMoveDuration = Theme.fadeDuration;
    }

    onLooksChanged: rewind()

    // The shell in the colours of the look in the middle, once the row has
    // rested there a moment: not every theme it passes on a held key.
    onCurrentChanged: preview.restart()

    Timer {
        id: preview

        interval: 120
        onTriggered: {
            if (root.current && CommandPalette.open)
                Themes.preview = root.current.theme === Themes.chosen ? null : root.current.colors;
        }
    }

    Component.onCompleted: {
        Looks.refresh();
        rewind();
        row.forceActiveFocus();
    }

    // closed without choosing: the shell's own colours again. (After
    // choosing, Themes ends the preview itself, when the theme is read.)
    Component.onDestruction: {
        if (!Themes.confirming)
            Themes.preview = null;
    }

    Connections {
        target: CommandPalette

        // reopened before the previous panel had faded away
        function onOpenChanged() {
            if (CommandPalette.open) {
                root.rewind();
                row.forceActiveFocus();
            } else if (!Themes.confirming) {
                Themes.preview = null;
            }
        }
    }

    Column {
        id: column

        x: root.margin
        y: root.margin
        width: parent.width - root.margin * 2
        spacing: 9

        PathView {
            id: row

            width: parent.width
            height: root.cardHeight + 18
            model: root.looks
            pathItemCount: Math.min(root.shownSlots, count)
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            snapMode: PathView.SnapToItem
            highlightMoveDuration: Theme.fadeDuration
            clip: true
            focus: true

            Keys.onLeftPressed: decrementCurrentIndex()
            Keys.onRightPressed: incrementCurrentIndex()
            Keys.onBacktabPressed: decrementCurrentIndex()
            Keys.onTabPressed: incrementCurrentIndex()
            Keys.onReturnPressed: root.choose()
            Keys.onEnterPressed: root.choose()
            Keys.onEscapePressed: CommandPalette.hide()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_H)
                    decrementCurrentIndex();
                else if (event.key === Qt.Key_L)
                    incrementCurrentIndex();
                else if (event.key === Qt.Key_Home)
                    currentIndex = 0;
                else if (event.key === Qt.Key_End)
                    currentIndex = count - 1;
                else
                    return;
                event.accepted = true;
            }

            // The line the looks stand on: across the row, the middle of it
            // in front and at full size.
            path: Path {
                startX: row.width / 2 - row.pathItemCount * root.slot / 2
                startY: row.height / 2

                PathAttribute {
                    name: "size"
                    value: 0.6
                }

                PathAttribute {
                    name: "front"
                    value: 0
                }

                PathLine {
                    x: row.width / 2
                    relativeY: 0
                }

                PathAttribute {
                    name: "size"
                    value: 1
                }

                PathAttribute {
                    name: "front"
                    value: 10
                }

                PathLine {
                    x: row.width / 2 + row.pathItemCount * root.slot / 2
                    relativeY: 0
                }

                PathAttribute {
                    name: "size"
                    value: 0.6
                }

                PathAttribute {
                    name: "front"
                    value: 0
                }
            }

            // one notch of the wheel, one look
            WheelHandler {
                property real rest: 0

                onWheel: event => {
                    rest += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                    const notches = rest > 0 ? Math.floor(rest / 120) : Math.ceil(rest / 120);
                    rest -= notches * 120;
                    for (let i = 0; i < Math.abs(notches); i++)
                        notches > 0 ? row.decrementCurrentIndex() : row.incrementCurrentIndex();
                }
            }

            delegate: Item {
                id: card

                required property var modelData
                required property int index

                readonly property bool middle: PathView.isCurrentItem
                readonly property var colors: Theme.resolved(modelData.colors)

                width: root.cardWidth
                height: root.cardHeight
                scale: PathView.size ?? 0.6
                z: PathView.front ?? 0
                opacity: PathView.onPath ? 1 : 0

                // the ring round the look in the middle, in its own accent
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4.5
                    radius: 16.5
                    color: "transparent"
                    border.width: 3
                    border.color: card.colors.accent
                    opacity: card.middle ? 1 : 0

                    Behavior on opacity {
                        Anim {
                            kind: Anim.Fade
                        }
                    }
                }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: 12
                    color: card.colors.bg

                    // A theme without a background, as itself: a piece of
                    // its frame with what stands on it.
                    Item {
                        anchors.fill: parent
                        visible: card.modelData.thumb === ""

                        Rectangle {
                            x: 24
                            y: 24
                            width: parent.width - 48
                            height: 30
                            radius: 15
                            color: card.colors.surface
                        }

                        Rectangle {
                            x: 24
                            y: 66
                            width: 96
                            height: 24
                            radius: 12
                            color: card.colors.accent
                        }

                        Rectangle {
                            x: 129
                            y: 66
                            width: 66
                            height: 24
                            radius: 12
                            color: card.colors.surfaceHover
                        }

                        Rectangle {
                            x: 24
                            y: 105
                            width: 144
                            height: 6
                            radius: 3
                            color: card.colors.fg
                        }

                        Rectangle {
                            x: 24
                            y: 120
                            width: 90
                            height: 6
                            radius: 3
                            color: card.colors.fgDim
                        }
                    }

                    Image {
                        anchors.fill: parent
                        visible: card.modelData.thumb !== ""
                        source: card.modelData.thumb !== "" ? "file://" + card.modelData.thumb : ""
                        sourceSize: Qt.size(640, 360)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    // the theme's colours on its picture: frame, accent and
                    // text, as three discs
                    Row {
                        anchors {
                            left: parent.left
                            bottom: parent.bottom
                            margins: 9
                        }
                        spacing: -6

                        Repeater {
                            model: [card.colors.bg, card.colors.accent, card.colors.fg]

                            Rectangle {
                                required property color modelData

                                width: 21
                                height: 21
                                radius: 10.5
                                color: modelData
                                border.width: 1.5
                                border.color: Qt.alpha(card.colors.fg, 0.55)
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (card.middle)
                            root.choose();
                        else
                            row.currentIndex = card.index;
                    }
                }
            }
        }

        // the look in the middle, by name, and its colours for the desktops
        Item {
            width: parent.width
            height: 42

            Column {
                anchors.centerIn: parent
                spacing: 6

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 9

                    Label {
                        font.pixelSize: 15
                        font.bold: true
                        text: root.current ? Themes.title(root.current.theme) : (Looks.ready ? "No themes" : "Looking at the backgrounds…")
                    }

                    Label {
                        anchors.baseline: parent.children[0].baseline
                        visible: text !== ""
                        color: Theme.fgDim
                        text: root.current && root.current.file !== "" ? Themes.title(root.current.file) : ""
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    Repeater {
                        model: root.currentColors.desktops

                        Rectangle {
                            required property color modelData

                            width: 9
                            height: 9
                            radius: 4.5
                            color: modelData
                        }
                    }
                }
            }
        }

        // the last line, as the palette's
        Item {
            width: parent.width
            height: 21

            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.padding
                    verticalCenter: parent.verticalCenter
                }
                color: Theme.fgDim
                font.pixelSize: 11
                text: {
                    if (!root.current)
                        return "Themes";
                    const using = root.current.theme === Themes.chosen && Themes.background.endsWith("/" + root.current.file);
                    return `${row.currentIndex + 1} of ${row.count}` + (using || (root.current.theme === Themes.chosen && root.current.file === "") ? "  ·  in use" : "");
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
                    key: "← →"
                    text: "Look"
                }

                KeyHint {
                    key: "↵"
                    text: "Use"
                }

                KeyHint {
                    key: "esc"
                    text: "Close"
                }
            }
        }
    }
}
