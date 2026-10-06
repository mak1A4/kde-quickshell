import QtCore
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.plasma.private.sessions

// What the lock screen shows: the shell's frame round the wallpaper, a clock
// on it, and two panels that come out of the frame when a key is pressed or
// the pointer moves, as the shell's own panels do. From the top edge, where
// the command palette hangs, the password; from the bottom edge, where the
// dock is, what else can be done. With nothing typed they go back after ten
// seconds, or at Escape.
//
// From kscreenlocker: `authenticator` (PAM), `kscreenlocker_userName`,
// `kscreenlocker_userImage`, and `root` (LockScreen.qml).
Item {
    id: ui

    // ---- look ------------------------------------------------------------

    // The shell's colours and sizes: the file it writes at each change of
    // theme, or without it the ones this comes with.
    DefaultLook {
        id: defaultLook
    }

    Loader {
        id: shellLook

        source: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/kde-quickshell/lock/Look.qml"
    }

    readonly property QtObject look: shellLook.item ?? defaultLook

    // ---- state -----------------------------------------------------------

    // whether the panels are out
    property bool active: false
    // Unlocked without a password having been asked for (there is none, or a
    // fingerprint did it): all that is wanted now is Enter.
    property bool unlocked: false
    // No typing for a moment after a wrong password. Not every kscreenlocker
    // has `graceLocked`, and a binding that gives undefined keeps its last
    // value: without the comparison this stayed true after the first failure.
    readonly property bool held: graceTimer.running || authenticator.graceLocked === true
    readonly property bool failed: failedTimer.running
    // The machine went to sleep with the password asked for. kscreenlocker
    // takes the question back then, and reports that as a failure: it is not
    // a wrong password, and is only asked again.
    property bool slept: false
    readonly property string message: {
        const parts = [];
        if (capsLock.locked)
            parts.push("Caps Lock is on");
        if (root.notification !== "")
            parts.push(root.notification);
        return parts.join("  ·  ");
    }
    property date now: new Date()

    function wake() {
        if (!active)
            Window.window?.requestActivate();
        active = true;
        idleTimer.restart();
        field.forceActiveFocus();
    }

    onActiveChanged: {
        if (active)
            authenticator.startAuthenticating();
    }

    function note(text) {
        if (text === "")
            return;
        if (root.notification === "")
            root.notification = text;
        else if (root.notification.includes(text))
            root.notificationRepeated();
        else
            root.notification += "\n" + text;
    }

    function submit() {
        if (unlocked) {
            Qt.quit();
        } else if (!held) {
            // what fails from here on is this answer
            slept = false;
            authenticator.respond(field.text);
        }
    }

    Connections {
        target: authenticator

        function onFailed(kind) {
            // 0 is the password; the others (fingerprint, card) say so themselves
            if (kind != 0)
                return;
            if (ui.slept) {
                ui.slept = false;
                authenticator.startAuthenticating();
                return;
            }
            ui.note("Wrong password");
            graceTimer.restart();
            failedTimer.restart();
            noteTimer.restart();
            shake.restart();
        }

        function onSucceeded() {
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                ui.unlocked = true;
                ui.wake();
            }
        }

        function onInfoMessageChanged() {
            ui.note(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            ui.note(authenticator.errorMessage);
        }

        function onPromptChanged() {
            ui.note(authenticator.prompt);
        }

        function onPromptForSecretChanged() {
            field.forceActiveFocus();
        }
    }

    Connections {
        target: root

        function onClearPassword() {
            PasswordSync.password = "";
        }
    }

    SessionManagement {
        id: session

        // nothing typed is left lying while the machine sleeps
        onAboutToSuspend: {
            root.clearPassword();
            ui.slept = true;
        }
    }

    KeyboardIndicator.KeyState {
        id: capsLock

        key: Qt.Key_CapsLock
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: ui.now = new Date()
    }

    Timer {
        id: idleTimer

        interval: 10000
        onTriggered: {
            if (field.text === "" && !ui.unlocked)
                ui.active = false;
        }
    }

    Timer {
        id: noteTimer

        interval: 3000
        onTriggered: root.notification = ""
    }

    // how long the field shows that the password was wrong
    Timer {
        id: failedTimer

        interval: 3000
    }

    Timer {
        id: graceTimer

        interval: 3000
        onTriggered: {
            root.clearPassword();
            authenticator.startAuthenticating();
        }
    }

    Component.onCompleted: field.forceActiveFocus()

    component Move: NumberAnimation {
        duration: ui.look.moveDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: ui.look.moveCurve
    }

    component Fade: NumberAnimation {
        duration: ui.look.fadeDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: ui.look.fadeCurve
    }

    // ---- pointer ---------------------------------------------------------

    MouseArea {
        // the first position is where the pointer already was
        property bool moved: false

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: ui.active ? Qt.ArrowCursor : Qt.BlankCursor
        onPressed: ui.wake()
        onPositionChanged: {
            if (moved)
                ui.wake();
            moved = true;
        }
    }

    // ---- wallpaper and clock ---------------------------------------------

    // the wallpaper steps back a little while the password is asked for
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: ui.active ? 0.3 : 0

        Behavior on opacity {
            Fade {
                duration: ui.look.moveDuration
            }
        }
    }

    Column {
        id: clock

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.36 - height / 2)
        spacing: 0
        layer.enabled: true
        // on any wallpaper: a soft shadow under the figures
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.7)
            shadowVerticalOffset: 2
            blurMax: 36
            shadowBlur: 0.8
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: ui.look.fg
            font.pixelSize: Math.round(ui.height * 0.16)
            font.weight: Font.Bold
            font.letterSpacing: -2
            text: Qt.formatTime(ui.now, "hh:mm")
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: ui.look.fg
            font.pixelSize: Math.max(16, Math.round(ui.height * 0.03))
            font.weight: Font.DemiBold
            text: ui.now.toLocaleDateString(Qt.locale(), Locale.LongFormat)
        }
    }

    // ---- frame -----------------------------------------------------------

    // The shell's frame and the two panels as one shape, drawn by the shell's
    // own shader (shell/shaders/frame.frag, copied in when this is installed),
    // with its shadow.
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.rgba(0, 0, 0, ui.look.shadowOpacity)
        }

        ShaderEffect {
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("frame.frag.qsb")

            readonly property vector2d resolution: Qt.vector2d(width, height)
            readonly property vector4d inner: Qt.vector4d(width / 2, height / 2, width / 2 - ui.look.frameBorder, height / 2 - ui.look.frameBorder)
            readonly property real innerRadius: ui.look.frameRounding
            readonly property real cornerRadius: ui.look.frameRounding
            readonly property real panelRadius: ui.look.panelRounding
            readonly property real smoothing: ui.look.panelSmoothing
            readonly property color color: ui.look.bg
            readonly property vector4d panel0: passwordPanel.blob
            readonly property vector4d panel1: actionPanel.blob
            readonly property vector4d panel2: Qt.vector4d(0, 0, 0, 0)
            readonly property vector4d panel3: Qt.vector4d(0, 0, 0, 0)
            readonly property vector4d panel4: Qt.vector4d(0, 0, 0, 0)
            readonly property vector4d bubble: Qt.vector4d(0, 0, 0, 0)
            readonly property real bubbleRadius: 0
            readonly property color bubbleColor: "transparent"
            readonly property real bubbleOpacity: 0
        }
    }

    // ---- password, from the top edge -------------------------------------

    Item {
        id: passwordPanel

        readonly property real w: 420
        readonly property real h: passwordContent.implicitHeight
        // 1 = behind the border, 0 = out; overshoots below 0 on the way out
        property real offset: ui.active ? 0 : 1
        readonly property bool hidden: offset >= 1
        // sideways, when the password was wrong
        property real shift: 0
        readonly property real edge: ui.look.frameBorder
        readonly property real leftX: Math.round((ui.width - w) / 2 / 3) * 3 + shift
        readonly property real slack: 36
        // what the frame's shader draws behind it: from inside the border to its lower edge
        readonly property vector4d blob: {
            const top = edge - ui.look.panelRounding;
            const bottom = edge + passwordBody.y + h;
            if (hidden || bottom <= edge)
                return Qt.vector4d(0, 0, 0, 0);
            return Qt.vector4d(leftX + w / 2, (top + bottom) / 2, w / 2, (bottom - top) / 2);
        }

        x: leftX - slack
        y: edge
        width: w + slack * 2
        height: h + slack
        clip: true
        visible: !hidden

        Behavior on offset {
            Move {}
        }

        SequentialAnimation {
            id: shake

            NumberAnimation {
                target: passwordPanel
                property: "shift"
                to: -15
                duration: 60
            }

            NumberAnimation {
                target: passwordPanel
                property: "shift"
                to: 15
                duration: 90
            }

            NumberAnimation {
                target: passwordPanel
                property: "shift"
                to: 0
                duration: 420
                easing.type: Easing.OutElastic
            }
        }

        Item {
            id: passwordBody

            x: passwordPanel.slack
            y: -(passwordPanel.h + ui.look.panelSmoothing) * passwordPanel.offset
            width: passwordPanel.w
            height: passwordPanel.h

            Column {
                id: passwordContent

                x: 12
                width: parent.width - 24
                topPadding: 12
                bottomPadding: 9
                spacing: 9

                // the field, as the command palette's: a pill
                Rectangle {
                    width: parent.width
                    height: 45
                    radius: height / 2
                    color: ui.look.surface
                    border.width: 1.5
                    border.color: ui.failed ? ui.look.error : "transparent"

                    Behavior on border.color {
                        ColorAnimation {
                            duration: ui.look.fadeDuration
                        }
                    }

                    // who: the user's picture, or the first letter of the name
                    Rectangle {
                        id: avatar

                        readonly property string picture: kscreenlocker_userImage !== "" ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/") : ""

                        anchors {
                            left: parent.left
                            leftMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        width: 33
                        height: 33
                        radius: width / 2
                        color: ui.look.accent

                        Text {
                            anchors.centerIn: parent
                            visible: face.status !== Image.Ready
                            color: ui.look.accentFg
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            text: kscreenlocker_userName.charAt(0).toUpperCase()
                        }

                        Image {
                            id: face

                            anchors.fill: parent
                            source: avatar.picture
                            sourceSize: Qt.size(99, 99)
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                        }

                        Rectangle {
                            id: round

                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                            layer.enabled: true
                        }

                        MultiEffect {
                            anchors.fill: parent
                            visible: face.status === Image.Ready
                            source: face
                            maskEnabled: true
                            maskSource: round
                        }
                    }

                    Text {
                        anchors {
                            left: field.left
                            right: field.right
                            verticalCenter: parent.verticalCenter
                        }
                        visible: field.text === ""
                        color: ui.look.fgDim
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        text: ui.unlocked ? "Unlocked" : "Password"
                    }

                    TextInput {
                        id: field

                        anchors {
                            left: avatar.right
                            leftMargin: 12
                            right: go.left
                            rightMargin: 9
                            verticalCenter: parent.verticalCenter
                        }
                        clip: true
                        focus: true
                        enabled: !ui.held
                        readOnly: ui.unlocked
                        opacity: ui.held ? 0.5 : 1
                        color: ui.look.fg
                        selectionColor: ui.look.accent
                        selectedTextColor: ui.look.accentFg
                        font.pixelSize: 14
                        font.letterSpacing: 3
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        passwordMaskDelay: 0
                        inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                        text: PasswordSync.password
                        onTextEdited: PasswordSync.password = text
                        onAccepted: ui.submit()

                        Keys.onEscapePressed: {
                            root.clearPassword();
                            if (!ui.unlocked)
                                ui.active = false;
                        }
                        // any key brings the panels out, and is typed as well;
                        // but the Enter that only brought them out is not an answer
                        Keys.onPressed: event => {
                            const first = !ui.active;
                            ui.wake();
                            event.accepted = first && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter);
                        }

                        Behavior on opacity {
                            Fade {}
                        }
                    }

                    Rectangle {
                        id: go

                        anchors {
                            right: parent.right
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        width: 33
                        height: 33
                        radius: width / 2
                        color: goMouse.containsMouse || field.text !== "" || ui.unlocked ? ui.look.accent : ui.look.surfaceHover

                        Behavior on color {
                            ColorAnimation {
                                duration: ui.look.fadeDuration
                            }
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: ui.look.iconSize
                            height: ui.look.iconSize
                            source: ui.unlocked ? "unlock-symbolic" : "go-next-symbolic"
                            isMask: true
                            color: goMouse.containsMouse || field.text !== "" || ui.unlocked ? ui.look.accentFg : ui.look.fgDim
                        }

                        MouseArea {
                            id: goMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                ui.wake();
                                ui.submit();
                            }
                        }
                    }
                }

                // below it, as the palette's last line: what is the matter, or
                // who is asked; and the keys
                Item {
                    width: parent.width
                    height: 21

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 9
                            right: hints.left
                            rightMargin: 9
                            verticalCenter: parent.verticalCenter
                        }
                        color: ui.failed ? ui.look.error : (ui.message !== "" ? ui.look.warning : ui.look.fgDim)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        text: ui.message !== "" ? ui.message.replace(/\n/g, "  ·  ") : kscreenlocker_userName
                    }

                    Row {
                        id: hints

                        anchors {
                            right: parent.right
                            rightMargin: 9
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 12

                        KeyHint {
                            look: ui.look
                            key: "↵"
                            text: "Unlock"
                        }

                        KeyHint {
                            look: ui.look
                            key: "esc"
                            text: ui.unlocked ? "" : "Clear"
                        }
                    }
                }
            }
        }
    }

    // ---- actions, from the bottom edge -----------------------------------

    Item {
        id: actionPanel

        readonly property real w: actionRow.implicitWidth + 18
        readonly property real h: 54
        property real offset: ui.active && actionRow.visibleChildren.length > 0 ? 0 : 1
        readonly property bool hidden: offset >= 1
        readonly property real edge: ui.height - ui.look.frameBorder
        readonly property real leftX: Math.round((ui.width - w) / 2 / 3) * 3
        readonly property real slack: 36
        readonly property vector4d blob: {
            const top = y + actionBody.y;
            const bottom = edge + ui.look.panelRounding;
            if (hidden || top >= edge)
                return Qt.vector4d(0, 0, 0, 0);
            return Qt.vector4d(leftX + w / 2, (top + bottom) / 2, w / 2, (bottom - top) / 2);
        }

        x: leftX - slack
        y: edge - height
        width: w + slack * 2
        height: h + slack
        clip: true
        visible: !hidden

        Behavior on offset {
            Move {}
        }

        Item {
            id: actionBody

            x: actionPanel.slack
            y: actionPanel.slack + (actionPanel.h + ui.look.panelSmoothing) * actionPanel.offset
            width: actionPanel.w
            height: actionPanel.h

            Row {
                id: actionRow

                anchors.centerIn: parent
                spacing: ui.look.spacing

                ActionButton {
                    look: ui.look
                    icon: "system-suspend-symbolic"
                    text: "Sleep"
                    visible: session.canSuspend
                    onClicked: session.suspend()
                }

                ActionButton {
                    look: ui.look
                    icon: "system-suspend-hibernate-symbolic"
                    text: "Hibernate"
                    visible: session.canHibernate
                    onClicked: session.hibernate()
                }

                ActionButton {
                    look: ui.look
                    icon: "system-switch-user-symbolic"
                    text: "Switch user"
                    visible: session.canSwitchUser
                    onClicked: session.switchUser()
                }
            }
        }
    }
}
