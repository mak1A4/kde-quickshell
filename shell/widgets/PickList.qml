import QtQuick
import qs

// A short list with one selected row, for the launcher and the command
// palette. It is as tall as its rows, up to `maxRows`. The delegate is the
// user's; it reports pointer movement to hover().
//
// One thing is animated: `highlightY`, the highlight's position in the list.
// For keyboard moves the scroll position is not animated separately but
// follows the highlight frame by frame (`following`), so the two cannot drift
// apart. (Animating both, the highlight fell behind on a held key and was
// dragged upward by the scrolling list.)
//
// A single press eases with the shell's curve. A held key glides at constant
// speed, one row per step, each step lasting as long as the gap between
// steps, which reads as continuous motion instead of hops.
ListView {
    id: root

    property int rowHeight: 54
    property int maxRows: 7
    // false hides the highlight, for a row that is a message, not a choice
    property bool highlighted: true

    // true while a key is held down and repeating
    property bool repeating: false
    // A held key steps at most this often (ms), whatever the keyboard's own
    // repeat rate: at the system rate the list ran past too fast to follow.
    readonly property int repeatInterval: 66
    property real lastRepeat: 0
    // measured time between the steps of a held key
    property int stepDuration: 80
    // the scroll position follows the highlight (keyboard), or not (pointer)
    property bool following: false
    // set to move the highlight without animation
    property bool jump: false

    property real highlightY: currentIndex * rowHeight

    Behavior on highlightY {
        enabled: !root.jump

        NumberAnimation {
            duration: root.repeating ? root.stepDuration : Theme.fadeDuration
            easing.type: root.repeating ? Easing.Linear : Easing.BezierSpline
            easing.bezierCurve: Theme.fadeCurve
        }
    }

    onHighlightYChanged: {
        if (!following)
            return;
        if (highlightY < contentY)
            contentY = highlightY;
        else if (highlightY + rowHeight > contentY + height)
            contentY = highlightY + rowHeight - height;
    }

    // Keyboard selection: moves the selection; the list scrolls to keep it in view.
    function step(by, autoRepeat) {
        if (count === 0)
            return;
        repeating = autoRepeat ?? false;
        if (repeating) {
            const now = Date.now();
            const since = now - lastRepeat;
            if (since < repeatInterval)
                return;
            lastRepeat = now;
            // the first repeat comes after the long initial delay; ignore that gap
            if (since < 250)
                stepDuration = since;
        }
        following = true;
        currentIndex = Math.max(0, Math.min(count - 1, currentIndex + by));
    }

    // Where the pointer was last seen, in window coordinates (x < 0: not yet).
    property point pointerAt: Qt.point(-1, -1)

    // Pointer selection, called for every hover report of a row. It acts only
    // when the pointer has really moved on screen. Rows sliding under a resting
    // pointer are reported as movement too (the pointer's position within the
    // row changes), and with the list gliding that happens every frame; acting
    // on those re-selects the row under the pointer and fights the keyboard.
    // Pointer selection never scrolls, see below.
    function hover(index, at) {
        const first = pointerAt.x < 0;
        const moved = Math.abs(at.x - pointerAt.x) >= 1 || Math.abs(at.y - pointerAt.y) >= 1;
        pointerAt = at;
        // the first report only says where the pointer rests: the list
        // usually opens right under it, and that must not select anything
        if (first || !moved)
            return;
        repeating = false;
        following = false;
        currentIndex = index;
    }

    // back to the first row, at the top, without gliding there
    function rewind() {
        jump = true;
        currentIndex = 0;
        contentY = 0;
        jump = false;
    }

    height: Math.min(count, maxRows) * rowHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // Only the wheel and the keyboard scroll. The list must not follow the
    // selection by itself (hovering a half-visible row would scroll it,
    // putting another row under the pointer, and so on), and dragging with
    // the mouse must not flick it.
    highlightRangeMode: ListView.NoHighlightRange
    acceptedButtons: Qt.NoButton
    // the wheel settles on whole rows
    snapMode: ListView.SnapToItem
    // the highlight is our own rectangle, so it can use the shell's curve
    highlightFollowsCurrentItem: false

    highlight: Rectangle {
        y: root.highlightY
        width: root.width
        height: root.rowHeight
        radius: 12
        color: Theme.surface
        visible: root.currentItem !== null && root.highlighted
    }
}
