import Quickshell
import QtQuick

// For the glass frame's blur: one strip of a fillet (BlurFillet.qml), a
// rectangle one pixel thick. `at` is { x, y, width, height }, or nothing.
Region {
    property var at: null

    x: at?.x ?? 0
    y: at?.y ?? 0
    width: at?.width ?? 0
    height: at?.height ?? 0
}
