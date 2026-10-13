import QtQuick
import qs

// Animation for anything that moves or resizes (the default), for opacity
// (`kind: Anim.Fade`), or for a size or an opacity that answers the pointer
// being on it (`kind: Anim.Hover`, as quick as HoverAnim is for colours).
// See Theme for the curves.
NumberAnimation {
    enum Kind {
        Move,
        Fade,
        Hover
    }

    property int kind: Anim.Move

    duration: kind === Anim.Hover ? Theme.followDuration : (kind === Anim.Fade ? Theme.fadeDuration : Theme.moveDuration)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: kind === Anim.Move ? Theme.moveCurve : Theme.fadeCurve
}
