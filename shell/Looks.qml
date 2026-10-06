pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The looks the theme switcher shows: every theme with each of its
// backgrounds, and a theme without one once (looks.sh, which also makes the
// small pictures of the backgrounds). Listed at the shell's start, so the
// pictures are there when the switcher is first opened, and again each time
// it opens, for a background that was added since.
Singleton {
    id: root

    // { theme, file, path, thumb, colors }
    property var list: []
    // false until the first list has come
    property bool ready: false

    function refresh() {
        if (!lister.running)
            lister.running = true;
    }

    // where a look is in the list; -1 if it is not
    function indexOf(theme: string, file: string): int {
        const exact = list.findIndex(look => look.theme === theme && look.file === file);
        return exact >= 0 ? exact : list.findIndex(look => look.theme === theme);
    }

    Process {
        id: lister

        command: ["sh", Quickshell.shellPath("looks.sh"), Quickshell.shellPath("themes"), Themes.configDir + "/themes", (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/kde-quickshell/thumbnails"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const looks = JSON.parse(text);
                    // not assigned if the same: the switcher would start over
                    if (JSON.stringify(looks) !== JSON.stringify(root.list))
                        root.list = looks;
                } catch (error) {
                    console.warn("Looks: looks.sh gave no list", error);
                }
                root.ready = true;
            }
        }
    }

    Component.onCompleted: refresh()
}
