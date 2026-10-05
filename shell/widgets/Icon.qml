import QtQuick
import org.kde.kirigami as Kirigami
import qs

// Icon from the system icon theme. Takes a name or a QIcon (e.g. a model's
// `decoration` role). Symbolic icons are recoloured so they stay readable on
// the bar regardless of the Plasma colour scheme.
Kirigami.Icon {
    property bool colorize: true
    // Set where this is the icon of one of the bar's modules ("audio", see
    // symbols.js): the settings window shows the same icon for the module,
    // whatever it is at the moment, and asks BarItems for it.
    property string module: ""

    function report() {
        if (module !== "")
            BarItems.report(module, String(source));
    }

    onSourceChanged: report()
    Component.onCompleted: report()

    implicitWidth: Theme.iconSize
    implicitHeight: Theme.iconSize
    isMask: colorize
    color: Theme.fg
}
