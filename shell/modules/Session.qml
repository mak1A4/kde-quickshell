import QtQuick
import QtQuick.Layouts
import qs
import qs.widgets
import qs.modules.session

// Opens the session menu: lock, sleep, log out, restart, shut down.
BarButton {
    id: root

    active: Popouts.current === "session"
    hintTitle: "Session"
    hintLines: ["Lock, sleep, restart, shut down"]
    onClicked: button => {
        if (button === Qt.LeftButton)
            Popouts.toggle("session", root, panel);
    }

    Component {
        id: panel

        SessionPanel {}
    }

    Icon {
        Layout.alignment: Qt.AlignHCenter
        source: "system-shutdown-symbolic"
    }
}
