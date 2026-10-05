import Quickshell.Widgets
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// One item of the bar: the icon the bar draws for it, for a tray item a
// button that opens the list of icons to choose another from, and when it is
// in the bar. One of the bar's own modules has no icon to choose (it draws
// its state: the volume, the kind of network) and is only shown or hidden.
RowLayout {
    id: root

    required property BarItems icons
    required property IconPicker picker
    // of one of icons.entries
    required property string key
    // empty for the moment in which a row outlives its entry
    readonly property var entry: icons.byKey[key] ?? blank
    readonly property var blank: ({
            key: key,
            label: key,
            module: false,
            own: "",
            preset: "",
            icon: "",
            isChosen: false,
            hide: "",
            running: false
        })

    spacing: Kirigami.Units.smallSpacing

    Item {
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: Kirigami.Units.iconSizes.smallMedium

        // the item's own, as it comes
        IconImage {
            anchors.fill: parent
            visible: root.entry.icon === "" && root.entry.own !== ""
            source: visible ? root.entry.own : ""
        }

        // Drawn as the bar draws it (shell/modules/Tray.qml), in a square
        // of the bar's 18 px, so that it is the same picture: at another
        // size the icon theme can hand out another drawing.
        Kirigami.Icon {
            readonly property int glyphSize: root.icons.size(root.entry.icon, 18)

            anchors.centerIn: parent
            width: glyphSize || 18
            height: width
            roundToIconSize: glyphSize === 0
            visible: root.entry.icon !== ""
            source: root.icons.source(root.entry.icon)
            isMask: true
            color: Kirigami.Theme.textColor
        }
    }

    QQC2.Button {
        visible: !root.entry.module
        text: root.entry.icon === "" ? "Its own icon" : root.icons.describe(root.entry.icon)
        onClicked: root.picker.chooseFor(root.key)
    }

    QQC2.ComboBox {
        // what BarItems.hide() takes, in the order of the list; a module is
        // never idle
        readonly property list<string> whens: root.entry.module ? ["", "always"] : ["", "idle", "always"]

        model: root.entry.module ? ["Shown", "Hidden"] : ["Shown", "Hidden While Idle", "Hidden"]
        implicitContentWidthPolicy: QQC2.ComboBox.WidestText
        currentIndex: Math.max(0, whens.indexOf(root.entry.hide))
        onActivated: index => root.icons.hide(root.key, whens[index])
    }

    // what is chosen for an item that is not in the tray now can also be dropped
    QQC2.ToolButton {
        visible: !root.entry.running
        icon.name: "edit-delete"
        text: "Forget"
        display: QQC2.AbstractButton.IconOnly
        onClicked: root.icons.forget(root.key)

        QQC2.ToolTip.text: "Not in the tray now. Forget what is chosen for it"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
}
