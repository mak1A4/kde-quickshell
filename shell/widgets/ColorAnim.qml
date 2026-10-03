import QtQuick
import qs

// Colour changes (hover, active state) fade instead of snapping.
ColorAnimation {
    duration: Theme.fadeDuration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.fadeCurve
}
