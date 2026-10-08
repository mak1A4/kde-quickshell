import QtQuick
import org.kde.plasma.workspace.calendar as PlasmaCalendar

// What is on a day, from Plasma's calendar: its event plugins (public
// holidays, and the calendars of KDE's PIM where that is installed), through
// the backend Plasma's own calendar uses. The calendar in CalendarPanel.qml
// loads this with a Loader and does without it where the module is missing:
// the import is optional.
//
// Which holidays: the regions in ~/.config/plasma_calendar_holiday_regions
// (Plasma's file; setup.sh writes it once, from the country of the date
// format), else those of the language's country.
Item {
    id: root

    // any day of the month that is looked at
    property date month: new Date()
    property date today: new Date()
    // counts up when the plugins have something new: what depends on
    // forDate() is then asked again
    property int revision: 0

    PlasmaCalendar.EventPluginsManager {
        id: plugins

        enabledPlugins: ["holidaysevents", "pimevents"]
    }

    PlasmaCalendar.Calendar {
        id: backend

        days: 7
        weeks: 6
        firstDayOfWeek: Qt.locale().firstDayOfWeek
        today: root.today
        displayedDate: root.month

        Component.onCompleted: daysModel.setPluginsManager(plugins)
    }

    Connections {
        target: backend.daysModel

        function onAgendaUpdated() {
            root.revision++;
        }

        function onModelReset() {
            root.revision++;
        }
    }

    // [{ title, description, allDay, minor, color, holiday, start }]: only
    // for days of the six weeks around `month`
    function forDate(date: date): var {
        revision;
        const found = [];
        for (const event of backend.daysModel.eventsForDate(date) ?? []) {
            found.push({
                title: event.title,
                description: event.description,
                allDay: event.isAllDay,
                minor: event.isMinor,
                color: event.eventColor,
                // a word, in the system's language: "Holidays" where that is English
                holiday: /^holiday/i.test(String(event.eventType)),
                start: event.startDateTime
            });
        }
        return found;
    }
}
