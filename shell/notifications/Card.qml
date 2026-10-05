import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets
import "glyphs.js" as Glyphs

// One notification as a popup, after Caelestia's card.
//
// An application shows its own icon, in colour and as large as the space;
// a critical one then has a red dot on the icon's corner, a low priority one
// a dimmed icon. Where the system speaks (a battery, the network, a plain
// "information") or there is no icon at all, a Tabler glyph sits on a disc
// whose colour says how urgent it is: see glyphs.js. A notification's own
// picture takes the icon's place, with rounded corners and nothing behind
// it, with the icon small on its corner.
//
// A card starts collapsed: title with its age, one line of the body, the
// action buttons. The arrow, or a click where there is no default action,
// expands it to the application's name and the whole text. For a job (a file
// copy, a download) the progress and its controls are always there.
//
// A click runs the default action. An expired notification has none, and no
// action buttons: KDE's engine expires one by itself about three minutes
// after it arrived, its application is then told it is closed, and the
// actions would do nothing. So has a record of a past run of the shell (see
// Notifications.qml). The cross, a middle click, or dragging
// the card off to the side closes it for good. Left alone it goes into the
// history after its time; hovering holds it.
Rectangle {
    id: root

    // the row of KDE's notification model, and the model for acting on it
    required property var model
    required property int index
    required property var notifications
    // how long it stays if the notification does not say (ms)
    required property int defaultTimeout
    // the current time, ticking, for the age
    required property real now
    // the popups are not visible right now
    property bool paused: false

    property bool expanded: false
    // more to see than the collapsed card shows
    readonly property bool expandable: expanded || summary.truncated || bodyText.truncated

    readonly property bool isJob: model.type === 2
    // its application still knows it: the actions work
    readonly property bool answerable: !(model.expired ?? false)
    // 1: low, 2: normal, 4: critical
    readonly property bool critical: model.urgency === 4
    readonly property bool low: model.urgency === 1
    // 0: stopped, 1: running, 2: suspended
    readonly property int jobState: model.jobState ?? 0
    // Milliseconds until it expires by itself; 0: stays. Notifications say
    // -1 for "the default", 0 for "until closed" (critical ones do). A job
    // stays while it runs and a little after it has ended.
    readonly property int timeout: {
        if (isJob)
            return jobState === 0 ? defaultTimeout : 0;
        return model.timeout === -1 ? defaultTimeout : model.timeout;
    }
    // KDE hands the body over as a small XML document
    readonly property string body: String(model.body ?? "").replace(/<\?xml[^>]*\?>/, "").replace(/<\/?html>/g, "").trim()
    // "now", "5m", "2h", "3d"
    readonly property string age: {
        const created = model.created;
        if (!created || isNaN(created.getTime()))
            return "";
        const seconds = (now - created.getTime()) / 1000;
        if (seconds < 60)
            return "now";
        if (seconds < 3600)
            return Math.floor(seconds / 60) + "m";
        if (seconds < 86400)
            return Math.floor(seconds / 3600) + "h";
        return Math.floor(seconds / 86400) + "d";
    }

    // the notification's icon, else its application's; "" if it has neither
    readonly property string iconName: model.iconName || model.applicationIconName || ""
    // The Tabler glyph that stands for it: one for a standard state or device
    // icon, the bell for no icon, "" for an application's icon (kept as it is).
    readonly property string glyph: iconName === "" ? "bell" : Glyphs.forIcon(iconName)
    // the disc under a glyph, and the glyph's colour on it
    readonly property color discColor: critical ? Theme.error : (low ? Theme.surfaceHover : Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.28)))
    readonly property color onDisc: critical ? Theme.bg : (low ? Theme.fgDim : Theme.accent)

    function modelIndex() {
        return notifications.index(index, 0);
    }

    // ---- dragging it away ---------------------------------------------------

    // how far it has been dragged; past `swipeAway` of its width it closes
    property real dragX: 0
    readonly property real swipeAway: 0.35
    property bool leaving: false

    function leave() {
        leaving = true;
        dragX = (dragX < 0 ? -1 : 1) * width * 1.2;
        gone.start();
    }

    transform: Translate {
        x: root.dragX
    }
    opacity: 1 - Math.min(1, Math.abs(dragX) / width) * 0.85

    Behavior on dragX {
        enabled: !drag.active

        Anim {
            kind: Anim.Fade
        }
    }

    Timer {
        id: gone

        interval: Theme.fadeDuration
        onTriggered: root.notifications.close(root.modelIndex())
    }

    DragHandler {
        id: drag

        target: null
        yAxis.enabled: false
        onActiveTranslationChanged: {
            if (active)
                root.dragX = activeTranslation.x;
        }
        onActiveChanged: {
            if (active)
                return;
            if (Math.abs(root.dragX) > root.width * root.swipeAway)
                root.leave();
            else
                root.dragX = 0;
        }
    }

    // ---- the card -----------------------------------------------------------

    implicitHeight: content.implicitHeight + Theme.padding * 2
    radius: 12
    color: Theme.surface

    Timer {
        interval: root.timeout
        running: root.timeout > 0 && !root.paused && !hover.hovered && !drag.active && !root.leaving
        onTriggered: root.notifications.expire(root.modelIndex())
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                root.notifications.close(root.modelIndex());
            else if (root.model.hasDefaultAction && root.answerable)
                root.notifications.invokeDefaultAction(root.modelIndex());
            else if (root.expandable)
                root.expanded = !root.expanded;
        }
    }

    RowLayout {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.padding
        }
        spacing: 12

        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 42
            implicitHeight: 42

            // The notification's own picture, filling the space. It was
            // round, on a disc: Kirigami drew it at the next smaller
            // standard icon size, 32 px in the 42, and the disc showed
            // around it as a ring.
            ClippingRectangle {
                anchors.fill: parent
                visible: picture.valid
                radius: 9
                color: "transparent"

                Icon {
                    id: picture

                    anchors.fill: parent
                    source: root.model.image ?? ""
                    fallback: ""
                    colorize: false
                    roundToIconSize: false
                }
            }

            // an application's icon: all of the space, or small on the picture's corner
            Icon {
                id: icon

                readonly property real size: picture.valid ? 21 : 42

                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    rightMargin: picture.valid ? -3 : 0
                    bottomMargin: picture.valid ? -3 : 0
                }
                width: size
                height: size
                visible: root.glyph === "" && valid
                opacity: root.low ? 0.55 : 1
                source: root.iconName
                fallback: ""
                colorize: false
            }

            // A glyph on its disc, likewise large or small. Also for an
            // application's icon the icon theme turns out not to have.
            Rectangle {
                readonly property real size: picture.valid ? 21 : 42

                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    rightMargin: picture.valid ? -3 : 0
                    bottomMargin: picture.valid ? -3 : 0
                }
                width: size
                height: size
                visible: !icon.visible && !(picture.valid && root.iconName === "")
                radius: width / 2
                color: root.discColor
                border.width: picture.valid ? 1.5 : 0
                border.color: Theme.surface

                Icon {
                    anchors.centerIn: parent
                    width: picture.valid ? 12 : 24
                    height: width
                    source: Quickshell.shellPath(`icons/tabler/${root.glyph || "bell"}.svg`)
                    color: root.onDisc
                }
            }

            // marks a critical one whose icon is in colour; a glyph's disc is red instead
            Rectangle {
                visible: root.critical && icon.visible && !picture.valid
                anchors {
                    right: parent.right
                    top: parent.top
                    rightMargin: -3
                    topMargin: -3
                }
                width: 15
                height: 15
                radius: width / 2
                color: Theme.error
                border.width: 1.5
                border.color: Theme.surface
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Label {
                Layout.fillWidth: true
                visible: root.expanded && text !== ""
                color: Theme.fgDim
                font.pixelSize: 11
                text: root.model.applicationName ?? ""
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                Label {
                    id: summary

                    Layout.fillWidth: true
                    font.pixelSize: 14
                    font.bold: true
                    wrapMode: root.expanded ? Text.WordWrap : Text.NoWrap
                    maximumLineCount: root.expanded ? 3 : 1
                    textFormat: Text.PlainText
                    // a notification without a title is its application
                    text: root.model.summary || root.model.applicationName || ""
                }

                Label {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 3
                    color: Theme.fgDim
                    font.pixelSize: 11
                    text: root.age
                }

                IconButton {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 21
                    implicitHeight: 21
                    visible: hover.hovered
                    source: "window-close-symbolic"
                    onClicked: root.notifications.close(root.modelIndex())
                }

                IconButton {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 21
                    implicitHeight: 21
                    visible: root.expandable
                    source: root.expanded ? "go-up-symbolic" : "go-down-symbolic"
                    onClicked: root.expanded = !root.expanded
                }
            }

            Label {
                id: bodyText

                Layout.fillWidth: true
                visible: root.body !== ""
                color: Theme.fgDim
                linkColor: Theme.accent
                wrapMode: root.expanded ? Text.WordWrap : Text.NoWrap
                maximumLineCount: root.expanded ? 12 : 1
                textFormat: Text.StyledText
                text: root.body
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // a job's progress
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 3
                visible: root.isJob && root.jobState !== 0
                implicitHeight: 6
                radius: 3
                color: Theme.surfaceActive

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, root.model.percentage ?? 0)) / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.jobState === 2 ? Theme.fgDim : Theme.accent

                    Behavior on width {
                        Anim {
                            kind: Anim.Fade
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 3
                visible: actions.count > 0 || jobControls.visible
                spacing: Theme.spacing

                Repeater {
                    id: actions

                    model: root.isJob || !root.answerable ? [] : (root.model.actionLabels ?? [])

                    Button {
                        required property string modelData
                        required property int index

                        raised: true
                        text: modelData
                        onClicked: root.notifications.invokeAction(root.modelIndex(), root.model.actionNames[index])
                    }
                }

                Row {
                    id: jobControls

                    visible: root.isJob && root.jobState !== 0
                    spacing: Theme.spacing

                    Button {
                        raised: true
                        visible: root.model.suspendable ?? false
                        text: root.jobState === 2 ? "Resume" : "Pause"
                        onClicked: root.jobState === 2 ? root.notifications.resumeJob(root.modelIndex()) : root.notifications.suspendJob(root.modelIndex())
                    }

                    Button {
                        raised: true
                        visible: root.model.killable ?? false
                        text: "Cancel"
                        onClicked: root.notifications.killJob(root.modelIndex())
                    }
                }
            }
        }
    }
}
