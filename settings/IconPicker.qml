import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The icons to choose from for one tray item: the shell's Tabler glyphs and
// the icon theme's one-colour icons, drawn in one colour as the bar draws
// them. A click on one sets it at once, and the bar shows it, so the dialog
// stays open for trying another. Below are the two choices that are not in
// the list: the item's own icon, and what the shell draws for it unasked.
QQC2.Dialog {
    id: root

    required property BarItems icons
    // of one of icons.entries
    property string key: ""
    readonly property var entry: icons.byKey[key] ?? null
    // the icon under the pointer, or ""
    property string pointed: ""

    readonly property list<string> shown: {
        const words = search.text.toLowerCase().split(/\s+/).filter(word => word !== "");
        const which = sets.currentIndex;
        return icons.names.filter(name => (which === 0 || (which === 2) === name.startsWith("tabler/")) && words.every(word => name.includes(word)));
    }

    function chooseFor(key: string): void {
        root.key = key;
        search.text = "";
        icons.loadNames();
        open();
        search.forceActiveFocus();
    }

    anchors.centerIn: parent
    width: parent.width - Kirigami.Units.gridUnit * 2
    height: parent.height - Kirigami.Units.gridUnit * 2
    modal: true
    title: entry ? `Icon for ${entry.label}` : ""
    // its row has gone: the item left the tray and nothing was chosen for it
    onEntryChanged: {
        if (!entry)
            close();
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Kirigami.SearchField {
                id: search

                Layout.fillWidth: true
            }

            QQC2.ComboBox {
                id: sets

                model: ["All Icons", "Icon Theme", "Tabler Glyphs"]
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            background: Rectangle {
                Kirigami.Theme.colorSet: Kirigami.Theme.View
                Kirigami.Theme.inherit: false
                color: Kirigami.Theme.backgroundColor
                border.color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, Kirigami.Theme.frameContrast)
                radius: Kirigami.Units.cornerRadius
            }

            GridView {
                id: grid

                readonly property int cell: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.largeSpacing * 2

                clip: true
                topMargin: Kirigami.Units.smallSpacing
                bottomMargin: Kirigami.Units.smallSpacing
                leftMargin: Kirigami.Units.smallSpacing
                // as many columns as fit, spread over the width
                cellWidth: Math.floor((width - leftMargin * 2) / Math.max(1, Math.floor((width - leftMargin * 2) / cell)))
                cellHeight: cell
                model: root.shown

                delegate: Item {
                    id: cell

                    required property string modelData
                    readonly property bool current: root.entry?.icon === modelData

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: Kirigami.Units.cornerRadius
                        color: Kirigami.Theme.highlightColor
                        opacity: cell.current ? 0.35 : pointer.containsMouse ? 0.15 : 0
                    }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        source: root.icons.source(cell.modelData)
                        isMask: true
                        color: Kirigami.Theme.textColor
                    }

                    MouseArea {
                        id: pointer

                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: {
                            if (containsMouse)
                                root.pointed = cell.modelData;
                            else if (root.pointed === cell.modelData)
                                root.pointed = "";
                        }
                        onClicked: root.icons.choose(root.key, cell.modelData)
                    }
                }
            }
        }

        // what the pointer is on, else what is set
        QQC2.Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: {
                if (root.pointed !== "")
                    return root.icons.describe(root.pointed);
                if (root.icons.names.length === 0)
                    return "Listing the icons…";
                if (root.shown.length === 0)
                    return "No icon of that name.";
                const icon = root.entry?.icon ?? "";
                return icon === "" ? "The bar shows its own icon." : `The bar shows ${root.icons.describe(icon)}.`;
            }
        }
    }

    footer: QQC2.DialogButtonBox {
        QQC2.Button {
            text: "Its Own Icon"
            enabled: (root.entry?.icon ?? "") !== ""
            QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.ActionRole
            onClicked: root.icons.choose(root.key, "")
        }

        // only where the shell draws something of its own unasked;
        // elsewhere that is "its own icon"
        QQC2.Button {
            text: `Default (${root.icons.describe(root.entry?.preset ?? "")})`
            visible: (root.entry?.preset ?? "") !== ""
            enabled: root.entry?.isChosen ?? false
            QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.ResetRole
            onClicked: root.icons.reset(root.key)
        }

        QQC2.Button {
            text: "Close"
            icon.name: "dialog-close"
            QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
            onClicked: root.close()
        }
    }
}
