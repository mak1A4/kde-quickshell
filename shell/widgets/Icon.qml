import QtQuick
import org.kde.kirigami as Kirigami
import qs

// Icon from the system icon theme. Takes a name or a QIcon (e.g. a model's
// `decoration` role). Symbolic icons are recoloured so they stay readable on
// the bar regardless of the Plasma colour scheme.
Kirigami.Icon {
    property bool colorize: true

    implicitWidth: Theme.iconSize
    implicitHeight: Theme.iconSize
    isMask: colorize
    color: Theme.fg
}
