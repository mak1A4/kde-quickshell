import QtQuick
import qs

// The one animation curve used for everything that moves.
NumberAnimation {
    duration: Theme.animDuration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.animCurve
}
