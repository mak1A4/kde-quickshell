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
// steps, which reads as continuous motion instead of hops. Under the pointer
// the highlight moves much faster (`Theme.followDuration`): the pointer is
// already on the row, and a highlight still on its way there reads as lag.
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
    // the last move came from the pointer, not from a key
    property bool pointing: false
    // set to move the highlight without animation
    property bool jump: false

    property real highlightY: currentIndex * rowHeight

    Behavior on highlightY {
        enabled: !root.jump

        NumberAnimation {
            duration: root.repeating ? root.stepDuration : (root.pointing ? Theme.followDuration : Theme.fadeDuration)
            easing.type: root.repeating ? Easing.Linear : (root.pointing ? Easing.OutCubic : Easing.BezierSpline)
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
        scroll.stop();
        following = true;
        pointing = false;
        keyedAt = pointerAt;
        currentIndex = Math.max(0, Math.min(count - 1, currentIndex + by));
    }

    // Where the pointer was last seen, in window coordinates (x < 0: not yet).
    property point pointerAt: Qt.point(-1, -1)
    // Where it was when a key last moved the selection. The pointer has to
    // travel `takeBack` away from there before it selects again: a mouse
    // lying next to a keyboard that is being typed on moves by a pixel or
    // two, and that put the selection back on the row under it.
    property point keyedAt: Qt.point(-1, -1)
    readonly property int takeBack: 6

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
        if (keyedAt.x >= 0) {
            if (Math.hypot(at.x - keyedAt.x, at.y - keyedAt.y) < takeBack)
                return;
            keyedAt = Qt.point(-1, -1);
        }
        repeating = false;
        following = false;
        pointing = true;
        currentIndex = index;
    }

    // back to the first row, at the top, without gliding there
    function rewind() {
        scroll.stop();
        jump = true;
        currentIndex = 0;
        contentY = 0;
        jump = false;
    }

    // ---- wheel -----------------------------------------------------------

    // The wheel moves the list by whole rows, one for each notch, and the
    // move is animated here. Left to ListView, a notch was a flick of some
    // 72 px with the speed of the turning added, on rows of 54 px that the
    // list then snapped to: now one row, now two, with a tug back or forward
    // at the end of each. A touchpad, which reports pixels, moves the list by
    // those and it settles on a row when the fingers rest.
    readonly property real scrollEnd: Math.max(0, count * rowHeight - height)
    // where the wheel has sent the list, which is ahead of where it is
    property real scrollGoal: 0
    // turning that has not added up to a notch yet (120 is one)
    property real wheelRest: 0

    function scrollBy(rows: int): void {
        // from where the list is going, not from where it is: the notches
        // of a quick turn each count, also while it is still moving
        const from = scroll.running ? scrollGoal : Math.round(contentY / rowHeight) * rowHeight;
        scrollGoal = Math.max(0, Math.min(scrollEnd, from + rows * rowHeight));
        scroll.to = scrollGoal;
        scroll.restart();
    }

    function wheel(event: var): void {
        if (scrollEnd <= 0)
            return;
        following = false;
        if (event.pixelDelta.y !== 0) {
            scroll.stop();
            contentY = Math.max(0, Math.min(scrollEnd, contentY - event.pixelDelta.y));
            settle.restart();
            return;
        }
        wheelRest += event.angleDelta.y;
        const notches = wheelRest > 0 ? Math.floor(wheelRest / 120) : Math.ceil(wheelRest / 120);
        if (notches === 0)
            return;
        wheelRest -= notches * 120;
        scrollBy(-notches);
    }

    NumberAnimation {
        id: scroll

        target: root
        property: "contentY"
        duration: Theme.followDuration * 2
        easing.type: Easing.OutCubic
    }

    // a touchpad's scrolling has ended: onto the nearest row
    Timer {
        id: settle

        interval: 120
        onTriggered: root.scrollBy(0)
    }

    WheelHandler {
        // the list's own flicking is not wanted: see above
        onWheel: event => root.wheel(event)
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
