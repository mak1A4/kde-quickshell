import QtQuick
import qs
import qs.widgets

// One column of the binary clock (BinaryTime.qml), flat: a dot for each bit
// of `number`, the lowest at the bottom. A lit one is solid, an unlit one
// smaller and faint, as the workspace switcher's dots are for desktops with
// and without windows (modules/Workspaces.qml).
//
// What moves: a dot coming on swells a little past its size and settles; and
// a wave, in which each dot in turn swells and settles, from the bottom up.
// One runs when the number changes, and whenever wave() is called.
Item {
    id: root

    required property int number
    // how many dots
    required property int count
    required property color tint
    required property real dot
    required property real gap

    signal waved

    function wave() {
        waved();
    }

    onNumberChanged: wave()

    implicitWidth: dot
    implicitHeight: dot * count + gap * (count - 1)

    Repeater {
        model: root.count

        Rectangle {
            id: dot

            required property int index
            readonly property bool lit: (root.number >> index) & 1
            property real size: lit ? root.dot : root.dot * 2 / 3
            // by a wave going through
            property real swell: 1

            x: (root.dot - size) / 2
            y: root.height - root.dot - index * (root.dot + root.gap) + (root.dot - size) / 2
            width: size
            height: size
            radius: size / 2
            color: root.tint
            opacity: lit ? 1 : 0.4
            scale: swell

            Behavior on size {
                Anim {}
            }

            SequentialAnimation {
                id: bump

                // the wave reaches a dot further up a little later
                PauseAnimation {
                    duration: dot.index * 45
                }

                NumberAnimation {
                    target: dot
                    property: "swell"
                    to: 1.3
                    duration: 150
                    easing.type: Easing.OutQuad
                }

                Anim {
                    target: dot
                    property: "swell"
                    to: 1
                }
            }

            Connections {
                target: root

                function onWaved() {
                    bump.restart();
                }
            }

            Behavior on opacity {
                Anim {
                    kind: Anim.Fade
                }
            }
        }
    }
}
