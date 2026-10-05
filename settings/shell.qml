//@ pragma UseQApplication
import Quickshell
import QtQuick
import QtQuick.Controls as QQC2
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

    BarItems {
        id: barItems
    }

    FloatingWindow {
        title: "Quickshell Settings"
        implicitWidth: 720
        implicitHeight: 720
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
                id: shortcutForm

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

            // A form of its own, its labels in line with the one above: in
            // one form the rows of the two lists, which arrive as KDE and
            // the tray answer, would mix.
            Kirigami.FormLayout {
                Layout.fillWidth: true
                twinFormLayouts: [shortcutForm]
                visible: barItems.keys.length > 0

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Icons in the Bar"
                }

                // One field per module of the bar, per item in the tray, and
                // per choice for a tray item that is not there now. A ScriptModel, so that a row is
                // only made or removed when its item comes or goes: the form
                // complains about every row taken from it.
                Repeater {
                    model: ScriptModel {
                        values: barItems.keys
                    }

                    BarItemField {
                        required property string modelData

                        Kirigami.FormData.label: entry.label + ":"
                        icons: barItems
                        picker: iconPicker
                        key: modelData
                    }
                }
            }

            // below the form, not in it: there it would sit among the rows,
            // wherever they had got to when it was made
            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                visible: barItems.keys.length > 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: "Hidden icons appear when you click the arrow above the icons in the bar. One that is hidden while idle comes back by itself while it has something to show, like unread messages."
            }

            Item {
                Layout.fillHeight: true
            }
        }

        IconPicker {
            id: iconPicker

            icons: barItems
        }
    }
}
