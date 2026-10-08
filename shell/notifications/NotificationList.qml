import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// The list that grows out of the frame's bottom left corner (see the Frame):
// every notification not yet closed, as the same cards the popups use (they
// do not expire here), grouped by application. Above it: do not disturb,
// clear, and the way to System Settings.
//
// What it shows is the history's entries (Notifications.qml), not KDE's
// model directly: an entry is a notification the engine still has (then its
// card is the model's row, with its picture and, while it is open towards
// its application, its actions), or a record of one it no longer has, left
// by a past run of the shell or taken back by its application (text, time
// and icon; no actions).
//
// An application with one notification is just its card. With several it is
// a group: a header with its name and how many, the newest card, and the
// rest when the header is clicked. The cross on the header closes them all.
// Jobs (a file copy) are not in the history; while there are some they are
// on top.
Item {
    id: root

    readonly property var notifications: Notifications.history
    readonly property int cardWidth: 345
    readonly property int maxListHeight: 540
    // for the cards' ages
    property real now: Date.now()
    // nothing at all to show
    readonly property bool empty: Notifications.groupNames.length === 0 && jobs.length === 0

    implicitWidth: cardWidth + Theme.padding * 2
    implicitHeight: column.implicitHeight + Theme.padding * 2

    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // ---- the engine's rows, to hand to the cards ------------------------------
    //
    // A card takes a row of KDE's model. These hold one each, by the
    // notification's id (and the jobs, in the model's order).
    property var rows: ({})
    property list<QtObject> jobs: []

    function collect(leaving) {
        const rows = {};
        const jobs = [];
        for (let n = 0; n < holders.count; n++) {
            const holder = holders.objectAt(n);
            if (!holder || holder === leaving)
                continue;
            if (holder.model.type === 2)
                jobs.push(holder);
            else
                rows[String(holder.model.notificationId)] = holder;
        }
        root.rows = rows;
        root.jobs = jobs;
    }

    Instantiator {
        id: holders

        model: root.notifications
        delegate: QtObject {
            required property var model
            required property int index
        }
        onObjectAdded: root.collect(null)
        // it is on its way out, and no card may keep it
        onObjectRemoved: (index, object) => root.collect(object)
    }

    // One entry as a card: the engine's row if it has one, else the entry
    // dressed as such a row.
    component EntryCard: Card {
        id: entryCard

        required property string key
        // for a record, in the model's place: something that can only close it
        readonly property QtObject recordActions: QtObject {
            function index(row, column) {
                return entryCard.key;
            }

            function close(key) {
                Notifications.forget(key);
            }

            function expire(key) {
            }
        }
        readonly property var entry: Notifications.byKey[key] ?? null
        readonly property QtObject row: entry && entry.session === Notifications.session ? root.rows[entry.id] ?? null : null

        model: row ? row.model : ({
                type: 1,
                urgency: entry?.urgency ?? 2,
                timeout: 0,
                expired: true,
                created: new Date(entry?.created ?? 0),
                applicationName: entry?.applicationName ?? "",
                applicationIconName: entry?.applicationIconName ?? "",
                iconName: entry?.iconName ?? "",
                summary: entry?.summary ?? "",
                body: entry?.body ?? "",
                hasDefaultAction: false
            })
        index: row ? row.index : 0
        notifications: row ? root.notifications : recordActions
        // it stays until it is closed or the list is cleared
        defaultTimeout: 0
        paused: true
        now: root.now
    }

    ColumnLayout {
        id: column

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: Theme.padding
        }
        spacing: Theme.padding

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 3
            spacing: Theme.spacing

            Label {
                Layout.fillWidth: true
                font.pixelSize: 15
                font.bold: true
                text: "Notifications"
            }

            Label {
                color: Theme.fgDim
                font.pixelSize: 12
                text: "Do not disturb"
            }

            Toggle {
                Layout.rightMargin: Theme.spacing
                checked: Notifications.doNotDisturb
                onToggled: Notifications.backend?.setDoNotDisturb(!checked)
            }

            IconButton {
                visible: !root.empty
                source: "edit-clear-history-symbolic"
                onClicked: Notifications.clearAll()
            }

            IconButton {
                source: "configure-symbolic"
                onClicked: {
                    Quickshell.execDetached(["kcmshell6", "kcm_notifications"]);
                    Notifications.listOpen = false;
                }
            }
        }

        ListView {
            id: list

            Layout.fillWidth: true
            implicitHeight: Math.min(contentHeight, root.maxListHeight)
            visible: !root.empty
            clip: true
            spacing: 9
            boundsBehavior: Flickable.StopAtBounds
            // a ScriptModel: a group, and its cards, stay while others change
            model: ScriptModel {
                values: Notifications.groupNames
            }

            header: Column {
                width: list.width
                spacing: list.spacing
                bottomPadding: root.jobs.length > 0 && list.count > 0 ? list.spacing : 0

                Repeater {
                    model: root.jobs

                    Item {
                        id: job

                        required property QtObject modelData

                        width: list.width
                        implicitHeight: jobCard.implicitHeight

                        Card {
                            id: jobCard

                            width: parent.width
                            model: job.modelData.model
                            index: job.modelData.index
                            notifications: root.notifications
                            defaultTimeout: 0
                            paused: true
                            now: root.now
                        }
                    }
                }
            }

            delegate: Column {
                id: group

                // the application's name
                required property string modelData
                // its entries, newest first
                readonly property var keys: Notifications.groups[modelData] ?? []
                readonly property var newest: Notifications.byKey[keys[0]] ?? null
                property bool expanded: false

                width: list.width
                spacing: 6

                // the header, for more than one
                Item {
                    width: parent.width
                    implicitHeight: 24
                    visible: group.keys.length > 1

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 3
                        }
                        spacing: Theme.spacing

                        Icon {
                            implicitWidth: 15
                            implicitHeight: 15
                            visible: valid && source !== ""
                            source: group.newest?.applicationIconName ?? ""
                            fallback: ""
                            colorize: false
                        }

                        Label {
                            font.pixelSize: 12
                            font.bold: true
                            color: Theme.fgDim
                            text: group.modelData || "Notifications"
                        }

                        Label {
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: Theme.fgDim
                            text: group.expanded ? String(group.keys.length) : `${group.keys.length - 1} more`
                        }

                        IconButton {
                            implicitWidth: 21
                            implicitHeight: 21
                            visible: headerHover.hovered
                            source: "window-close-symbolic"
                            onClicked: Notifications.closeGroup(group.modelData)
                        }

                        IconButton {
                            implicitWidth: 21
                            implicitHeight: 21
                            source: group.expanded ? "go-up-symbolic" : "go-down-symbolic"
                            onClicked: group.expanded = !group.expanded
                        }
                    }

                    HoverHandler {
                        id: headerHover
                    }

                    // under the buttons: a click anywhere else on the header
                    MouseArea {
                        cursorShape: Qt.PointingHandCursor
                        anchors.fill: parent
                        z: -1
                        onClicked: group.expanded = !group.expanded
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: group.expanded ? group.keys : group.keys.slice(0, 1)
                    }

                    Item {
                        id: slot

                        required property string modelData

                        width: group.width
                        implicitHeight: card.implicitHeight

                        EntryCard {
                            id: card

                            width: parent.width
                            key: slot.modelData
                        }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: Theme.padding
            Layout.bottomMargin: Theme.padding
            visible: root.empty
            horizontalAlignment: Text.AlignHCenter
            color: Theme.fgDim
            text: Notifications.serving ? "No notifications" : "Plasma is showing the notifications"
        }
    }
}
