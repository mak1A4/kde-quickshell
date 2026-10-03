import QtQuick
import qs

// Animation for anything that moves or resizes (the default), or for
// opacity (`kind: Anim.Fade`). See Theme for the curves.
NumberAnimation {
    enum Kind {
        Move,
        Fade
    }

    property int kind: Anim.Move

    duration: kind === Anim.Fade ? Theme.fadeDuration : Theme.moveDuration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: kind === Anim.Fade ? Theme.fadeCurve : Theme.moveCurve
}
