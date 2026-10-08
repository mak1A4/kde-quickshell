import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets

// The clock's popout: the time and the day at the top, a month to look
// through, and what is on the day that is picked (Events.qml: holidays and
// calendars, from Plasma's own plugins, where that module is installed).
//
// The month is turned with the arrows or the wheel and slides in from the
// side it came from; a click on its name, or on "Today", goes back. Names of
// days and months, the first day of the week and the date's form are the
// system's (its date format); week numbers are ISO weeks.
Item {
    id: root

    required property date now

    readonly property int margin: 15
    readonly property int weekColumn: 30
    readonly property int cellWidth: Math.floor((implicitWidth - margin * 2 - weekColumn) / 7 / 3) * 3
    readonly property int cellHeight: 36
    readonly property var locale: Qt.locale()
    // 0 Sunday ... 6 Saturday, as JavaScript counts
    readonly property int firstDay: locale.firstDayOfWeek % 7

    // "2026-10-07": only changes at midnight
    readonly property string todayKey: key(now)
    readonly property date today: fromKey(todayKey)
    // the first of the month that is shown
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)
    property string pickedKey: todayKey
    readonly property date picked: fromKey(pickedKey)
    readonly property bool atToday: pickedKey === todayKey && month.getFullYear() === today.getFullYear() && month.getMonth() === today.getMonth()

    // a day that began while the popout was open: today moves on, and what
    // was picked with it if it was today
    onTodayKeyChanged: goToday()

    implicitWidth: Theme.popupWidth
    implicitHeight: column.implicitHeight + margin * 2

    function key(date: date): string {
        return Qt.formatDate(date, "yyyy-MM-dd");
    }

    function fromKey(key: string): date {
        const parts = key.split("-");
        return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    }

    // ISO 8601: the week belongs to the year its Thursday is in
    function week(date: date): int {
        const thursday = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 3 - (date.getDay() + 6) % 7);
        const first = new Date(thursday.getFullYear(), 0, 4);
        return 1 + Math.round(((thursday - first) / 86400000 - 3 + (first.getDay() + 6) % 7) / 7);
    }

    // The six weeks that hold the month, a week a row:
    // [{ week, days: [{ key, date, number, inMonth, weekend }] }]
    readonly property var weeks: {
        const lead = (month.getDay() - firstDay + 7) % 7;
        const rows = [];
        for (let row = 0; row < 6; row++) {
            const days = [];
            for (let column = 0; column < 7; column++) {
                const date = new Date(month.getFullYear(), month.getMonth(), 1 - lead + row * 7 + column);
                days.push({
                    key: key(date),
                    date: date,
                    number: date.getDate(),
                    inMonth: date.getMonth() === month.getMonth(),
                    weekend: date.getDay() === 0 || date.getDay() === 6
                });
            }
            // the week its middle day is in, whatever day weeks begin on
            rows.push({
                week: week(days[3].date),
                days: days
            });
        }
        return rows;
    }

    // +1 the month after, -1 the one before
    function turn(by: int): void {
        slide.from = by * 36;
        month = new Date(month.getFullYear(), month.getMonth() + by, 1);
        slide.restart();
        fade.restart();
    }

    function goToday(): void {
        const there = new Date(today.getFullYear(), today.getMonth(), 1);
        const by = Math.sign(there - month);
        pickedKey = todayKey;
        if (by !== 0) {
            slide.from = by * 36;
            month = there;
            slide.restart();
            fade.restart();
        }
    }

    function pick(day: var): void {
        pickedKey = day.key;
        if (!day.inMonth)
            turn(day.date < month ? -1 : 1);
    }

    // holidays and calendars: optional
    Loader {
        id: events

        source: Qt.resolvedUrl("Events.qml")
        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("Clock: Plasma's calendar module is not loadable; the calendar has no holidays or events");
        }

        Binding {
            target: events.item
            property: "month"
            value: root.month
            when: events.status === Loader.Ready
        }

        Binding {
            target: events.item
            property: "today"
            value: root.today
            when: events.status === Loader.Ready
        }
    }

    function eventsOn(date: date): var {
        return events.item ? events.item.forDate(date) : [];
    }

    readonly property var pickedEvents: eventsOn(picked)

    // While the popout is open: `qs ipc call calendar pick 2026-12-25`
    IpcHandler {
        target: "calendar"

        // goes to that day's month and picks the day
        function pick(day: string): string {
            if (!/^\d{4}-\d{2}-\d{2}$/.test(day))
                return "a day is written 2026-12-25";
            const date = root.fromKey(day);
            const by = Math.sign(new Date(date.getFullYear(), date.getMonth(), 1) - root.month);
            root.pickedKey = root.key(date);
            if (by !== 0) {
                slide.from = by * 36;
                root.month = new Date(date.getFullYear(), date.getMonth(), 1);
                slide.restart();
                fade.restart();
            }
            return root.pickedKey;
        }

        // what is on the picked day, a line each
        function events(): string {
            return root.pickedEvents.map(event => `${event.holiday ? (event.minor ? "observance" : "holiday") : "event"}: ${event.title}`).join("\n");
        }
    }

    ColumnLayout {
        id: column

        x: root.margin
        y: root.margin
        width: root.implicitWidth - root.margin * 2
        spacing: 12

        // the time, and the day in words
        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            Label {
                elide: Text.ElideNone
                font.pixelSize: 42
                font.bold: true
                font.features: ({
                        tnum: 1
                    })
                text: Qt.formatDateTime(root.now, "HH:mm")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    Layout.fillWidth: true
                    font.pixelSize: 18
                    font.bold: true
                    text: root.locale.toString(root.today, "dddd")
                }

                Label {
                    Layout.fillWidth: true
                    color: Theme.fgDim
                    text: root.locale.toString(root.today, "d MMMM yyyy")
                }

                Label {
                    Layout.fillWidth: true
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontSizeSmall + 1
                    text: "Week " + root.week(root.today)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1.5
            color: Theme.surface
        }

        // the month's name, and through the months
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            Label {
                Layout.fillWidth: true
                font.pixelSize: 15
                font.bold: true
                text: root.locale.standaloneMonthName(root.month.getMonth()) + " " + root.month.getFullYear()

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    onClicked: root.goToday()
                }
            }

            // only while somewhere else
            Rectangle {
                implicitWidth: todayLabel.implicitWidth + 18
                implicitHeight: 24
                radius: 12
                color: todayMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                opacity: root.atToday ? 0 : 1
                visible: opacity > 0

                Behavior on opacity {
                    Anim {
                        kind: Anim.Fade
                    }
                }

                Behavior on color {
                    ColorAnim {}
                }

                Label {
                    id: todayLabel

                    anchors.centerIn: parent
                    font.pixelSize: Theme.fontSizeSmall + 1
                    text: "Today"
                }

                MouseArea {
                    id: todayMouse

                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.goToday()
                }
            }

            IconButton {
                source: "go-previous-symbolic"
                onClicked: root.turn(-1)
            }

            IconButton {
                source: "go-next-symbolic"
                onClicked: root.turn(1)
            }
        }

        // the month
        Item {
            Layout.fillWidth: true
            implicitHeight: 24 + root.cellHeight * 6
            clip: true

            // one notch of the wheel, one month
            WheelHandler {
                property real rest: 0

                onWheel: event => {
                    rest += event.angleDelta.y;
                    const notches = rest > 0 ? Math.floor(rest / 120) : Math.ceil(rest / 120);
                    rest -= notches * 120;
                    if (notches !== 0)
                        root.turn(notches > 0 ? -1 : 1);
                }
            }

            // the days' names
            Row {
                x: root.weekColumn
                height: 24

                Repeater {
                    model: 7

                    Label {
                        required property int index
                        readonly property int day: (root.firstDay + index) % 7

                        width: root.cellWidth
                        height: 24
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontSizeSmall + 1
                        text: root.locale.standaloneDayName(day, Locale.ShortFormat)
                    }
                }
            }

            Column {
                id: grid

                y: 24

                NumberAnimation on x {
                    id: slide

                    running: false
                    to: 0
                    duration: Theme.moveDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.moveCurve
                }

                NumberAnimation on opacity {
                    id: fade

                    running: false
                    from: 0
                    to: 1
                    duration: Theme.fadeDuration
                }

                Repeater {
                    model: root.weeks

                    Row {
                        id: weekRow

                        required property var modelData

                        Label {
                            width: root.weekColumn
                            height: root.cellHeight
                            verticalAlignment: Text.AlignVCenter
                            color: Theme.fgDim
                            opacity: 0.6
                            font.pixelSize: Theme.fontSizeSmall
                            text: weekRow.modelData.week
                        }

                        Repeater {
                            model: weekRow.modelData.days

                            Item {
                                id: cell

                                required property var modelData
                                readonly property bool isToday: modelData.key === root.todayKey
                                readonly property bool isPicked: modelData.key === root.pickedKey
                                readonly property var events: root.eventsOn(modelData.date)
                                readonly property bool holiday: events.some(event => event.holiday && !event.minor)
                                readonly property bool busy: events.some(event => !event.holiday)

                                width: root.cellWidth
                                height: root.cellHeight

                                Rectangle {
                                    id: disc

                                    anchors.centerIn: parent
                                    width: 30
                                    height: 30
                                    radius: 15
                                    color: cell.isToday ? Theme.accent : (cell.isPicked ? Theme.surfaceActive : (mouse.containsMouse ? Theme.surfaceHover : Theme.none))

                                    Behavior on color {
                                        ColorAnim {
                                            duration: Theme.followDuration
                                        }
                                    }
                                }

                                Label {
                                    anchors.centerIn: parent
                                    elide: Text.ElideNone
                                    font.bold: cell.isToday || cell.isPicked
                                    opacity: cell.modelData.inMonth || cell.isToday ? 1 : 0.4
                                    color: {
                                        if (cell.isToday)
                                            return Theme.accentFg;
                                        if (cell.holiday)
                                            return Theme.error;
                                        return cell.modelData.weekend ? Theme.fgDim : Theme.fg;
                                    }
                                    text: cell.modelData.number
                                }

                                // something is on that day
                                Rectangle {
                                    anchors {
                                        horizontalCenter: parent.horizontalCenter
                                        bottom: disc.bottom
                                        bottomMargin: 3
                                    }
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    visible: cell.busy
                                    color: cell.isToday ? Theme.accentFg : Theme.accent
                                }

                                MouseArea {
                                    id: mouse

                                    cursorShape: Qt.PointingHandCursor
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.pick(cell.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1.5
            color: Theme.surface
        }

        // the day that is picked, and what is on it
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            RowLayout {
                Layout.fillWidth: true

                Label {
                    Layout.fillWidth: true
                    font.bold: true
                    text: root.pickedKey === root.todayKey ? "Today" : root.locale.toString(root.picked, "dddd, d MMMM")
                }

                Label {
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontSizeSmall + 1
                    text: {
                        const days = Math.round((root.picked - root.today) / 86400000);
                        if (days === 0)
                            return "";
                        if (days === 1)
                            return "Tomorrow";
                        if (days === -1)
                            return "Yesterday";
                        return days > 0 ? `In ${days} days` : `${-days} days ago`;
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: root.pickedEvents.length === 0
                color: Theme.fgDim
                text: "Nothing on this day"
            }

            Repeater {
                model: root.pickedEvents

                RowLayout {
                    id: entry

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 9

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 3
                        implicitWidth: 4.5
                        implicitHeight: Math.max(15, texts.implicitHeight - 6)
                        radius: 2.25
                        color: entry.modelData.holiday ? Theme.error : (entry.modelData.color || Theme.accent)
                        opacity: entry.modelData.minor ? 0.5 : 1
                    }

                    ColumnLayout {
                        id: texts

                        Layout.fillWidth: true
                        spacing: 0

                        Label {
                            Layout.fillWidth: true
                            text: entry.modelData.title
                        }

                        Label {
                            Layout.fillWidth: true
                            color: Theme.fgDim
                            font.pixelSize: Theme.fontSizeSmall + 1
                            text: {
                                const what = entry.modelData.holiday ? (entry.modelData.minor ? "Observance" : "Public holiday") : (entry.modelData.allDay ? "All day" : root.locale.toString(entry.modelData.start, "HH:mm"));
                                return entry.modelData.description && entry.modelData.description !== entry.modelData.title ? what + "  ·  " + entry.modelData.description : what;
                            }
                        }
                    }
                }
            }
        }
    }
}
