//@ pragma UseQApplication
import Quickshell
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Settings for the shell, as an ordinary KDE window: not part of the shell's
// frame and not in its style, but Kirigami and Breeze like any other KDE
// settings page. It is a Quickshell config of its own, so it runs as a
// separate process (`qs -p <this directory>`, or "Shell settings" among the
// shell's ">" actions) and can use Breeze's widget style, which needs a
// QApplication; the shell itself does not have one.
ShellRoot {
    id: root

    Shortcuts {
        id: kdeShortcuts
    }

    FloatingWindow {
        title: "Quickshell Settings"
        implicitWidth: 600
        implicitHeight: 330
        minimumSize: Qt.size(480, 270)
        color: Kirigami.Theme.backgroundColor
        onClosed: Qt.quit()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Error
                visible: kdeShortcuts.error !== ""
                text: kdeShortcuts.error
            }

            // A requested key that KDE already uses for something else, with
            // the one click that frees it and sets it here.
            Kirigami.InlineMessage {
                id: conflictMessage

                // kept while the message animates away
                property string keyName: ""
                property string owners: ""
                property string wantedBy: ""

                Layout.fillWidth: true
                type: Kirigami.MessageType.Warning
                showCloseButton: true
                property bool foreign: false

                // another program keeps its key and is only overridden;
                // another action of the shell loses it
                text: foreign ? `${keyName} is already the shortcut for ${owners}. It stays that, and works there whenever the shell is not running.` : `${keyName} is already the shortcut for ${owners}.`
                // its close button hides it by assignment, so `visible` is
                // set from the handler below, not bound
                onVisibleChanged: {
                    if (!visible)
                        kdeShortcuts.dismiss();
                }
                actions: [
                    Kirigami.Action {
                        text: conflictMessage.foreign ? `Use it for "${conflictMessage.wantedBy}" while the shell runs` : `Remove it there and use it for "${conflictMessage.wantedBy}"`
                        icon.name: "edit-redo"
                        onTriggered: kdeShortcuts.takeOver()
                    }
                ]

                Connections {
                    target: kdeShortcuts

                    function onConflictChanged() {
                        const conflict = kdeShortcuts.conflict;
                        if (conflict) {
                            conflictMessage.keyName = conflict.text;
                            conflictMessage.owners = kdeShortcuts.conflictOwners;
                            conflictMessage.wantedBy = conflict.action.name;
                            conflictMessage.foreign = kdeShortcuts.conflictForeign;
                        }
                        conflictMessage.visible = conflict !== null;
                    }
                }
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Shortcuts"
                }

                // one field per action the shell has registered with KDE
                Repeater {
                    model: kdeShortcuts.actions

                    ShortcutField {
                        required property var modelData

                        Kirigami.FormData.label: modelData.name + ":"
                        shortcuts: kdeShortcuts
                        action: modelData
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
