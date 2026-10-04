import QtQuick
import qs

// The notifications to show right now, newest and most urgent first, as a
// column of cards. The Frame hangs it from the top edge beside the bar.
// Which ones, how many and for how long is KDE's notification model's
// business (see Service.qml).
Item {
    id: root

    required property var notifications
    // how long a popup stays unless the notification says otherwise (ms)
    required property int timeout
    // not visible right now: the cards' clocks stand still
    property bool paused: false

    readonly property int count: cards.count
    // for the cards' ages
    property real now: Date.now()

    Timer {
        interval: 20000
        running: root.count > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
    readonly property int margin: 12
    readonly property int cardWidth: 345

    implicitWidth: cardWidth + margin * 2
    implicitHeight: count > 0 ? column.implicitHeight + margin * 2 : 0

    Column {
        id: column

        x: root.margin
        y: root.margin
        spacing: 9

        Repeater {
            id: cards

            model: root.notifications

            Card {
                width: root.cardWidth
                notifications: root.notifications
                defaultTimeout: root.timeout
                now: root.now
                paused: root.paused
            }
        }
    }
}
