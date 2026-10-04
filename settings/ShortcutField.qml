import QtQuick
import org.kde.kquickcontrols as KQuickControls

// KDE's own shortcut button for one of the shell's actions. It records the
// keys, with global shortcuts held off meanwhile, so a combination that is in
// use can be pressed too. Its own check for conflicts (a dialog) is off:
// Shortcuts checks, and the window offers the takeover in place.
KQuickControls.KeySequenceItem {
    id: root

    required property Shortcuts shortcuts
    // one of shortcuts.actions; a new field is made whenever they are read again
    required property var action

    multiKeyShortcutsAllowed: false
    checkForConflictsAgainst: KQuickControls.ShortcutType.None
    // a new combination, or the clear button
    onKeySequenceModified: shortcuts.request(action, String(keySequence))
    Component.onCompleted: keySequence = action.keyText
}
