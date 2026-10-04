import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// The session menu. Lock and sleep act at once; anything that ends the
// session arms on the first click and acts on the second.
Item {
    id: root

    // id of the action waiting for its confirming click
    property string armed: ""

    implicitWidth: 270
    implicitHeight: column.implicitHeight + Theme.padding * 2

    // an armed action forgets itself if the second click doesn't come
    Timer {
        id: disarm

        interval: 4000
        onTriggered: root.armed = ""
    }

    ColumnLayout {
        id: column

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: Theme.padding
        }
        spacing: 3

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.bottomMargin: Theme.spacing
            font.pixelSize: 15
            font.bold: true
            text: "Session"
        }

        Repeater {
            model: SessionActions.available

            Rectangle {
                id: row

                required property var modelData
                readonly property bool armed: root.armed === modelData.id

                Layout.fillWidth: true
                implicitHeight: 42
                radius: 9
                color: armed ? Theme.error : (mouse.containsMouse ? Theme.surfaceHover : "transparent")

                Behavior on color {
                    ColorAnim {}
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 12
                    }
                    spacing: 12

                    Icon {
                        source: row.modelData.icon
                        color: row.armed ? Theme.accentFg : Theme.fg
                    }

                    Label {
                        Layout.fillWidth: true
                        color: row.armed ? Theme.accentFg : Theme.fg
                        font.bold: row.armed
                        text: row.armed ? `Click again to ${row.modelData.title.toLowerCase()}` : row.modelData.title
                    }
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (row.modelData.confirm && !row.armed) {
                            root.armed = row.modelData.id;
                            disarm.restart();
                            return;
                        }
                        root.armed = "";
                        Popouts.close();
                        SessionActions.run(row.modelData);
                    }
                }
            }
        }
    }
}
